import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../core/api.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

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

/// 把第 [index] 条章节滚到视口里。列表是懒构建的，远处的行还不存在，
/// 所以先按固定行高 [rowExtent] 从第一行的位置估算并跳过去，再对齐到真实的行。
Future<void> revealChapterRow({required GlobalKey firstKey, required GlobalKey targetKey, required int index, required double rowExtent}) async {
  final built = targetKey.currentContext;
  if (built != null) {
    await Scrollable.ensureVisible(built, alignment: .35, duration: const Duration(milliseconds: 250));
    return;
  }
  final first = firstKey.currentContext;
  final box = first?.findRenderObject();
  if (first == null || box is! RenderBox || !box.attached) return;
  final position = Scrollable.of(first).position;
  final firstOffset = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
  final to = (firstOffset + index * rowExtent - position.viewportDimension * .35).clamp(position.minScrollExtent, position.maxScrollExtent);
  position.jumpTo(to);
  await WidgetsBinding.instance.endOfFrame;
  final target = targetKey.currentContext;
  if (target != null && target.mounted) await Scrollable.ensureVisible(target, alignment: .35, duration: const Duration(milliseconds: 200));
}

/// 下划线页签（分组切换）。
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({super.key, required this.labels, required this.selected, required this.onSelect, this.dark = false});

  /// (名称, 计数)
  final List<(String, int)> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final on = dark ? Palette.rInk : Palette.ink;
    final off = dark ? Palette.rInk2 : Palette.ink2;
    final count = dark ? Palette.rMute : Palette.ink3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: dark ? Palette.rLine : Palette.line))),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: InkWell(
              onTap: () => onSelect(i),
              child: Container(
                height: 44,
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == selected ? on : Colors.transparent, width: 2))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(labels[i].$1, style: TextStyle(fontSize: 14, color: i == selected ? on : off, fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400)),
                  const SizedBox(width: 5),
                  Text('${labels[i].$2}', style: TextStyle(fontSize: 12, color: count)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

/// 分段胶囊：1–100、101–200……
class RangeChips extends StatelessWidget {
  const RangeChips({super.key, required this.browser, this.dark = false});

  final ChapterBrowser browser;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final order = browser.rangeOrder;
    if (order.length <= 1) return const SizedBox(height: 4);
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
        itemCount: order.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final idx = order[i];
          final on = idx == browser.rangeIndex.clamp(0, browser.ranges.length - 1);
          final fg = dark ? (on ? Palette.rBg : Palette.rInk2) : (on ? Palette.onInk : Palette.ink2);
          final bg = dark ? (on ? Palette.rInk : Colors.transparent) : (on ? Palette.ink : Colors.transparent);
          final side = dark ? Palette.rLine : Palette.line;
          return Material(
            color: bg,
            shape: StadiumBorder(side: on ? BorderSide.none : BorderSide(color: side)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => browser.selectRange(idx),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(child: Text(ChapterBrowser.rangeLabel(browser.ranges[idx]), style: TextStyle(fontSize: 13, color: fg, fontWeight: on ? FontWeight.w500 : FontWeight.w400))),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 一条章节：序号、名称、标签（特别篇/公告）、已读勾；在读的那一条单独成卡并显示页数进度。
class ChapterTile extends StatelessWidget {
  const ChapterTile({
    super.key,
    required this.chapter,
    required this.number,
    required this.read,
    required this.onTap,
    this.current,
    this.locked = false,
    this.dark = false,
  });

  final Chapter chapter;

  /// 显示用序号（从 1 开始）。
  final int number;
  final bool read;
  final VoidCallback onTap;

  /// 在读时传入书架条目，用于显示页数进度。
  final ShelfEntry? current;
  final bool locked;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final tag = chapterTag(chapter.name);
    final ink = dark ? Palette.rInk : Palette.ink;
    final muted = dark ? Palette.rMute : Palette.ink3;
    final no = Text('$number', style: TextStyle(fontSize: 12, color: current != null ? (dark ? Palette.rThumb : Palette.accent) : muted, fontFeatures: const [FontFeature.tabularFigures()]));
    if (current != null) {
      final e = current!;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Material(
          color: dark ? const Color(0xFF26372E) : Palette.tonal,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: dark ? 0 : 12),
              child: dark
                  ? SizedBox(
                      height: 48,
                      child: Row(children: [
                        SizedBox(width: 34, child: no),
                        Expanded(child: Text(chapter.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w600))),
                        Pill(e.pageCount > 0 ? '在读 ${e.page + 1}/${e.pageCount}' : '在读', background: Palette.rThumb, color: Palette.rBg, bold: true),
                      ]),
                    )
                  : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(padding: const EdgeInsets.only(top: 2), child: SizedBox(width: 34, child: no)),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(chapter.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
                            const SizedBox(width: 8),
                            const Pill('在读', background: Palette.tonal2, color: Palette.sageInk, bold: true),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Text(e.pageCount > 0 ? '第 ${e.page + 1} / ${e.pageCount} 页' : '已开始', style: const TextStyle(fontSize: 12, color: Palette.sageInk)),
                            const SizedBox(width: 12),
                            Expanded(child: ProgressLine(e.progress)),
                          ]),
                        ]),
                      ),
                    ]),
            ),
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: SizedBox(
          height: 48,
          child: Row(children: [
            SizedBox(width: 34, child: no),
            Expanded(child: Text(chapter.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: read ? muted : ink))),
            if (tag.isNotEmpty) ...[
              const SizedBox(width: 8),
              Pill(tag, background: dark ? Palette.rLine : Palette.tonal, color: dark ? Palette.rInk2 : Palette.ink2),
            ],
            const SizedBox(width: 8),
            SizedBox(
              width: 18,
              child: locked
                  ? AppIcon('lock', size: 15, color: muted)
                  : read
                      ? AppIcon('check', size: 15, color: muted, stroke: 1.8)
                      : null,
            ),
          ]),
        ),
      ),
    );
  }
}

/// 章节区底部：加载骨架 / 错误重试。
class ChapterListStatus extends StatelessWidget {
  const ChapterListStatus({super.key, required this.browser, this.dark = false});

  final ChapterBrowser browser;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (browser.error != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Text(browser.error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: dark ? Palette.rInk2 : Palette.ink2)),
          const SizedBox(height: 8),
          TextButton(onPressed: browser.retry, style: TextButton.styleFrom(foregroundColor: dark ? Palette.rInk : Palette.ink), child: const Text('重试')),
        ]),
      );
    }
    if (browser.loading || browser.items == null) {
      // 深色面板里浅色骨架太跳，用转圈。
      if (dark) return const SizedBox(height: 120, child: LoadingView(color: Palette.rInk2));
      return Column(children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            child: Row(children: [
              const Skeleton(width: 22, height: 12),
              const SizedBox(width: 12),
              Expanded(child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: .4 + (i % 3) * .15, child: const Skeleton(height: 14))),
            ]),
          ),
      ]);
    }
    if (browser.items!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('这个分组还没有章节', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: dark ? Palette.rInk2 : Palette.ink3)),
      );
    }
    return const SizedBox(height: 8);
  }
}
