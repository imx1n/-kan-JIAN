import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'chapter_pager.dart';
import 'navigation.dart';
import 'zoomable_page.dart';

class MangaReaderPage extends StatefulWidget {
  const MangaReaderPage({
    super.key,
    required this.comic,
    required this.group,
    required this.chapterUuid,
    this.initialPage = 0,
  });

  final ComicBrief comic;
  final String group;
  final String chapterUuid;
  final int initialPage;

  @override
  State<MangaReaderPage> createState() => _MangaReaderPageState();
}

class _MangaReaderPageState extends State<MangaReaderPage> {
  final _prefs = ReaderPrefs.instance;
  final _scroll = ScrollController();
  PageController? _pager;
  ChapterContent? _content;
  String? _error;
  bool _loading = true;
  bool _chrome = true;
  bool _advancing = false;
  int _page = 0;
  int _retry = 0;
  List<GlobalKey> _keys = const [];

  bool get _saver => _prefs.mangaSaver;
  List<String> get _images => [for (final u in _content?.images ?? const <String>[]) imageUrlFor(u, saver: _saver)];
  bool get _scrollMode => _prefs.mangaScroll;
  bool get _rtl => _prefs.mangaRtl;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefs);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Palette.rBg,
    ));
    _load(widget.chapterUuid, page: widget.initialPage);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Palette.bar,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    _pager?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  Future<void> _load(String uuid, {int page = 0}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await MangaApi.instance.chapter(widget.comic.pathWord, uuid);
      if (!mounted) return;
      final start = c.images.isEmpty ? 0 : page.clamp(0, c.images.length - 1);
      _pager?.dispose();
      setState(() {
        _content = c;
        _loading = false;
        _advancing = false;
        _page = start;
        _pager = PageController(initialPage: start);
        _keys = List.generate(c.images.length, (_) => GlobalKey());
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      if (_scrollMode && start > 0) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpScroll(start));
      _save();
      _precache(start);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _advancing = false;
          _error = e.toString();
        });
      }
    }
  }

  void _save() {
    final c = _content;
    if (c == null || c.images.isEmpty || c.isLock) return;
    final store = LibraryStore.instance;
    store.recordPosition(
      id: widget.comic.pathWord,
      create: () => ShelfEntry(
        id: widget.comic.pathWord,
        kind: ShelfKind.manga,
        name: widget.comic.name,
        cover: widget.comic.cover,
        author: widget.comic.authorText,
      ),
      chapterUuid: c.chapter.uuid,
      chapterName: c.chapter.name,
      chapterIndex: c.chapter.index,
      group: c.chapter.groupPathWord.isEmpty ? widget.group : c.chapter.groupPathWord,
      page: _page,
      pageCount: c.images.length,
      progress: (_page + 1) / c.images.length,
    );
    if (_page >= c.images.length - 1) store.markRead(widget.comic.pathWord, c.chapter.uuid);
  }

  void _precache(int from) {
    final images = _images;
    for (var i = from + 1; i <= from + 3 && i < images.length; i++) {
      precacheImage(CachedNetworkImageProvider(images[i], headers: AppConfig.imageHeaders), context).ignore();
    }
  }

  void _onPage(int i) {
    final page = math.min(i, math.max(0, _images.length - 1));
    if (page == _page) return;
    setState(() => _page = page);
    _save();
    _precache(page);
  }

  void _setChrome(bool show) {
    setState(() => _chrome = show);
    SystemChrome.setEnabledSystemUIMode(show ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky);
  }

  /// 单页模式的点击分区：两侧翻页，中间呼出/收起工具栏。
  void _onTapUp(TapUpDetails d) {
    final w = MediaQuery.sizeOf(context).width;
    final x = d.globalPosition.dx / w;
    if (_scrollMode || (x > .3 && x < .7)) return _setChrome(!_chrome);
    final forward = _rtl ? x <= .3 : x >= .7;
    _goTo(_page + (forward ? 1 : -1), animate: true);
  }

  void _goTo(int page, {bool animate = false}) {
    final max = _images.length; // 允许翻到末尾的「本话完」卡片
    page = page.clamp(0, _scrollMode ? max - 1 : max);
    if (_scrollMode) {
      _jumpScroll(page);
    } else if (_pager?.hasClients ?? false) {
      animate
          ? _pager!.animateToPage(page, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic)
          : _pager!.jumpToPage(page);
    }
  }

  void _jumpScroll(int page) {
    final ctx = _keys.elementAtOrNull(page)?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx);
      return;
    }
    if (!_scroll.hasClients) return;
    // 目标未构建：先按估算高度跳过去，再精确对齐。
    final est = MediaQuery.sizeOf(context).width * 1.45;
    _scroll.jumpTo(math.min(page * est, _scroll.position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys.elementAtOrNull(page)?.currentContext;
      if (c != null) Scrollable.ensureVisible(c);
    });
  }

  /// 条漫模式：取视口中线所在的那一页作为当前页；到底后继续下拉自动接下一话。
  bool _onScroll(ScrollNotification n) {
    // 只有手指拖着越过底部 72 像素才算“继续下滑”；惯性甩到底的回弹不算，否则快速滑动会连跳好几话。
    final pulledPastEnd = n.metrics.pixels > n.metrics.maxScrollExtent + 72;
    final byFinger = (n is ScrollUpdateNotification && n.dragDetails != null) || (n is OverscrollNotification && n.dragDetails != null);
    if (byFinger && ((n is OverscrollNotification && n.overscroll > 0) || pulledPastEnd)) {
      _autoNext();
      return false;
    }
    if (n is! ScrollUpdateNotification || _keys.isEmpty) return false;
    final mid = MediaQuery.sizeOf(context).height / 2;
    var found = _page;
    final lo = math.max(0, _page - 6), hi = math.min(_keys.length - 1, _page + 6);
    for (var i = lo; i <= hi; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= mid) found = i;
    }
    _onPage(found);
    return false;
  }

  void _autoNext() {
    final next = _content?.chapter.next;
    if (_advancing || _loading || next == null) return;
    _advancing = true;
    _load(next);
  }

  void _toggleMode() {
    final page = _page;
    _prefs.mangaScroll = !_prefs.mangaScroll;
    _pager?.dispose();
    setState(() => _pager = PageController(initialPage: page));
    if (_prefs.mangaScroll) WidgetsBinding.instance.addPostFrameCallback((_) => _jumpScroll(page));
  }

  void _openChapter(String? uuid) {
    if (uuid != null) _load(uuid);
  }

  @override
  Widget build(BuildContext context) {
    final c = _content;
    return Scaffold(
      backgroundColor: Palette.rBg,
      body: Stack(children: [
        Positioned.fill(child: _body(c)),
        // 亮度只模拟页面明暗，不修改系统亮度。
        Positioned.fill(
          child: IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: (1 - _prefs.mangaBrightness) * .75))),
        ),
        _topBar(c),
        _bottomBar(c),
        if (!_chrome && c != null && _images.isNotEmpty) _miniChip(c),
      ]),
    );
  }

  Widget _body(ChapterContent? c) {
    if (_loading) return const LoadingView(color: Palette.rInk2);
    if (_error != null) return ErrorView(message: _error!, dark: true, onRetry: () => _load(c?.chapter.uuid ?? widget.chapterUuid, page: _page));
    if (c == null) return const SizedBox();
    if (c.isLock || c.images.isEmpty) return _locked(c);
    final images = _images;
    if (_scrollMode) {
      return GestureDetector(
        onTap: () => _setChrome(!_chrome),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: ListView.builder(
            controller: _scroll,
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            scrollCacheExtent: const ScrollCacheExtent.pixels(2400),
            itemCount: images.length + 1,
            itemBuilder: (context, i) => i == images.length
                ? _EndCard(chapter: c.chapter, onNext: () => _openChapter(c.chapter.next), scrollMode: true)
                : KeyedSubtree(key: _keys[i], child: _image(images[i], fitWidth: true)),
          ),
        ),
      );
    }
    return PageView.builder(
      controller: _pager,
      reverse: _rtl,
      itemCount: images.length + 1,
      onPageChanged: _onPage,
      itemBuilder: (context, i) => i == images.length
          ? GestureDetector(onTap: () => _setChrome(!_chrome), child: _EndCard(chapter: c.chapter, onNext: () => _openChapter(c.chapter.next)))
          : ZoomablePage(onTapUp: _onTapUp, child: _image(images[i])),
    );
  }

  Widget _locked(ChapterContent c) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Palette.rBar, shape: BoxShape.circle),
              child: const AppIcon('lock', size: 26, color: Palette.rInk),
            ),
            const SizedBox(height: 18),
            Text(c.isLock ? '这一话需要会员' : '这一话暂时没有图片',
                style: const TextStyle(fontFamily: kSerif, fontSize: 19, fontWeight: FontWeight.w600, color: Palette.rInk)),
            const SizedBox(height: 8),
            Text(
              c.isLock ? '源站把它标记为付费内容。栞间不提供绕过方式，也不会请求这一话的图片。' : '源站没有返回这一话的图片，可以换一话试试。',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, height: 1.7, color: Palette.rInk2),
            ),
            const SizedBox(height: 24),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (c.chapter.prev != null) ...[
                FilledButton(
                  onPressed: () => _openChapter(c.chapter.prev),
                  style: FilledButton.styleFrom(backgroundColor: Palette.rBar, foregroundColor: Palette.rInk, minimumSize: const Size(0, 44)),
                  child: const Text('上一话'),
                ),
                const SizedBox(width: 10),
              ],
              FilledButton(
                onPressed: () => _showCatalog(c),
                style: FilledButton.styleFrom(backgroundColor: Palette.rThumb, foregroundColor: Palette.rBg, minimumSize: const Size(0, 44)),
                child: const Text('回到目录'),
              ),
            ]),
          ]),
        ),
      );

  Widget _image(String url, {bool fitWidth = false}) {
    final w = MediaQuery.sizeOf(context).width;
    return CachedNetworkImage(
      key: ValueKey('$url#$_retry'),
      imageUrl: url,
      httpHeaders: AppConfig.imageHeaders,
      fit: fitWidth ? BoxFit.fitWidth : BoxFit.contain,
      width: fitWidth ? w : null,
      fadeInDuration: const Duration(milliseconds: 120),
      progressIndicatorBuilder: (context, _, p) => SizedBox(
        height: fitWidth ? w * 1.4 : null,
        child: Center(
          child: SizedBox.square(dimension: 26, child: CircularProgressIndicator(value: p.progress, strokeWidth: 2, color: Palette.rInk2)),
        ),
      ),
      errorWidget: (context, _, _) => SizedBox(
        height: fitWidth ? w * 1.4 : null,
        child: Center(
          child: TextButton.icon(
            onPressed: () {
              CachedNetworkImage.evictFromCache(url);
              setState(() => _retry++);
            },
            icon: const AppIcon('refresh', size: 16, color: Palette.rInk),
            label: const Text('图片加载失败，点按重试', style: TextStyle(color: Palette.rInk)),
          ),
        ),
      ),
    );
  }

  Widget _topBar(ChapterContent? c) => AnimatedPositioned(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        top: _chrome ? 0 : -120,
        left: 0,
        right: 0,
        child: Container(
          color: Palette.rBg.withValues(alpha: .96),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Row(children: [
                const SizedBox(width: 4),
                ToolButton(icon: 'back', color: Palette.rInk, iconSize: 22, size: 48, tooltip: '返回', onTap: () => Navigator.pop(context)),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(widget.comic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Palette.rInk)),
                    const SizedBox(height: 2),
                    Text(c?.chapter.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.rInk2)),
                  ]),
                ),
                ToolButton(icon: 'info', color: Palette.rInk, iconSize: 22, size: 48, tooltip: '作品详情', onTap: () => openDetail(context, widget.comic)),
                const SizedBox(width: 4),
              ]),
            ),
          ),
        ),
      );

  Widget _bottomBar(ChapterContent? c) {
    final n = _images.length;
    final hasPages = c != null && n > 0 && !c.isLock;
    final prev = c?.chapter.prev, next = c?.chapter.next;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      bottom: _chrome ? 0 : -240,
      left: 0,
      right: 0,
      child: Container(
        color: Palette.rBg.withValues(alpha: .97),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(children: [
                  Text(hasPages ? '第 ${_page + 1} / $n 页' : '—', style: const TextStyle(fontSize: 12, color: Palette.rInk2)),
                  const Spacer(),
                  if (!_scrollMode)
                    Material(
                      color: Palette.rBar,
                      shape: const StadiumBorder(),
                      child: InkWell(
                        customBorder: const StadiumBorder(),
                        onTap: () => _prefs.mangaRtl = !_rtl,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const AppIcon('direction', size: 14, color: Palette.rInk),
                            const SizedBox(width: 5),
                            Text(_rtl ? '从右向左' : '从左向右', style: const TextStyle(fontSize: 12, color: Palette.rInk)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 6),
              Container(
                height: 48,
                decoration: BoxDecoration(color: Palette.rBar, borderRadius: BorderRadius.circular(24)),
                child: Row(children: [
                  ToolButton(icon: 'previous', size: 44, iconSize: 18, tooltip: '上一话', color: prev == null ? Palette.rLine : Palette.rInk, onTap: prev == null ? null : () => _openChapter(prev)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: Palette.rThumb,
                        inactiveTrackColor: Palette.rLine,
                        thumbColor: Palette.rThumb,
                        trackHeight: 3,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      ),
                      child: Directionality(
                        // 从右向左阅读时，进度条也从右往左走。
                        textDirection: _rtl && !_scrollMode ? TextDirection.rtl : TextDirection.ltr,
                        child: Slider(
                          value: hasPages ? _page.toDouble() : 0,
                          max: hasPages ? math.max(1, n - 1).toDouble() : 1,
                          divisions: hasPages && n > 1 ? n - 1 : null,
                          onChanged: hasPages && n > 1 ? (v) => setState(() => _page = v.round()) : null,
                          onChangeEnd: hasPages ? (v) => _goTo(v.round()) : null,
                        ),
                      ),
                    ),
                  ),
                  ToolButton(icon: 'next', size: 44, iconSize: 18, tooltip: '下一话', color: next == null ? Palette.rLine : Palette.rInk, onTap: next == null ? null : () => _openChapter(next)),
                ]),
              ),
              SizedBox(
                height: 60,
                child: Row(children: [
                  _tool('list', '目录', c == null ? null : () => _showCatalog(c)),
                  _tool(_scrollMode ? 'scroll' : 'pages', _scrollMode ? '条漫' : '单页', _toggleMode),
                  _tool('image', _saver ? '画质 省流' : '画质 标准', () {
                    _prefs.mangaSaver = !_saver;
                    _precache(_page);
                  }),
                  _tool('sun', '亮度', _showBrightness),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _tool(String icon, String label, VoidCallback? onTap) {
    final color = onTap == null ? Palette.rLine : Palette.rInk;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AppIcon(icon, size: 21, color: color, stroke: 1.5),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 12, color: onTap == null ? Palette.rLine : Palette.rInk2)),
        ]),
      ),
    );
  }

  /// 工具栏收起时，底部只留一个页码。
  Widget _miniChip(ChapterContent c) => Positioned(
        left: 0,
        right: 0,
        bottom: 24 + MediaQuery.paddingOf(context).bottom,
        child: IgnorePointer(
          child: Center(
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(color: Palette.rBg.withValues(alpha: .8), borderRadius: BorderRadius.circular(13)),
              child: Center(widthFactor: 1, child: Text('${c.chapter.name} · ${_page + 1} / ${_images.length}', style: const TextStyle(fontSize: 12, color: Palette.rInk2))),
            ),
          ),
        ),
      );

  void _showBrightness() => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Palette.rBar,
        builder: (sheet) => ListenableBuilder(
          listenable: _prefs,
          builder: (context, _) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('亮度', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Palette.rInk)),
                  const Spacer(),
                  Text('${(_prefs.mangaBrightness * 100).round()}%', style: const TextStyle(fontSize: 13, color: Palette.rInk2)),
                ]),
                const SizedBox(height: 4),
                const Text('只调暗页面，不改变系统亮度', style: TextStyle(fontSize: 12, color: Palette.rMute)),
                Row(children: [
                  const AppIcon('sun', size: 14, color: Palette.rInk2),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(activeTrackColor: Palette.rThumb, inactiveTrackColor: Palette.rLine, thumbColor: Palette.rThumb),
                      child: Slider(value: _prefs.mangaBrightness, min: .3, max: 1, onChanged: (v) => _prefs.mangaBrightness = v),
                    ),
                  ),
                  const AppIcon('sun', size: 20, color: Palette.rInk2),
                ]),
              ]),
            ),
          ),
        ),
      );

  void _showCatalog(ChapterContent c) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Palette.rBar,
        builder: (sheet) => _CatalogSheet(
          comic: widget.comic,
          group: c.chapter.groupPathWord.isEmpty ? widget.group : c.chapter.groupPathWord,
          current: c.chapter,
          page: _page,
          pageCount: _images.length,
          onPick: (uuid) {
            Navigator.pop(sheet);
            _load(uuid);
          },
        ),
      );
}

