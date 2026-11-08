import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart' show PageResult;
import 'store.dart';

/// 一次同步的结果。
class SyncReport {
  const SyncReport({required this.shelfTotal, required this.shelfAdded, required this.historyTotal, required this.historyFilled, this.historyUpdated = 0, required this.at});

  final int shelfTotal;
  final int shelfAdded;
  final int historyTotal;
  final int historyFilled;

  /// 另一台设备读到了别的话，本机位置跟着换过去的条数。
  final int historyUpdated;
  final DateTime at;
}

/// 拷贝漫画账号：登录、保存登录凭证、把源站书架和浏览历史合并到本地。
///
/// - 只保存登录后拿到的凭证（token）和昵称，**不保存密码**。
/// - 同步是单向的：源站 → 本地。源站的「加入书架」接口还没打通，本地追更暂时写不回源站。
/// - 每次登录都会让旧凭证失效，短时间多次登录会被源站风控，所以凭证失效前不会自动重新登录。
class AccountService extends ChangeNotifier {
  AccountService._();

  static final instance = AccountService._();

  static const _kToken = 'account.token';
  static const _kName = 'account.name';
  static const _kUser = 'account.user';
  static const _kLastSync = 'account.lastSync';

  /// 打开或回到应用时，距上次同步超过这么久才自动同步。两台设备轮流读时要及时接上，所以不宜太长。
  static const autoInterval = Duration(minutes: 5);

  /// 一次同步最多拉取的书架 / 历史条数，避免超大书架一次请求太多页。
  static const maxItems = 500;

  /// 测试里关掉启动时的自动同步。
  static bool autoSync = true;

  late SharedPreferences _prefs;
  String? _token;
  String _name = '';
  String _user = '';
  DateTime? lastSync;
  bool busy = false;
  String? error;
  SyncReport? lastReport;

  bool get loggedIn => _token != null;

  /// 显示用：昵称，没有时用账号名。
  String get displayName => _name.isNotEmpty ? _name : _user;
  String get username => _user;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _token = _prefs.getString(_kToken);
    _name = _prefs.getString(_kName) ?? '';
    _user = _prefs.getString(_kUser) ?? '';
    final t = _prefs.getInt(_kLastSync);
    lastSync = t == null ? null : DateTime.fromMillisecondsSinceEpoch(t);
    error = null;
    lastReport = null;
    _reportedKey = null;
    _failedKey = null;
    _failedAt = null;
  }

  /// 登录成功后立即同步一次。失败时抛出 [ApiException]（消息可以直接给用户看）。
  Future<void> login(String username, String password) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final r = await MangaApi.instance.login(username.trim(), password);
      _token = r['token'] as String;
      _user = '${r['username'] ?? username}'.trim();
      _name = '${r['nickname'] ?? ''}'.trim();
      await _prefs.setString(_kToken, _token!);
      await _prefs.setString(_kUser, _user);
      await _prefs.setString(_kName, _name);
    } finally {
      busy = false;
      notifyListeners();
    }
    await sync();
  }

  /// 退出：只清掉本机保存的凭证。已经合并进书架的作品和阅读位置保留。
  Future<void> logout() async {
    _token = null;
    _name = '';
    _user = '';
    lastSync = null;
    lastReport = null;
    error = null;
    for (final k in [_kToken, _kName, _kUser, _kLastSync]) {
      await _prefs.remove(k);
    }
    notifyListeners();
  }

  String? _reportedKey;
  String? _failedKey;
  DateTime? _failedAt;

  /// 阅读器保存位置时调用：这一话还没上报过，就带凭证请求一次章节，让源站记进浏览历史，
  /// 另一台设备同步时就能接上。同一话只报一次；失败后 1 分钟内不重试。没登录时什么都不做。
  /// 只在真正读到这一话时调用（预载前后话不算），否则源站会以为已经读到下一话。
  Future<void> reportRead(String pathWord, String uuid) async {
    final token = _token;
    if (token == null) return;
    final key = '$pathWord/$uuid';
    if (key == _reportedKey) return;
    if (key == _failedKey && _failedAt != null && DateTime.now().difference(_failedAt!) < const Duration(minutes: 1)) return;
    _reportedKey = key;
    try {
      await MangaApi.instance.reportRead(pathWord, uuid, token);
      LibraryStore.instance.markReported(pathWord, uuid);
      _failedKey = null;
    } on ApiException {
      if (_reportedKey == key) _reportedKey = null;
      _failedKey = key;
      _failedAt = DateTime.now();
    }
  }

  /// 打开作品详情时调用：读浏览历史第一页，找到这部作品就按同步规则合并它的阅读位置，
  /// 「继续阅读」直接接上另一台设备读到的那一话。返回是否改了本机位置；失败不打扰用户。
  Future<bool> refreshComic(String pathWord) async {
    final token = _token;
    if (token == null) return false;
    try {
      final page = await MangaApi.instance.browsedComics(token, limit: 50);
      final h = page.list.where((r) => r.comic.pathWord == pathWord && r.chapterId != null).firstOrNull;
      if (h == null) return false;
      final merged = LibraryStore.instance.mergeRemoteHistory([(comic: h.comic, chapterId: h.chapterId!, chapterName: h.chapterName ?? '')]);
      return merged.filled + merged.updated > 0;
    } on ApiException {
      return false;
    }
  }

  /// 打开应用时调用：已登录且距上次同步足够久才同步，失败不打扰用户。
  Future<void> autoSyncIfDue() async {
    if (!autoSync || !loggedIn || busy) return;
    if (lastSync != null && DateTime.now().difference(lastSync!) < autoInterval) return;
    await sync();
  }

  /// 拉取源站书架和浏览历史，合并到本地。返回是否成功。
  Future<bool> sync() async {
    final token = _token;
    if (token == null || busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    try {
      final api = MangaApi.instance;
      final shelf = await _all((offset) => api.collectedComics(token, offset: offset));
      final history = await _all((offset) => api.browsedComics(token, offset: offset));
      final store = LibraryStore.instance;
      final added = store.mergeRemoteShelf(shelf.map((r) => r.comic));
      final merged = store.mergeRemoteHistory([
        for (final h in history)
          if (h.chapterId != null) (comic: h.comic, chapterId: h.chapterId!, chapterName: h.chapterName ?? ''),
      ]);
      lastSync = DateTime.now();
      await _prefs.setInt(_kLastSync, lastSync!.millisecondsSinceEpoch);
      lastReport = SyncReport(shelfTotal: shelf.length, shelfAdded: added, historyTotal: history.length, historyFilled: merged.filled, historyUpdated: merged.updated, at: lastSync!);
      return true;
    } on AuthExpired catch (e) {
      error = e.message;
      // 凭证已经作废，留着只会一直失败；书架和阅读位置不动。
      _token = null;
      await _prefs.remove(_kToken);
      return false;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  static Future<List<RemoteComic>> _all(Future<PageResult<RemoteComic>> Function(int offset) page) async {
    final out = <RemoteComic>[];
    while (out.length < maxItems) {
      final p = await page(out.length);
      out.addAll(p.list);
      if (p.list.isEmpty || !p.hasMore) break;
    }
    return out;
  }
}
