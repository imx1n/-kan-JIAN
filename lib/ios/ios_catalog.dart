import 'package:flutter/material.dart';

import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/motion.dart';
import 'ios_theme.dart';

/// 目录里的一章（与具体数据源无关，漫画小说都能用）。
class NovelTocEntry {
  const NovelTocEntry({required this.index, required this.name, this.badge = ''});

  /// 在整本目录里的序号（从 0 开始），用来跳章。
  final int index;
  final String name;

  /// 行尾的小标签，例如「特别篇」。
  final String badge;
}

/// 目录里的一卷。
class NovelTocSection {
  const NovelTocSection({required this.name, required this.entries});

  final String name;
  final List<NovelTocEntry> entries;
}

/// 分卷目录页。
///
/// 设计依据：`design/reader-ios26` 的 `catalog` 屏——顶部玻璃返回 + 居中标题 +
/// 右侧定位；下面一条「分组」筛选，选中项用浅色底；再下面是章节列表，正在读的
/// 一行底色高亮并在行尾标「在读」，已加书签的行尾显示书签图标。
///
/// 轻小说按「卷」分组：默认停在当前章所在的卷，水平滚动选择；选「全部」时按卷
/// 分段列出全部章节，段与段之间有卷名标题。
class IosCatalogPage extends StatefulWidget {
  const IosCatalogPage({
    super.key,
    required this.sections,
    required this.currentIndex,
    required this.title,
    this.bookmarkKey,
    this.onSelected,
  });

  final List<NovelTocSection> sections;
  final int currentIndex;

  /// 导航栏标题（书名）。
  final String title;

  /// 书签存储用的键；为空表示这个页面不显示书签。
  final String? bookmarkKey;

  /// 选中章节后的回调；为空时直接把序号 pop 回上一页。
  final ValueChanged<int>? onSelected;

  @override
  State<IosCatalogPage> createState() => _IosCatalogPageState();
}

class _IosCatalogPageState extends State<IosCatalogPage> {
  final _prefs = ReaderPrefs.instance;
  final _scroll = ScrollController();
  final _currentKey = GlobalKey();
  late int _volume;

