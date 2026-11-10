import 'dart:async';
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

/// 轻小说在书架里的 id：`wenku-<aid>`。内置示例小说用的是固定 id，两者不会撞。
String wenkuIdOf(int aid) => 'wenku-$aid';

/// 从书架 id 还原源站的书号；不是轻小说时返回 null。
int? wenkuAidOf(String id) => id.startsWith('wenku-') ? int.tryParse(id.substring(6)) : null;

/// 一部作品的阅读位置和追更状态。只有 [followed] 的作品出现在书架上、参与追更同步。
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
    this.followed = true,
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

  /// 是否追更。只读过、没点追更的作品只保留阅读位置。
  bool followed;

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
        'followed': followed,
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
        // 旧数据没有这个字段，都视为已追更，书架内容不变。
        followed: j['followed'] as bool? ?? true,
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
    _entries.clear();
    _read.clear();
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

  /// 书架上的作品（已追更），最近阅读在前。
  List<ShelfEntry> get entries => _entries.values.where((e) => e.followed).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// 阅读位置和追更信息；没追更但读过的作品也有。
  ShelfEntry? entry(String id) => _entries[id];

  bool isFollowed(String id) => _entries[id]?.followed ?? false;

  int get readChapterCount => _read.values.fold(0, (n, s) => n + s.length);

  void put(ShelfEntry entry) {
    _entries[entry.id] = entry;
    _save();
  }

  /// 取消追更：移出书架。读过的作品保留阅读位置，下次打开还能接着读。
  void unfollow(String id) {
    final e = _entries[id];
    if (e == null) return;
    if (e.started) {
      e.followed = false;
    } else {
      _entries.remove(id);
    }
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
    _entries[e.id] = e..followed = true;
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

  /// 记录阅读位置。第一次读的作品由 [create] 建一条记录（不追更，不进书架）。
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

  /// 合并源站书架：都记为追更。本地已有的作品保留阅读位置；新作品排在最近阅读之后，
  /// 追更信息由下一次书架同步补齐（[applyRemote] 第一次同步不会把它们标成「有更新」）。返回新加入书架的数量。
  int mergeRemoteShelf(Iterable<ComicBrief> comics) {
    var added = 0;
    for (final c in comics) {
      if (c.pathWord.isEmpty) continue;
      final e = _entries[c.pathWord];
      if (e == null) {
        _entries[c.pathWord] = ShelfEntry(id: c.pathWord, kind: ShelfKind.manga, name: c.name, cover: c.cover, author: c.authorText, updatedAt: 1);
        added++;
      } else if (!e.followed) {
        e.followed = true;
        added++;
      }
    }
    if (added > 0) _save();
    return added;
  }

  /// 合并源站轻小说书架（[Wenku8] 官方站）。都记为已加入书架；本地已有的保留阅读位置。
  /// 源站给的是章节名而不是章节 id，所以只在本地还没读过时用来定位「读到哪一章」。
  /// 返回新加入书架的数量。
  int mergeWenkuShelf(Iterable<({int aid, String name, String author, String bookmark})> items) {
    var added = 0;
    for (final i in items) {
      final id = wenkuIdOf(i.aid);
      final existing = _entries[id];
      final e = existing ??
          ShelfEntry(
            id: id,
            kind: ShelfKind.novel,
            name: i.name,
            cover: 'https://img.wenku8.com/image/${i.aid ~/ 1000}/${i.aid}/${i.aid}s.jpg',
            author: i.author,
            updatedAt: 1,
          );
      if (existing == null || !e.followed) added++;
      e.followed = true;
      _entries[id] = e;
      if (!e.started && i.bookmark.isNotEmpty) e.chapterName = i.bookmark;
    }
    _save();
    return added;
  }

  /// 合并源站浏览历史：只给本地还没读过的作品补上「读到哪一话」，本地记录更精确（有页码），不覆盖。
  /// 没在书架上的作品只记阅读位置、不追更。返回补上阅读位置的数量。
  int mergeRemoteHistory(Iterable<({ComicBrief comic, String chapterId, String chapterName})> items) {
    var filled = 0;
    for (final h in items) {
      final c = h.comic;
      if (c.pathWord.isEmpty) continue;
      final e = _entries[c.pathWord] ??= ShelfEntry(id: c.pathWord, kind: ShelfKind.manga, name: c.name, cover: c.cover, author: c.authorText, followed: false, updatedAt: 1);
      if (e.started) continue;
      e
        ..chapterUuid = h.chapterId
        ..chapterName = h.chapterName
        ..page = 0
        ..pageCount = 0
        ..progress = 0;
      filled++;
    }
    if (filled > 0) _save();
    return filled;
  }

  bool isRead(String id, String chapterUuid) => _read[id]?.contains(chapterUuid) ?? false;

  void markRead(String id, String chapterUuid) {
    if ((_read[id] ??= {}).add(chapterUuid)) _save();
  }

  /// 清除阅读记录：保留书架上的作品和追更状态，只清掉阅读位置和已读标记。
  void clearHistory() {
    _entries.removeWhere((_, e) => !e.followed);
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
    // 漫画阅读模式，沿用 PMX 的划分：
    // 0 单页·从左向右，1 单页·从右向左，2 单页·从上向下，3 单页·从下向上，4 条漫。
    'mangaMode': 0,
    // 手势分区：0 关闭（只有中间切换控件），1 自适应，2 左右三分，3 L 形。
    'mangaArea': 1,
    // 首次进入阅读器时的分区提示遮罩是否已看过。
    'mangaTipSeen': false,
    // 预取页数：当前页前/后各预加载几页。
    'mangaPrefetch': 3,
    'mangaSaver': false,
    // 图片适配：0 自动，1 适应宽度，2 适应高度，3 适应屏幕，4 原始尺寸。
    // 对应 PageFit.fromValue。
    'mangaFit': 0,
    'mangaBrightness': 1.0,
    'proxy': AppConfig.defaultProxy,
    'shelfSort': 0,
    // 书架顶层分区：0 漫画，1 轻小说。下次进来还停在同一个区。
    'shelfSection': 0,
    'lastShelfSync': 0,
    'lastUpdateCheck': 0,
    // 每次启动自动检查更新；用户可以在「我的」里关掉。
    'autoUpdate': true,
    'skipVersion': '',
    'searchHistory': '',
    'lineHeight': 1.85,
    // 小说翻页方式：true 左右翻页，false 整章上下滚动。
    'novelPaged': true,
    'reduceTransparency': false,
    'appearance': 0,
    // 线路：0 自动，1 固定线路，2 自定义基址。
    'apiMode': 0,
    'apiRoute': 'hotmangas',
    'apiCustom': '',
    // 轻小说书签：`书号:章节序号` 换行分隔。
    'novelBookmarks': '',
  };

  final _v = Map<String, Object>.of(defaults);

  void _load() {
    _v
      ..clear()
      ..addAll(defaults);
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

  /// 落盘去抖。拖动滑块时每帧都会 `_set`，如果每次都 `jsonEncode` 整张表
  /// 再走平台通道写盘，主线程会被写盘啃掉——这就是「亮度滑一下很卡」。
  /// 现在内存里立刻生效、立刻通知，写盘合并到 320ms 后一次。
  Timer? _saveTimer;

  /// 是否合并写盘。真机上是 true（拖动滑块时别每帧写盘）；
  /// 测试里设成 false，否则用例结束时会有个挂着的定时器。
  static bool debounce = true;

  void _set(String k, Object v) {
    // 值没变就不通知。拖滑块时同一档会重复回调，没必要让整棵树重建。
    if (_v[k] == v) return;
    _v[k] = v;
    notifyListeners();
    if (!debounce) {
      _flush();
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 320), _flush);
  }

  /// 立刻写盘（退出阅读器、切后台这类时机用）。
  void flush() => _flush();

  void _flush() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _prefs.setString(_k, jsonEncode(_v));
  }

  int get theme => _get('theme');
  set theme(int v) => _set('theme', v);
  double get brightness => _get('brightness');
  set brightness(double v) => _set('brightness', v);
  int get font => _get('font');
  set font(int v) => _set('font', v);
  double get fontSize => _get('fontSize');
  set fontSize(double v) => _set('fontSize', v);
  /// 漫画阅读模式：
  /// 0 单页·从左向右，1 单页·从右向左，2 单页·从上向下，3 单页·从下向上，
  /// 4 条漫·无缝，5 条漫·留白。
  ///
  /// 划分参考 PasteMangaX（`ComicCategories.READER_MODE_*`）：它把「单页」按横/纵、
  /// 正/反拆成四种，交互差异全部由手势分区和目标位置算出来，代码里只有一套翻页逻辑。
  int get mangaMode => _get('mangaMode');
  set mangaMode(int v) => _set('mangaMode', v.clamp(0, 5));

  /// 是否条漫（连续纵向滚动）。4 无缝、5 留白都是条漫。
  bool get mangaScroll => mangaMode >= 4;
  // 已经是条漫时保持原来的 4/5，不要在切换别的开关时把它打回 4。
  set mangaScroll(bool v) => mangaMode = v ? (mangaScroll ? mangaMode : 4) : 0;

  /// 是否从右向左翻（日漫顺序）。仅对横向模式有意义。
  bool get mangaRtl => mangaMode == 1 || mangaMode == 3;
  set mangaRtl(bool v) => mangaMode = v ? (mangaScroll ? mangaMode : 1) : (mangaScroll ? mangaMode : 0);

  /// 竖向翻页（上下翻，不是左右）。条漫也是竖向阅读。
  bool get mangaVertical => mangaMode == 2 || mangaMode == 3 || mangaMode >= 4;

  /// 翻页方向反过来：从下向上 / 从右向左。
  bool get mangaReversed => mangaMode == 1 || mangaMode == 3;

  /// 手势分区：0 关闭，1 自适应，2 左右三分，3 L 形，4 边缘，5 Kindle 式。
  int get mangaArea => _get('mangaArea');
  set mangaArea(int v) => _set('mangaArea', v.clamp(0, 5));

  /// 首次进入阅读器时是否已经展示过手势分区提示。
  bool get mangaTipSeen => _get('mangaTipSeen');
  set mangaTipSeen(bool v) => _set('mangaTipSeen', v);

  /// 预取页数：当前页前后各预加载几页。
  int get mangaPrefetch => _get('mangaPrefetch');
  set mangaPrefetch(int v) => _set('mangaPrefetch', v.clamp(1, 8));

  /// 省流画质：图片用 800px 高（接口默认 1500px）。
  bool get mangaSaver => _get('mangaSaver');
  set mangaSaver(bool v) => _set('mangaSaver', v);

  /// 图片适配方式，取值见 `PageFit.fromValue`。
  int get mangaFit => _get('mangaFit');
  set mangaFit(int v) => _set('mangaFit', v.clamp(0, 4));


  /// 漫画页面明暗，0.3–1；只模拟，不改系统亮度。
  double get mangaBrightness => _get('mangaBrightness');
  set mangaBrightness(double v) => _set('mangaBrightness', v);

  /// `host:port`，空串表示直连；重启后生效。
  String get proxy => _get('proxy');
  set proxy(String v) => _set('proxy', v.trim());

  /// 书架排序：0 最近阅读，1 更新时间。
  int get shelfSort => _get('shelfSort');
  set shelfSort(int v) => _set('shelfSort', v);

  /// 书架顶层分区：0 漫画，1 轻小说。
  ///
  /// 和 [shelfSort] 不同，这两个区各有自己的筛选维度：漫画有「有更新 / 连载中 /
  /// 已完结」，轻小说只有「全部 / 在读」。所以分区必须是独立的顶层状态，
  /// 不能塞进筛选条里当第六个选项。
  int get shelfSection => _get('shelfSection');
  set shelfSection(int v) => _set('shelfSection', v.clamp(0, 1));

  int get lastShelfSync => _get('lastShelfSync');
  set lastShelfSync(int v) => _set('lastShelfSync', v);

  int get lastUpdateCheck => _get('lastUpdateCheck');
  set lastUpdateCheck(int v) => _set('lastUpdateCheck', v);

  /// 每次启动自动检查更新；关掉后只有手动「检查更新」才查。
  bool get autoUpdate => _get('autoUpdate');
  set autoUpdate(bool v) => _set('autoUpdate', v);

  /// 用户选择跳过的版本号（不带 v）。
  String get skipVersion => _get('skipVersion');
  set skipVersion(String v) => _set('skipVersion', v);

  /// iOS 小说排版的连续行距（安卓用 [line] 的三档）。
  double get lineHeight => _get('lineHeight');
  set lineHeight(double v) => _set('lineHeight', v);

  /// 小说翻页方式：true 左右翻页（默认，和设计稿的页码一致），false 整章上下滚动。
  bool get novelPaged => _get('novelPaged');
  set novelPaged(bool v) => _set('novelPaged', v);

  /// 一本书的书签（章节序号集合）。[key] 用书号，轻小说和示例小说分开存。
  Set<int> novelBookmarks(String key) {
    final raw = _get<String>('novelBookmarks');
    if (raw.isEmpty) return <int>{};
    return {
      for (final line in raw.split('\n'))
        if (line.startsWith('$key:')) ...{int.tryParse(line.substring(key.length + 1)) ?? -1},
    }..remove(-1);
  }

  bool isBookmarked(String key, int chapter) => novelBookmarks(key).contains(chapter);

  /// 切换一章的书签，返回切换后的状态。
  bool toggleBookmark(String key, int chapter) {
    final all = {for (final line in _get<String>('novelBookmarks').split('\n')) if (line.isNotEmpty) line};
    final tag = '$key:$chapter';
    final on = !all.contains(tag);
    if (on) {
      all.add(tag);
    } else {
      all.remove(tag);
    }
    _set('novelBookmarks', all.join('\n'));
    return on;
  }

  /// iOS「减少透明度」：玻璃控件改为实底。
  /// 外观：0 跟随系统、1 浅色、2 深色。
  int get appearance => _get('appearance');
  set appearance(int v) => _set('appearance', v);

  /// 线路模式：0 自动（启动时测速选最快）、1 固定线路、2 自定义基址。
  int get apiMode => _get('apiMode');
  set apiMode(int v) => _set('apiMode', v.clamp(0, 2));

  /// 固定模式下的线路 id（见 `AppConfig.routes`）。
  String get apiRoute => _get('apiRoute');
  set apiRoute(String v) => _set('apiRoute', v);

  /// 自定义基址，例如自建反代 `https://api.example.com`；空串表示未填。
  String get apiCustom => _get('apiCustom');
  set apiCustom(String v) => _set('apiCustom', v.trim());

  bool get reduceTransparency => _get('reduceTransparency');
  set reduceTransparency(bool v) => _set('reduceTransparency', v);

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
    for (final k in const ['font', 'fontSize']) {
      _v[k] = defaults[k]!;
    }
    _set('lineHeight', defaults['lineHeight']!);
  }
}

/// 省流画质把接口给的 `.h1500x.` 换成 `.h800x.`。
String imageUrlFor(String url, {required bool saver}) => saver ? url.replaceFirst('.h1500x.', '.h800x.') : url;
