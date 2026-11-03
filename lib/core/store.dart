import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'models.dart';

late SharedPreferences _prefs;

Future<void> initStores() async {
  _prefs = await SharedPreferences.getInstance();
  LibraryStore.instance._load();
  ReaderPrefs.instance._load();
}

enum ShelfKind { manga, novel }

/// 书架上的一本作品：阅读位置 + 追更状态。
class ShelfEntry {
  ShelfEntry({
    required this.id,
    required this.kind,
    required this.name,
    required this.cover,
    required this.author,
    this.group,
    this.chapterUuid,
    this.chapterName,
    this.chapterIndex,
    this.page = 0,
    this.pageCount = 0,
    this.progress = 0,
    this.status = '',
    this.latestChapter = '',
    this.latestUpdated = '',
    this.latestCount = 0,
    this.seenCount = 0,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// 漫画为 path_word；内置小说为固定 id。
  final String id;
  final ShelfKind kind;
  final String name;
  final String cover;
  final String author;
  String? group;
  String? chapterUuid;
  String? chapterName;

  /// 当前章节在分组里的序号（从 0 开始），用于详情页定位到所在分段。
  int? chapterIndex;
  int page;
  int pageCount;

  /// 当前章节内的阅读比例，0–1。
  double progress;
  int updatedAt;

  /// 以下来自 `comic2` 详情，由书架同步刷新。
  String status;
  String latestChapter;
  String latestUpdated;

  /// 所有分组章节总数（最新一次同步）。
  int latestCount;

  /// 用户上次看到这部作品时的章节总数。
  int seenCount;

  bool get started => chapterUuid != null;

  String get kindLabel => kind == ShelfKind.manga ? '漫画' : '轻小说';

  bool get finished => status.contains('完結') || status.contains('完结');

  /// 上次看过之后新增的章节数。
  int get newCount => latestCount > seenCount ? latestCount - seenCount : 0;

  bool get hasUpdate => kind == ShelfKind.manga && newCount > 0;

  String get placeLabel {
    if (!started) return '未开始';
    return '读到 $chapterName';
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'cover': cover,
        'author': author,
        'group': group,
        'chapterUuid': chapterUuid,
        'chapterName': chapterName,
        'chapterIndex': chapterIndex,
        'page': page,
        'pageCount': pageCount,
        'progress': progress,
        'updatedAt': updatedAt,
        'status': status,
        'latestChapter': latestChapter,
        'latestUpdated': latestUpdated,
        'latestCount': latestCount,
        'seenCount': seenCount,
      };

  factory ShelfEntry.fromJson(Map<String, dynamic> j) => ShelfEntry(
        id: j['id'] as String,
        kind: ShelfKind.values.byName(j['kind'] as String),
        name: j['name'] as String,
        cover: j['cover'] as String? ?? '',
        author: j['author'] as String? ?? '',
        group: j['group'] as String?,
        chapterUuid: j['chapterUuid'] as String?,
        chapterName: j['chapterName'] as String?,
        chapterIndex: j['chapterIndex'] as int?,
        page: j['page'] as int? ?? 0,
        pageCount: j['pageCount'] as int? ?? 0,
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        updatedAt: j['updatedAt'] as int?,
        status: j['status'] as String? ?? '',
        latestChapter: j['latestChapter'] as String? ?? '',
        latestUpdated: j['latestUpdated'] as String? ?? '',
        latestCount: j['latestCount'] as int? ?? 0,
        seenCount: j['seenCount'] as int? ?? 0,
      );
}

class LibraryStore extends ChangeNotifier {
  LibraryStore._();

  static final instance = LibraryStore._();

  static const _kShelf = 'shelf.v1';
  static const _kRead = 'read.v1';

  final _entries = <String, ShelfEntry>{};
  final _read = <String, Set<String>>{};

  void _load() {
    final raw = _prefs.getString(_kShelf);
    if (raw != null) {
      for (final e in (jsonDecode(raw) as List)) {
        final entry = ShelfEntry.fromJson(Map<String, dynamic>.from(e as Map));
        _entries[entry.id] = entry;
      }
    }
    final read = _prefs.getString(_kRead);
    if (read != null) {
      (jsonDecode(read) as Map).forEach((k, v) => _read[k as String] = Set<String>.from(v as List));
    }
  }

  void _save() {
    _prefs.setString(_kShelf, jsonEncode(_entries.values.map((e) => e.toJson()).toList()));
    _prefs.setString(_kRead, jsonEncode(_read.map((k, v) => MapEntry(k, v.toList()))));
    notifyListeners();
  }

  /// 最近阅读在前。
  List<ShelfEntry> get entries => _entries.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  ShelfEntry? entry(String id) => _entries[id];

  bool contains(String id) => _entries.containsKey(id);

  int get readChapterCount => _read.values.fold(0, (n, s) => n + s.length);

  void put(ShelfEntry entry) {
    _entries[entry.id] = entry;
    _save();
  }

  void remove(String id) {
    _entries.remove(id);
    _save();
  }

  /// 追更：加入书架，并把当前章节数记为已看过。
  void follow(ComicDetail d) {
    final e = _entries[d.comic.pathWord] ??
        ShelfEntry(
          id: d.comic.pathWord,
          kind: ShelfKind.manga,
          name: d.comic.name,
          cover: d.comic.cover,
          author: d.comic.authorText,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
    _entries[e.id] = e;
    applyRemote(d, seen: true);
  }

  /// 写入详情里的追更信息；[seen] 为 true 表示用户刚看过（打开了详情或阅读器），清掉“有更新”。
  void applyRemote(ComicDetail d, {bool seen = false, bool notify = true}) {
    final e = _entries[d.comic.pathWord];
    if (e == null) return;
    e
      ..status = d.status
      ..latestChapter = d.lastChapter
      ..latestUpdated = d.comic.updated
      ..latestCount = d.chapterCount;
    // 旧数据没有 seenCount，第一次同步时视为已看过，避免整部作品都显示成“新”。
    if (seen || e.seenCount == 0) e.seenCount = d.chapterCount;
    if (notify) _save();
  }

  /// 批量同步结束后统一保存一次。
  void commit() => _save();

  /// 记录阅读位置；作品不在书架时自动加入。
  void recordPosition({
    required String id,
    required ShelfEntry Function() create,
    required String chapterUuid,
    required String chapterName,
    int? chapterIndex,
    String? group,
    int page = 0,
    int pageCount = 0,
    required double progress,
  }) {
    final e = _entries[id] ?? create();
    e
      ..chapterUuid = chapterUuid
      ..chapterName = chapterName
      ..chapterIndex = chapterIndex ?? e.chapterIndex
      ..group = group ?? e.group
      ..page = page
      ..pageCount = pageCount
      ..progress = progress.clamp(0, 1)
      ..updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (e.latestCount > 0) e.seenCount = e.latestCount;
    _entries[id] = e;
    _save();
  }

  bool isRead(String id, String chapterUuid) => _read[id]?.contains(chapterUuid) ?? false;

  void markRead(String id, String chapterUuid) {
    if ((_read[id] ??= {}).add(chapterUuid)) _save();
  }

  /// 清除阅读记录：保留书架上的作品和追更状态，只清掉阅读位置和已读标记。
  void clearHistory() {
    for (final e in _entries.values) {
      e
        ..chapterUuid = null
        ..chapterName = null
        ..chapterIndex = null
        ..page = 0
        ..pageCount = 0
        ..progress = 0;
    }
    _read.clear();
    _save();
  }
}

/// 阅读外观（轻小说）、漫画阅读方式和其他小设置，跨页面持久化。
class ReaderPrefs extends ChangeNotifier {
  ReaderPrefs._();

  static final instance = ReaderPrefs._();

  static const _k = 'reader.v1';

  static const defaults = <String, Object>{
    'theme': 0,
    'brightness': 1.0,
    'font': 0,
    'fontSize': 19.0,
    'line': 1,
    'weight': 0,
    'margin': 1,
    'spacing': 0.0,
    'ink': 0,
    'mangaScroll': false,
    'mangaRtl': true,
    'mangaSaver': false,
    'mangaBrightness': 1.0,
    'proxy': AppConfig.defaultProxy,
    'shelfSort': 0,
    'lastShelfSync': 0,
    'lastUpdateCheck': 0,
    'skipVersion': '',
    'searchHistory': '',
  };

  final _v = Map<String, Object>.of(defaults);

  void _load() {
    final raw = _prefs.getString(_k);
    if (raw == null) return;
    (jsonDecode(raw) as Map).forEach((k, v) {
      if (defaults.containsKey(k) && v != null && v.runtimeType == defaults[k]!.runtimeType) {
        _v[k as String] = v as Object;
      } else if (defaults[k] is double && v is num) {
        _v[k as String] = v.toDouble();
      }
    });
  }

  T _get<T>(String k) => _v[k] as T;

  void _set(String k, Object v) {
    _v[k] = v;
    _prefs.setString(_k, jsonEncode(_v));
    notifyListeners();
  }

  int get theme => _get('theme');
  set theme(int v) => _set('theme', v);
  double get brightness => _get('brightness');
  set brightness(double v) => _set('brightness', v);
  int get font => _get('font');
  set font(int v) => _set('font', v);
  double get fontSize => _get('fontSize');
  set fontSize(double v) => _set('fontSize', v);
  int get line => _get('line');
  set line(int v) => _set('line', v);
  int get weight => _get('weight');
  set weight(int v) => _set('weight', v);
  int get margin => _get('margin');
  set margin(int v) => _set('margin', v);
  double get spacing => _get('spacing');
  set spacing(double v) => _set('spacing', v);
  int get ink => _get('ink');
  set ink(int v) => _set('ink', v);
  bool get mangaScroll => _get('mangaScroll');
  set mangaScroll(bool v) => _set('mangaScroll', v);
  bool get mangaRtl => _get('mangaRtl');
  set mangaRtl(bool v) => _set('mangaRtl', v);

  /// 省流画质：图片用 800px 高（接口默认 1500px）。
  bool get mangaSaver => _get('mangaSaver');
  set mangaSaver(bool v) => _set('mangaSaver', v);

  /// 漫画页面明暗，0.3–1；只模拟，不改系统亮度。
  double get mangaBrightness => _get('mangaBrightness');
  set mangaBrightness(double v) => _set('mangaBrightness', v);

  /// `host:port`，空串表示直连；重启后生效。
  String get proxy => _get('proxy');
  set proxy(String v) => _set('proxy', v.trim());

  /// 书架排序：0 最近阅读，1 更新时间。
  int get shelfSort => _get('shelfSort');
  set shelfSort(int v) => _set('shelfSort', v);

  int get lastShelfSync => _get('lastShelfSync');
  set lastShelfSync(int v) => _set('lastShelfSync', v);

  int get lastUpdateCheck => _get('lastUpdateCheck');
  set lastUpdateCheck(int v) => _set('lastUpdateCheck', v);

  /// 用户选择跳过的版本号（不带 v）。
  String get skipVersion => _get('skipVersion');
  set skipVersion(String v) => _set('skipVersion', v);

  List<String> get searchHistory {
    final raw = _get<String>('searchHistory');
    return raw.isEmpty ? const [] : raw.split('\n');
  }

  void addSearch(String q) {
    final list = [q, ...searchHistory.where((s) => s != q)].take(8).toList();
    _set('searchHistory', list.join('\n'));
  }

  void clearSearchHistory() => _set('searchHistory', '');

  /// 只恢复排版相关项，保留配色、亮度和漫画设置。
  void resetTypography() {
    for (final k in const ['font', 'fontSize', 'line', 'weight', 'spacing', 'ink']) {
      _v[k] = defaults[k]!;
    }
    _set('margin', defaults['margin']!);
  }
}

/// 省流画质把接口给的 `.h1500x.` 换成 `.h800x.`。
String imageUrlFor(String url, {required bool saver}) => saver ? url.replaceFirst('.h1500x.', '.h800x.') : url;
