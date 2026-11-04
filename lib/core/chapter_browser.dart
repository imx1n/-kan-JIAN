import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

/// 章节浏览：分组 + 每 100 条一段。详情页和阅读器里的目录共用。
class ChapterBrowser extends ChangeNotifier {
  ChapterBrowser(this.pathWord);

  static const rangeSize = 100;

  final String pathWord;
  List<ComicGroup> groups = const [];
  String group = 'default';
  bool descending = false;

  /// 当前分段在正序分段列表里的下标。
  int rangeIndex = 0;
  bool loading = false;
  String? error;

  final _cache = <String, List<Chapter>>{};
  int _generation = 0;

  int get groupCount => groups.where((g) => g.pathWord == group).firstOrNull?.count ?? 0;

  List<(int, int)> get ranges => chapterRanges(groupCount, size: rangeSize);

  (int, int)? get currentRange => ranges.isEmpty ? null : ranges[rangeIndex.clamp(0, ranges.length - 1)];

  /// 当前分段的章节；还没加载完返回 null。倒序时反转。
  List<Chapter>? get items {
    final r = currentRange;
    if (r == null) return const [];
    final list = _cache['$group@${r.$1}'];
    if (list == null) return null;
    return descending ? list.reversed.toList() : list;
  }

  /// 分段标签的显示顺序（倒序时从后往前），值为正序下标。
  List<int> get rangeOrder {
    final idx = [for (var i = 0; i < ranges.length; i++) i];
    return descending ? idx.reversed.toList() : idx;
  }

  static String rangeLabel((int, int) r) => '${r.$1 + 1}–${r.$1 + r.$2}';

  /// 用详情里的分组初始化；[locateIndex] 为在读章节的序号，会直接打开它所在的分段。
  void setGroups(List<ComicGroup> gs, {String? preferGroup, int? locateIndex}) {
    groups = gs;
    group = gs.any((g) => g.pathWord == preferGroup) ? preferGroup! : (gs.isEmpty ? 'default' : gs.first.pathWord);
    rangeIndex = locateIndex == null ? 0 : locateIndex ~/ rangeSize;
    _load();
  }

  /// 阅读器里的目录没有详情数据，先取一次详情拿分组。
  Future<void> init({String? preferGroup, int? locateIndex}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final d = await MangaApi.instance.detail(pathWord);
      setGroups(d.groups, preferGroup: preferGroup, locateIndex: locateIndex);
    } catch (e) {
      loading = false;
      error = e.toString();
      notifyListeners();
    }
  }

  void selectGroup(String g) {
    if (g == group) return;
    group = g;
    rangeIndex = descending ? ranges.length - 1 : 0;
    _load();
  }

  void selectRange(int i) {
    rangeIndex = i;
    _load();
  }

  void toggleOrder() {
    descending = !descending;
    notifyListeners();
  }

  void locate(int index, {String? inGroup}) {
    if (inGroup != null && groups.any((g) => g.pathWord == inGroup)) group = inGroup;
    rangeIndex = index ~/ rangeSize;
    _load();
  }

  Future<void> retry() => _load();

  Future<void> _load() async {
    final r = currentRange;
    if (r == null) {
      loading = false;
      notifyListeners();
      return;
    }
    final key = '$group@${r.$1}';
    if (_cache.containsKey(key)) {
      loading = false;
      error = null;
      notifyListeners();
      return;
    }
    final gen = ++_generation;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final page = await MangaApi.instance.chapters(pathWord, group, offset: r.$1, limit: r.$2);
      if (gen != _generation) return;
      _cache[key] = page.list;
    } catch (e) {
      if (gen != _generation) return;
      error = e.toString();
    } finally {
      if (gen == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }
}