class _EndCard extends StatelessWidget {
  const _EndCard({required this.chapter, required this.onNext, this.scrollMode = false});

  final Chapter chapter;
  final VoidCallback onNext;
  final bool scrollMode;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(28, scrollMode ? 40 : 0, 28, scrollMode ? 120 : 160),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${chapter.name} 完', textAlign: TextAlign.center, style: const TextStyle(fontFamily: kSerif, fontSize: 19, fontWeight: FontWeight.w600, letterSpacing: 2, color: Palette.rInk)),
            const SizedBox(height: 6),
            Text('${chapter.size > 0 ? '${chapter.size} 页 · ' : ''}已记为读完', style: const TextStyle(fontSize: 12, color: Palette.rMute)),
            const SizedBox(height: 24),
            if (chapter.next != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Palette.rBar, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('下一话', style: TextStyle(fontSize: 12, color: Palette.rInk2)),
                      SizedBox(height: 3),
                      Text('点按或继续滑动', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.rInk)),
                    ]),
                  ),
                  FilledButton(
                    onPressed: onNext,
                    style: FilledButton.styleFrom(backgroundColor: Palette.rThumb, foregroundColor: Palette.rBg, minimumSize: const Size(0, 44)),
                    child: const Text('接着读'),
                  ),
                ]),
              ),
              if (scrollMode) ...[
                const SizedBox(height: 18),
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon('down', size: 16, color: Palette.rMute),
                  SizedBox(width: 6),
                  Text('继续下滑，自动接上下一话', style: TextStyle(fontSize: 12, color: Palette.rMute)),
                ]),
              ],
            ] else
              const Text('已经是最新一话', style: TextStyle(fontSize: 13, color: Palette.rInk2)),
          ]),
        ),
      );
}

