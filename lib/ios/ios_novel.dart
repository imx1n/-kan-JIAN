import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';
import '../data/sample_novel.dart';
import '../ui/icons.dart';
import 'ios_theme.dart';

/// 纸张：纸白、暖纸、深色。对应共享偏好里的配色下标 0 / 1 / 3（安卓的雾绿在 iOS 上按纸白显示）。
class _Paper {
  const _Paper(this.name, this.index, this.bg, this.ink, this.muted);

  final String name;
  final int index;
  final Color bg;
  final Color ink;
  final Color muted;

  bool get dark => index == 3;

  static const all = [
    _Paper('纸白', 0, Color(0xFFF3F2EE), Color(0xFF2A2B2F), Color(0xFF66676D)),
    _Paper('暖纸', 1, Color(0xFFEFE3CA), Color(0xFF4A3F31), Color(0xFF6E604B)),
    _Paper('深色', 3, Color(0xFF1B1C20), Color(0xFFDADAE0), Color(0xFFA6A7B0)),
  ];

  static _Paper of(int theme) => all.firstWhere((p) => p.index == theme, orElse: () => all.first);
}

TextStyle _bodyStyle(ReaderPrefs p, _Paper paper) {
  final base = p.font == 1 ? const TextStyle() : kIosSerif;
  return base.copyWith(fontSize: p.fontSize, height: p.lineHeight, color: paper.ink, letterSpacing: .3);
}

class IosNovelPage extends StatefulWidget {
  const IosNovelPage({super.key});

  @override
  State<IosNovelPage> createState() => _IosNovelPageState();
}

class _IosNovelPageState extends State<IosNovelPage> {
  final _p = ReaderPrefs.instance;
  final _store = LibraryStore.instance;
  final _scroll = ScrollController();
  final _bookmarks = <int>{};
  int _chapter = 0;
  double _progress = 0;
  bool _chrome = true;

