import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';
import '../data/sample_novel.dart';
import '../ui/icons.dart';
import '../ui/widgets.dart';
import 'reader_settings_sheet.dart';

/// 轻小说阅读：正文优先，点按正文显示/收起上下两层工具。
class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({super.key});

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  final _p = ReaderPrefs.instance;
  final _store = LibraryStore.instance;
  final _scroll = ScrollController();
  final _bookmarks = <int>{};
  int _chapter = 0;
  double _progress = 0;
  bool _chrome = true;
  bool _fullscreen = false;
  String _find = '';

  @override
  void initState() {
    super.initState();
    final e = _store.entry(SampleNovel.id);
    final saved = int.tryParse(e?.chapterUuid?.replaceFirst('c', '') ?? '');
    if (saved != null && saved < SampleNovel.chapters.length) {
      _chapter = saved;
      _progress = e!.progress;
    }
    // 第一帧时还没有排版尺寸，页码只能算出 1/1；排完版后跳到上次位置并重算一次页码。
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
    if (_fullscreen) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFFF8F9F6),
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
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

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    SystemChrome.setEnabledSystemUIMode(_fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  (int, int) _pageCounter() {
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) return (1, 1);
    final view = _scroll.position.viewportDimension;
    final total = ((_scroll.position.maxScrollExtent + view) / view).ceil().clamp(1, 999);
    return ((_progress * (total - 1)).round() + 1, total);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _p,
        builder: (context, _) {
          final t = ReaderTheme.all[_p.theme];
          SystemChrome.setSystemUIOverlayStyle((t.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent, systemNavigationBarColor: t.bg));
          return PopScope(
            onPopInvokedWithResult: (_, _) => _save(),
            child: Scaffold(
              backgroundColor: t.bg,
              body: Stack(children: [
                Positioned.fill(child: _body(t)),
                _topBar(t),
                _bottomBar(t),
                // 亮度只模拟页面明暗，不修改系统亮度。
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      color: Colors.black.withValues(alpha: (1 - _p.brightness) * .7),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      );

  Widget _body(ReaderTheme t) {
    final ch = SampleNovel.chapters[_chapter];
    final style = Typo.body(_p, t);
    final margin = Typo.margins[_p.margin].$2;
    final top = MediaQuery.paddingOf(context).top;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _chrome = !_chrome),
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          _save();
          return false;
        },
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(margin, top + 72, margin, 200),
          children: [
            Text('${SampleNovel.chapterLabels[_chapter]}  ·  ${ch.title}', style: TextStyle(fontFamily: 'serif', fontSize: 13, color: t.muted)),
            const SizedBox(height: 18),
            for (final para in ch.paragraphs)
              Padding(
                padding: EdgeInsets.only(bottom: style.fontSize! * .8),
                child: Text.rich(_highlight('　　$para', t), style: style, textAlign: TextAlign.justify),
              ),
            const SizedBox(height: 24),
            if (_chapter < SampleNovel.chapters.length - 1)
              Center(
                child: OutlinedButton(
                  onPressed: () => _goChapter(_chapter + 1),
                  style: OutlinedButton.styleFrom(foregroundColor: t.ink, side: BorderSide(color: t.track), minimumSize: const Size(160, 46)),
                  child: Text('下一章 · ${SampleNovel.chapters[_chapter + 1].title}'),
                ),
              )
            else
              Center(child: Text('— 全文完 —', style: TextStyle(color: t.muted, fontSize: 13))),
          ],
        ),
      ),
    );
  }

  TextSpan _highlight(String text, ReaderTheme t) {
    if (_find.isEmpty || !text.contains(_find)) return TextSpan(text: text);
    final parts = text.split(_find);
    return TextSpan(children: [
      for (var i = 0; i < parts.length; i++) ...[
        TextSpan(text: parts[i]),
        if (i < parts.length - 1) TextSpan(text: _find, style: TextStyle(backgroundColor: t.progress.withValues(alpha: .35))),
      ],
    ]);
  }

  Widget _topBar(ReaderTheme t) => AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        top: _chrome ? 0 : -110,
        left: 0,
        right: 0,
        child: Container(
          color: t.bg.withValues(alpha: .96),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(children: [
                ToolButton(icon: 'left', background: t.card, color: t.ink, iconSize: 22, tooltip: '返回', onTap: () => Navigator.maybePop(context)),
                Expanded(
                  child: Text(SampleNovel.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'serif', fontSize: 14, fontWeight: FontWeight.w600, color: t.ink)),
                ),
                ToolButton(icon: 'expand', background: t.card, color: t.ink, iconSize: 20, tooltip: _fullscreen ? '退出全屏' : '全屏', onTap: _toggleFullscreen),
              ]),
            ),
          ),
        ),
      );

  Widget _bottomBar(ReaderTheme t) {
    final (page, pages) = _pageCounter();
    final marked = _bookmarks.contains(_chapter);
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      bottom: _chrome ? 0 : -240,
      left: 0,
      right: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(children: [
                Text('本章已读 ${(_progress * 100).round()}%', style: TextStyle(fontSize: 12, color: t.muted)),
                const Spacer(),
                Text('$page / $pages', style: TextStyle(fontSize: 12, color: t.muted, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ),
            Container(
              height: 44,
              decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(22)),
              child: Row(children: [
                ToolButton(icon: 'previous', color: _chapter > 0 ? t.ink : t.track, iconSize: 18, tooltip: '上一章', onTap: _chapter > 0 ? () => _goChapter(_chapter - 1) : null),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(activeTrackColor: t.progress, inactiveTrackColor: t.track, thumbColor: t.card),
                    child: Slider(
                      value: _progress,
                      onChanged: (v) {
                        if (_scroll.hasClients) _scroll.jumpTo(v * _scroll.position.maxScrollExtent);
                      },
                      onChangeEnd: (_) => _save(),
                    ),
                  ),
                ),
                ToolButton(
                  icon: 'next',
                  color: _chapter < SampleNovel.chapters.length - 1 ? t.ink : t.track,
                  iconSize: 18,
                  tooltip: '下一章',
                  onTap: _chapter < SampleNovel.chapters.length - 1 ? () => _goChapter(_chapter + 1) : null,
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Container(
              height: 66,
              decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(24)),
              child: Row(children: [
                _tool(t, 'list', '目录', () => _showToc(t)),
                _tool(t, marked ? 'bookmarkFilled' : 'bookmark', '书签', () {
                  setState(() => marked ? _bookmarks.remove(_chapter) : _bookmarks.add(_chapter));
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(marked ? '已取消本章书签' : '已为本章添加书签'), duration: const Duration(seconds: 1)));
                }),
                _tool(t, 'type', '外观', () => showReaderSettings(context)),
                _tool(t, 'search', '查找', () => _showFind(t), active: _find.isNotEmpty),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tool(ReaderTheme t, String icon, String label, VoidCallback onTap, {bool active = false}) => Expanded(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Material(
            color: active ? t.segment : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                AppIcon(icon, size: 22, color: t.ink, stroke: 1.5),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 12, color: t.ink)),
              ]),
            ),
          ),
        ),
      );

  void _showToc(ReaderTheme t) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: t.sheet,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < SampleNovel.chapters.length; i++)
              ListTile(
                leading: Text((i + 1).toString().padLeft(2, '0'), style: TextStyle(color: i == _chapter ? t.progress : t.muted)),
                title: Text(SampleNovel.chapters[i].title,
                    style: TextStyle(color: t.ink, fontWeight: i == _chapter ? FontWeight.w600 : FontWeight.w400)),
                trailing: _bookmarks.contains(i) ? AppIcon('bookmarkFilled', size: 16, color: t.progress) : null,
                onTap: () {
                  Navigator.pop(sheet);
                  _goChapter(i);
                },
              ),
          ]),
        ),
      );

  Future<void> _showFind(ReaderTheme t) async {
    final q = await showTextPrompt(
      context,
      title: '在本章查找',
      initial: _find,
      hint: '输入要查找的文字',
      confirmLabel: '查找',
      clearLabel: '清除',
      background: t.sheet,
      ink: t.ink,
    );
    if (q == null || !mounted) return;
    setState(() => _find = q.trim());
    if (_find.isEmpty) return;
    final hits = SampleNovel.chapters[_chapter].paragraphs.fold<int>(0, (n, p) => n + _find.allMatches(p).length);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(hits == 0 ? '本章没有找到“$_find”' : '本章找到 $hits 处“$_find”'), duration: const Duration(seconds: 2)));
  }
}