/// 阅读中的目录：分组、分段与详情页一致，自动打开当前话所在的分段。
class _CatalogSheet extends StatefulWidget {
  const _CatalogSheet({required this.comic, required this.group, required this.current, required this.page, required this.pageCount, required this.onPick});

  final ComicBrief comic;
  final String group;
  final Chapter current;
  final int page;
  final int pageCount;
  final ValueChanged<String> onPick;

  @override
  State<_CatalogSheet> createState() => _CatalogSheetState();
}

class _CatalogSheetState extends State<_CatalogSheet> {
  late final _browser = ChapterBrowser(widget.comic.pathWord)..init(preferGroup: widget.group, locateIndex: widget.current.index);
  final _currentKey = GlobalKey();
  final _firstKey = GlobalKey();
  bool _located = false;

  @override
  void initState() {
    super.initState();
    _browser.addListener(_onBrowser);
  }

  void _onBrowser() {
    if (!_located && !_browser.loading && _browser.items != null) {
      _located = true;
      final index = _browser.items!.indexWhere((c) => c.uuid == widget.current.uuid);
      if (index >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) => revealChapterRow(firstKey: _firstKey, targetKey: _currentKey, index: index, rowExtent: 48));
      }
    }
  }

  @override
  void dispose() {
    _browser.removeListener(_onBrowser);
    _browser.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: ListenableBuilder(
          listenable: _browser,
          builder: (context, _) {
            final items = _browser.items ?? const <Chapter>[];
            final current = ShelfEntry(
              id: widget.comic.pathWord,
              kind: ShelfKind.manga,
              name: widget.comic.name,
              cover: widget.comic.cover,
              author: '',
              page: widget.page,
              pageCount: widget.pageCount,
            );
            return Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                child: Row(children: [
                  const Text('目录', style: TextStyle(fontFamily: kSerif, fontSize: 19, fontWeight: FontWeight.w600, color: Palette.rInk)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(widget.comic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.rInk2))),
                  ToolButton(icon: 'sort', tooltip: _browser.descending ? '改为正序' : '改为倒序', size: 48, iconSize: 20, color: _browser.descending ? Palette.rThumb : Palette.rInk2, onTap: _browser.toggleOrder),
                  ToolButton(icon: 'close', tooltip: '关闭', size: 48, iconSize: 20, color: Palette.rInk2, onTap: () => Navigator.pop(context)),
                ]),
              ),
              if (_browser.groups.length > 1)
                UnderlineTabs(
                  dark: true,
                  labels: [for (final g in _browser.groups) (g.name, g.count)],
                  selected: _browser.groups.indexWhere((g) => g.pathWord == _browser.group).clamp(0, _browser.groups.length - 1),
                  onSelect: (i) => _browser.selectGroup(_browser.groups[i].pathWord),
                ),
              RangeChips(browser: _browser, dark: true),
              Expanded(
                child: ListView(children: [
                  if (!_browser.loading)
                    for (final (i, ch) in items.indexed)
                      KeyedSubtree(
                        key: i == 0 ? _firstKey : null,
                        child: ChapterTile(
                          key: ch.uuid == widget.current.uuid ? _currentKey : null,
                          dark: true,
                          chapter: ch,
                          number: ch.index + 1,
                          read: LibraryStore.instance.isRead(widget.comic.pathWord, ch.uuid),
                          current: ch.uuid == widget.current.uuid ? current : null,
                          onTap: () => widget.onPick(ch.uuid),
                        ),
                      ),
                  ChapterListStatus(browser: _browser, dark: true),
                ]),
              ),
            ]);
          },
        ),
      );
}