  @override
  void initState() {
    super.initState();
    final e = _store.entry(SampleNovel.id);
    final saved = int.tryParse(e?.chapterUuid?.replaceFirst('c', '') ?? '');
    if (saved != null && saved < SampleNovel.chapters.length) {
      _chapter = saved;
      _progress = e!.progress;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients && _progress > 0) _scroll.jumpTo(_progress * _scroll.position.maxScrollExtent);
      setState(() {});
    });
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent));
    super.dispose();
  }

  void _onScroll() {
    final max = _scroll.position.maxScrollExtent;
    final v = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    if ((v - _progress).abs() > .005) setState(() => _progress = v);
  }

  void _save() => _store.recordPosition(
        id: SampleNovel.id,
        create: SampleNovel.createEntry,
        chapterUuid: 'c$_chapter',
        chapterName: '${SampleNovel.chapterLabels[_chapter]} · ${SampleNovel.chapters[_chapter].title}',
        progress: _progress,
      );

  void _goChapter(int i) {
    if (i < 0 || i >= SampleNovel.chapters.length) return;
    setState(() {
      _chapter = i;
      _progress = 0;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _save();
  }

  (int, int) _pages() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return (1, 1);
    final view = _scroll.position.viewportDimension;
    final total = ((_scroll.position.maxScrollExtent + view) / view).ceil().clamp(1, 999);
    return ((_progress * (total - 1)).round() + 1, total);
  }

  Future<void> _toc() async {
    final i = await showIosChoices(
      context,
      title: '目录',
      options: [for (var i = 0; i < SampleNovel.chapters.length; i++) '${SampleNovel.chapterLabels[i]}  ${SampleNovel.chapters[i].title}${_bookmarks.contains(i) ? '  · 书签' : ''}'],
      selected: _chapter,
    );
    if (i != null) _goChapter(i);
  }

  void _toggleBookmark() {
    final had = _bookmarks.contains(_chapter);
    setState(() => had ? _bookmarks.remove(_chapter) : _bookmarks.add(_chapter));
    HapticFeedback.selectionClick();
    showIosToast(context, had ? '已取消本章书签' : '已为本章添加书签', dark: _Paper.of(_p.theme).dark);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _p,
        builder: (context, _) {
          final paper = _Paper.of(_p.theme);
          SystemChrome.setSystemUIOverlayStyle((paper.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark).copyWith(statusBarColor: Colors.transparent));
          final ch = SampleNovel.chapters[_chapter];
          final style = _bodyStyle(_p, paper);
          final top = MediaQuery.paddingOf(context).top;
          final bottom = MediaQuery.paddingOf(context).bottom;
          final (page, pages) = _pages();
          final marked = _bookmarks.contains(_chapter);
          return PopScope(
            onPopInvokedWithResult: (_, _) => _save(),
            child: Scaffold(
              backgroundColor: paper.bg,
              body: Stack(children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _chrome = !_chrome),
                    child: NotificationListener<ScrollEndNotification>(
                      onNotification: (_) {
                        _save();
                        return false;
                      },
                      child: ListView(
                        controller: _scroll,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(28, top + 70, 28, bottom + 120),
                        children: [
                          Text(SampleNovel.chapterLabels[_chapter], style: TextStyle(fontSize: 13, color: paper.muted)),
                          const SizedBox(height: 6),
                          Text(ch.title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: paper.ink)),
                          const SizedBox(height: 22),
                          for (final para in ch.paragraphs)
                            Padding(
                              padding: EdgeInsets.only(bottom: style.fontSize! * .9),
                              child: Text('　　$para', style: style, textAlign: TextAlign.justify),
                            ),
                          const SizedBox(height: 18),
                          if (_chapter < SampleNovel.chapters.length - 1)
                            Center(child: TextAction(label: '下一章 · ${SampleNovel.chapters[_chapter + 1].title}', color: paper.ink, onTap: () => _goChapter(_chapter + 1)))
                          else
                            Center(child: Text('— 全文完 —', style: TextStyle(fontSize: 13, color: paper.muted))),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: (1 - _p.brightness) * .7)))),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  top: _chrome ? top + 4 : -100,
                  left: 16,
                  right: 16,
                  child: Row(children: [
                    GlassButton(icon: 'chevronLeft', label: '返回', dark: paper.dark, onTap: () => Navigator.maybePop(context)),
                    Expanded(child: Text(SampleNovel.title, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: paper.ink))),
                    GlassButton(icon: marked ? 'bookmarkFilled' : 'bookmark', label: marked ? '取消书签' : '添加书签', dark: paper.dark, color: marked ? IosColors.accent : null, onTap: _toggleBookmark),
                  ]),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: 16,
                  right: 16,
                  bottom: _chrome ? (bottom > 0 ? bottom - 4 : 16) : -120,
                  child: Glass(
                    dark: paper.dark,
                    radius: 30,
                    child: SizedBox(
                      height: 60,
                      child: Row(children: [
                        Expanded(child: _barButton('list', '目录', paper, _toc)),
                        Text('$page  /  $pages', style: TextStyle(fontSize: 15, color: paper.ink, fontFeatures: const [FontFeature.tabularFigures()])),
                        Expanded(
                          child: _barButton('settings', '阅读设置', paper, () {
                            showModalBottomSheet<void>(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (_) => const _AppearanceSheet());
                          }),
                        ),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      );

  Widget _barButton(String icon, String label, _Paper paper, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: SizedBox(
          height: 60,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            AppIcon(icon, size: 18, color: paper.ink, stroke: 1.7),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 15, color: paper.ink)),
          ]),
        ),
      );
}

/// 阅读外观（一级）→ 字体与排版（二级），同一个面板内切换。
class _AppearanceSheet extends StatefulWidget {
  const _AppearanceSheet();