  @override
  void initState() {
    super.initState();
    _volume = _volumeOf(widget.currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate(first: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 当前章属于哪一卷；找不到就显示「全部」。
  int _volumeOf(int chapterIndex) {
    for (var i = 0; i < widget.sections.length; i++) {
      if (widget.sections[i].entries.any((e) => e.index == chapterIndex)) return i;
    }
    return -1;
  }

  /// 滚动到当前章。第一次进入不播放滚动动画，免得页面一打开就在动。
  void _locate({bool first = false}) {
    final ctx = _currentKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.25,
      duration: first ? Duration.zero : const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _select(int index) {
    if (widget.onSelected != null) {
      widget.onSelected!(index);
      Navigator.of(context).maybePop();
    } else {
      Navigator.of(context).pop(index);
    }
  }

  /// 当前筛选下要显示的章节，按卷分组。
  List<(NovelTocSection, List<NovelTocEntry>)> get _visible {
    if (_volume < 0) {
      return [for (final s in widget.sections) (s, s.entries)];
    }
    final s = widget.sections[_volume];
    return [(s, s.entries)];
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final groups = widget.sections.length > 1;
    return Scaffold(
      backgroundColor: IosColors.bg,
      body: Stack(
        children: [
          ListView(
            controller: _scroll,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, top + 112, 20, bottom + 32),
            children: [
              if (groups) ...[_volumeChips(), const SizedBox(height: 16)],
              for (final (section, entries) in _visible) ...[
                if (_volume < 0) ...[_sectionHeader(section), const SizedBox(height: 8)],
                DecoratedBox(
                  decoration: BoxDecoration(color: IosColors.surface, borderRadius: BorderRadius.circular(18)),
                  child: Column(
                    children: [
                      for (var i = 0; i < entries.length; i++)
                        _row(entries[i], first: i == 0, last: i == entries.length - 1),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
          _navBar(top),
        ],
      ),
    );
  }

  Widget _navBar(double top) => Positioned(
        top: top + 4,
        left: 16,
        right: 16,
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                widget.title.isEmpty ? '目录' : widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: IosColors.ink),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: GlassButton(icon: 'chevronLeft', label: '返回', onTap: () => Navigator.maybePop(context)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Pressable(
                  onTap: _locate,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      AppIcon('locate', size: 16, color: IosColors.accent, stroke: 1.9),
                      const SizedBox(width: 4),
                      Text('定位', style: TextStyle(fontSize: 15, color: IosColors.accent)),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  /// 卷选择：只有超过一卷才出现，避免单卷作品多一行无意义的控件。
  Widget _volumeChips() => SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          children: [
            _chip('全部', widget.sections.fold<int>(0, (n, s) => n + s.entries.length), -1),
            for (var i = 0; i < widget.sections.length; i++) ...[
              const SizedBox(width: 6),
              _chip(widget.sections[i].name, widget.sections[i].entries.length, i),
            ],
          ],
        ),
      );

  Widget _chip(String name, int count, int index) {
    final on = _volume == index;
    return Pressable(
      haptic: true,
      onTap: () {
        setState(() => _volume = index);
        WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(color: on ? IosColors.accentSoft : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Center(
          widthFactor: 1,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                _shortVolumeName(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 15, color: on ? IosColors.accent : IosColors.muted, fontWeight: on ? FontWeight.w700 : FontWeight.w400),
              ),
            ),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 13, color: on ? IosColors.accent : IosColors.muted)),
          ]),
        ),
      ),
    );
  }

  /// 卷名通常写作「第二卷 这场青春，并没有另一个解。」，筛选条上只留能区分的那段。
  static String _shortVolumeName(String name) {
    final m = RegExp(r'^第[一二三四五六七八九十百零\d]+卷[\s　:：·、-]*').firstMatch(name);
    final rest = m == null ? name : name.substring(m.end);
    if (rest.isEmpty) return name;
    return rest.length > 10 ? '${rest.substring(0, 10)}…' : rest;
  }

  Widget _sectionHeader(NovelTocSection section) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(children: [
          Expanded(
            child: Text(
              section.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: IosColors.muted),
            ),
          ),
          Text('${section.entries.length} 章', style: TextStyle(fontSize: 13, color: IosColors.muted)),
        ]),
      );

  Widget _row(NovelTocEntry e, {required bool first, required bool last}) {
    final current = e.index == widget.currentIndex;
    final marked = widget.bookmarkKey != null && _prefs.isBookmarked(widget.bookmarkKey!, e.index);
    final radius = BorderRadius.vertical(
      top: first ? const Radius.circular(18) : Radius.zero,
      bottom: last ? const Radius.circular(18) : Radius.zero,
    );
    return Material(
      color: current ? IosColors.accentSoft : Colors.transparent,
      child: InkWell(
        key: current ? _currentKey : null,
        borderRadius: radius,
        onTap: () => _select(e.index),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: BoxDecoration(
            border: first || current ? null : Border(top: BorderSide(color: IosColors.line, width: .5)),
            borderRadius: radius,
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                e.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, color: current ? IosColors.accent : IosColors.ink, fontWeight: current ? FontWeight.w600 : FontWeight.w400),
              ),
            ),
            if (e.badge.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: IosColors.faint, borderRadius: BorderRadius.circular(5)),
                child: Text(e.badge, style: TextStyle(fontSize: 12, color: IosColors.muted)),
              ),
            ],
            const SizedBox(width: 8),
            if (current)
              Text('在读', style: TextStyle(fontSize: 13, color: IosColors.accent))
            else if (marked)
              AppIcon('bookmarkFilled', size: 15, color: IosColors.accent, stroke: 1.8)
            else
              AppIcon('chevronRight', size: 13, color: IosColors.muted, stroke: 2),
          ]),
        ),
      ),
    );
  }
}

/// 打开目录页并返回选中的章节序号；用户返回时为 null。
Future<int?> showIosCatalog(
  BuildContext context, {
  required List<NovelTocSection> sections,
  required int currentIndex,
  String title = '目录',
  String? bookmarkKey,
}) =>
    Navigator.of(context).push<int>(appRoute((_) => IosCatalogPage(
          sections: sections,
          currentIndex: currentIndex,
          title: title,
          bookmarkKey: bookmarkKey,
        )));