  @override
  State<_AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<_AppearanceSheet> {
  final _p = ReaderPrefs.instance;
  bool _typography = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([_p, GlassScope.reduce]),
        builder: (context, _) => Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, MediaQuery.paddingOf(context).bottom + 8),
          child: Glass(
            radius: 32,
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 36, height: 5, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(3)))),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(.04, 0), end: Offset.zero).animate(a), child: child)),
                child: _typography ? _typographyPage() : _appearancePage(),
              ),
            ]),
          ),
        ),
      );

  Widget _header(String title, {bool back = false}) => Row(children: [
        if (back) ...[GlassButton(icon: 'chevronLeft', label: '返回阅读外观', onTap: () => setState(() => _typography = false)), const SizedBox(width: 10)],
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: IosColors.ink)),
        const Spacer(),
        TextAction(label: '完成', onTap: () => Navigator.pop(context)),
      ]);

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(color: IosColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(children: children),
      );

  Widget _appearancePage() {
    final fontName = _p.font == 1 ? '黑体' : '宋体';
    return Column(key: const ValueKey('appearance'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header('阅读外观'),
      const Padding(padding: EdgeInsets.fromLTRB(4, 14, 4, 8), child: Text('纸张', style: TextStyle(fontSize: 13, color: IosColors.muted))),
      Row(children: [
        for (final paper in _Paper.all) ...[
          if (paper != _Paper.all.first) const SizedBox(width: 10),
          Expanded(
            child: Pressable(
              haptic: true,
              semanticLabel: paper.name,
              onTap: () => _p.theme = paper.index,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 86,
                decoration: BoxDecoration(
                  color: paper.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _Paper.of(_p.theme) == paper ? IosColors.accent : const Color(0x14000000), width: _Paper.of(_p.theme) == paper ? 2 : 1),
                ),
                child: Stack(children: [
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('文', style: kIosSerif.copyWith(fontSize: 24, color: paper.ink)),
                      const SizedBox(height: 4),
                      Text(paper.name, style: TextStyle(fontSize: 12, color: paper.muted)),
                    ]),
                  ),
                  if (_Paper.of(_p.theme) == paper) const Positioned(top: 8, right: 8, child: AppIcon('check', size: 14, color: IosColors.accent, stroke: 2.4)),
                ]),
              ),
            ),
          ),
        ],
      ]),
      const SizedBox(height: 14),
      Pressable(
        onTap: () => setState(() => _typography = true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: IosColors.surface, borderRadius: BorderRadius.circular(18)),
          child: Row(children: [
            const AppIcon('type', size: 22, color: IosColors.ink),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('字体与排版', style: TextStyle(fontSize: 17, color: IosColors.ink)),
                const SizedBox(height: 2),
                Text('$fontName · ${_p.fontSize.round()} 磅', style: const TextStyle(fontSize: 13, color: IosColors.muted)),
              ]),
            ),
            const AppIcon('right', size: 14, color: IosColors.muted, stroke: 2),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      _card([
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            const Text('页面亮度', style: TextStyle(fontSize: 15, color: IosColors.ink)),
            const Spacer(),
            Text('${(_p.brightness * 100).round()}%', style: const TextStyle(fontSize: 15, color: IosColors.muted)),
          ]),
        ),
        SizedBox(width: double.infinity, child: CupertinoSlider(value: _p.brightness, min: .3, max: 1, activeColor: IosColors.accent, onChanged: (v) => _p.brightness = v)),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        const Padding(padding: EdgeInsets.only(left: 4), child: Text('减少透明度', style: TextStyle(fontSize: 17, color: IosColors.ink))),
        const Spacer(),
        CupertinoSwitch(value: _p.reduceTransparency, activeTrackColor: IosColors.accent, onChanged: GlassScope.set),
      ]),
    ]);
  }

  Widget _typographyPage() {
    final paper = _Paper.of(_p.theme);
    return Column(key: const ValueKey('typography'), mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header('字体与排版', back: true),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.only(left: 14),
        decoration: const BoxDecoration(border: Border(left: BorderSide(color: IosColors.line, width: 2))),
        child: Text('风穿过候车室，\n把时刻表的一角轻轻掀起。', style: _bodyStyle(_p, paper).copyWith(color: IosColors.ink, fontSize: _p.fontSize.clamp(16, 22))),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(4, 18, 4, 8), child: Text('阅读字体', style: TextStyle(fontSize: 13, color: IosColors.muted))),
      IosSegmented(options: const ['宋体', '黑体'], selected: _p.font == 1 ? 1 : 0, onChanged: (i) => _p.font = i),
      const SizedBox(height: 14),
      _card([
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            const Text('文字大小', style: TextStyle(fontSize: 15, color: IosColors.ink)),
            const Spacer(),
            Text('${_p.fontSize.round()} 磅', style: const TextStyle(fontSize: 15, color: IosColors.muted)),
          ]),
        ),
        SizedBox(width: double.infinity, child: CupertinoSlider(value: _p.fontSize, min: 16, max: 26, divisions: 10, activeColor: IosColors.accent, onChanged: (v) => _p.fontSize = v)),
        const Divider(height: 1, thickness: .5, color: IosColors.line),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            const Text('行间距', style: TextStyle(fontSize: 15, color: IosColors.ink)),
            const Spacer(),
            Text(_p.lineHeight.toStringAsFixed(2), style: const TextStyle(fontSize: 15, color: IosColors.muted)),
          ]),
        ),
        SizedBox(width: double.infinity, child: CupertinoSlider(value: _p.lineHeight, min: 1.4, max: 2.2, divisions: 16, activeColor: IosColors.accent, onChanged: (v) => _p.lineHeight = v)),
      ]),
      const SizedBox(height: 8),
      Center(child: TextAction(label: '恢复默认排版', onTap: _p.resetTypography)),
    ]);
  }
}
