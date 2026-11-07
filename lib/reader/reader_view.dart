import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../ui/zoomable_page.dart';
import 'reader_controller.dart';
import 'reader_models.dart';
import 'reader_navigation.dart';
import 'reading_mode.dart';

/// 阅读区本体，照搬 Mihon 的 `PagerViewer` / `WebtoonViewer` 两种形态（Apache-2.0）。
///
/// 单页是「一页一屏」的分页器，条漫是连续滚动；两者共用同一份条目列表
/// （上一话的页 → 过渡页 → 当前话的页 → 过渡页 → 下一话的页），所以跨话是连续的，
/// 不存在「读完一话弹一张卡片再点一下」的断点。
///
/// 反向阅读不把条目反过来排，而是交给 `PageView.reverse`：页码、进度和跳转
/// 都还是正序，只有手势和视觉方向反转，省掉一整类下标换算错误。
class ReaderView extends StatefulWidget {
  const ReaderView({
    super.key,
    required this.controller,
    required this.mode,
    required this.navigation,
    required this.pageBuilder,
    required this.transitionBuilder,
    this.onMenu,
  });

  final ReaderController controller;
  final ReadingMode mode;
  final ReaderNavigation navigation;

  /// 一页的内容（图片）。缩放和点按由本组件包在外面。
  final Widget Function(BuildContext context, ReaderPage page) pageBuilder;

  /// 过渡页的内容（跨话卡片）。
  final Widget Function(BuildContext context, ChapterTransition transition) transitionBuilder;

  /// 点按落在「切换控件」分区时回调。
  final VoidCallback? onMenu;

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  /// 分页器与滚动控制器。
  ///
  /// 换阅读方式时**整个换掉**，用目标页作为初始位置——而不是先建在 0 再 `_sync`
  /// 跳过去。后者会在第一帧画出第 1 页、下一帧才跳到当前页，看上去就是
  /// 「切模式卡了一下」。
  /// 这两个控制器在 [didChangeDependencies] 里按「当前读到哪一页」创建。
  ///
  /// 换阅读方式时 [AnimatedSwitcher] 会换 key，所以这个 State 是**全新**的，
  /// `didUpdateWidget` 根本不会跑——控制器必须在第一次 build 之前就带着
  /// 正确的初始位置，否则第一帧会先画出第 1 页、下一帧再跳过去，看上去就是卡一下。
  late PageController _pager;
  late ScrollController _scroll;
  bool _controllersReady = false;

  /// 条目 → key，条漫里用来把目标页滚进视野、以及判断中线落在哪一页。
  final _keys = <Object, GlobalKey>{};

  /// 当前停着的条目。用对象身份而不是下标，条目列表变长时下标会挪。
  Object? _anchor;

  List<Object> get _items => widget.controller.chapters?.items ?? const [];

  /// 当前该停在哪一页：条目下标 + 条漫模式下的估算像素位置。
  ///
  /// 条漫的每页高度要等图片量出来才知道，所以用「屏宽 × 1.4」的常见比例估算，
  /// 建好之后 `_sync` 会在遮罩底下做一次精确校正（见 [_ReaderViewState._sync]）。
  ({int index, double offset}) _restingSpot() {
    final items = _items;
    final pages = widget.controller.current?.pages;
    if (items.isEmpty || pages == null || pages.isEmpty) return (index: 0, offset: 0);
    final target = pages[widget.controller.pageIndex.clamp(0, pages.length - 1)];
    final index = items.indexOf(target);
    if (index < 0) return (index: 0, offset: 0);
    if (!widget.mode.stacked) return (index: index, offset: 0);
    final w = MediaQuery.sizeOf(context).width;
    final h = w * 1.4 + (widget.mode.gap ? 8 : 0);
    return (index: index, offset: index * h);
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    widget.controller.seek.addListener(_onSeek);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync(initial: true));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controllersReady) return;
    _controllersReady = true;
    // 这里才拿得到 MediaQuery（条漫要按屏宽估算偏移），所以控制器放在这建。
    final spot = _restingSpot();
    _pager = PageController(initialPage: spot.index);
    _scroll = ScrollController(initialScrollOffset: spot.offset);
  }

  /// 用目标位置重建两个控制器。旧的延后一帧再释放，避免它还在本帧被读取。
  void _rebuildControllers() {
    final spot = _restingSpot();
    final oldPager = _pager;
    final oldScroll = _scroll;
    _pager = PageController(initialPage: spot.index);
    _scroll = ScrollController(initialScrollOffset: spot.offset);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldPager.dispose();
      oldScroll.dispose();
    });
  }

  @override
  void didUpdateWidget(ReaderView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      old.controller.seek.removeListener(_onSeek);
      widget.controller.addListener(_onController);
      widget.controller.seek.addListener(_onSeek);
      _anchor = null;
    }
    if (old.mode != widget.mode) {
      // 换了阅读方式：轴、方向、滚动形态都变了，按当前页重建控制器。
      _anchor = null;
      _rebuildControllers();
      // 条漫的估算位置可能在图片量出来之后有偏差，下一帧精确对齐一次。
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync(initial: true));
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    widget.controller.seek.removeListener(_onSeek);
    if (_controllersReady) {
      _pager.dispose();
      _scroll.dispose();
    }
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  /// 外部请求跳页（底部滑条、目录跳转）。
  void _onSeek() {
    final target = widget.controller.seek.value;
    if (target == null) return;
    widget.controller.seek.value = null;
    if (!mounted) return;
    final items = _items;
    if (items.isEmpty) return;
    final pages = widget.controller.current?.pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[target.clamp(0, pages.length - 1)];
    final at = items.indexOf(page);
    if (at < 0) return;
    // 换章跳转时窗口可能还没跟上，直接把锚点和页码定到目标，
    // 再交给 _sync 对齐——它会在下一帧按锚点重新落位。
    _anchor = page;
    widget.controller.setPage(target);
    if (widget.mode.stacked) {
      _scrollTo(at);
    } else if (_pager.hasClients) {
      _pager.jumpToPage(at);
    }
  }

  /// 相邻话载入后，条目列表会在当前项前面多出一些页，当前项的下标随之变化。
  /// `PageView` 不会自己跟过去，所以列表一换就把位置对齐回来。
  void _sync({bool initial = false}) {
    if (!mounted) return;
    final items = _items;
    if (items.isEmpty) return;

    // 目标条目：当前话的当前页。
    final pages = widget.controller.current?.pages;
    if (pages == null || pages.isEmpty) return;
    final target = pages[widget.controller.pageIndex.clamp(0, pages.length - 1)];

    if (initial) {
      _anchor = target;
      _jump(items.indexOf(target));
      return;
    }

    if (widget.mode.stacked) {
      // 条漫不强行对齐：用户自己在滚。只有首次进入或换模式才定位。
      if (_anchor == null) {
        _anchor = target;
        _jump(items.indexOf(target));
      }
      return;
    }

    if (!_pager.hasClients || !_pager.position.hasContentDimensions) return;
    final at = (_pager.page ?? 0).round().clamp(0, items.length - 1);

    final anchor = _anchor;
    if (anchor == null) {
      _adopt(items[at]);
      return;
    }
    final want = items.indexOf(anchor);
    if (want < 0) {
      // 停着的过渡页已经被实际页替换（下一话载入完成），就地换成同位置的条目。
      _jump(at);
      _adopt(items[at]);
      return;
    }
    if (want != at) _jump(want);
  }

  void _jump(int index) {
    if (index < 0) return;
    if (widget.mode.stacked) {
      _scrollTo(index);
      return;
    }
    if (!_pager.hasClients) return;
    _pager.jumpToPage(index);
  }

  void _scrollTo(int index) {
    final items = _items;
    if (index < 0 || index >= items.length) return;
    final key = _keys[items[index]];
    void reveal() {
      final ctx = key?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: Duration.zero);
    }

    reveal();
    WidgetsBinding.instance.addPostFrameCallback((_) => reveal());
  }

  /// 把一个条目设为当前项。它是别的话的页时，顺手把三话窗口平移过去。
  void _adopt(Object? item) {
    if (item == null) return;
    _anchor = item;
    if (item is! ReaderPage) return;
    widget.controller.setPage(item.index);
    if (!identical(item.chapter, widget.controller.current)) {
      widget.controller.promote(item.chapter, page: item.index);
    }
  }

  void _onPage(int index) {
    final items = _items;
    if (index < 0 || index >= items.length) return;
    _adopt(items[index]);
  }

  void _tap(Offset global) {
    final size = MediaQuery.sizeOf(context);
    final p = Offset(global.dx / size.width, global.dy / size.height);
    switch (widget.navigation.actionAt(p)) {
      case ReaderAction.menu:
        widget.onMenu?.call();
      case ReaderAction.forward:
        _move(1);
      case ReaderAction.backward:
        _move(-1);
    }
  }

  void _move(int dir) {
    final items = _items;
    if (items.isEmpty) return;
    if (widget.mode.stacked) {
      if (!_scroll.hasClients) return;
      final h = MediaQuery.sizeOf(context).height;
      final target = (_scroll.position.pixels + dir * h * .78).clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
      return;
    }
    if (!_pager.hasClients) return;
    final next = ((_pager.page ?? 0).round() + dir).clamp(0, items.length - 1);
    _pager.animateToPage(next, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
  }

  /// 条漫：视口中线落在哪一页，就算读到哪一页。
  bool _onScroll(ScrollNotification n) {
    if (n is! ScrollUpdateNotification) return false;
    final items = _items;
    if (items.isEmpty) return false;
    final mid = MediaQuery.sizeOf(context).height / 2;
    final anchorAt = _anchor == null ? 0 : math.max(0, items.indexOf(_anchor!));
    final lo = math.max(0, anchorAt - 6);
    final hi = math.min(items.length - 1, anchorAt + 6);
    Object? found;
    for (var i = lo; i <= hi; i++) {
      final box = _keys[items[i]]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= mid) found = items[i];
    }
    if (found != null && !identical(found, _anchor)) _adopt(found);
    return false;
  }

  Widget _wrapTap(Widget child, {required bool zoom}) {
    if (zoom && !widget.mode.stacked) {
      return ZoomablePage(onTapUp: (d) => _tap(d.globalPosition), child: child);
    }
    return GestureDetector(behavior: HitTestBehavior.opaque, onTapUp: (d) => _tap(d.globalPosition), child: child);
  }

  @override
  Widget build(BuildContext context) {
    // 条目列表里过渡页的对象每次都会重建（const 构造不算），
    // 用「类型 + 目标话 uuid」当 key，避免条漫里整屏重建。
    Widget itemWidget(Object item) => item is ReaderPage
        ? widget.pageBuilder(context, item)
        : widget.transitionBuilder(context, item as ChapterTransition);

    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();

    if (widget.mode.stacked) {
      return NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView.builder(
          controller: _scroll,
          // 从下向上阅读：列表整体反向，条目 0 落在底部，往上是继续读。
          reverse: widget.mode.reversed,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          scrollCacheExtent: const ScrollCacheExtent.pixels(2400),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            return Padding(
              key: _keyOf(item),
              padding: EdgeInsets.only(bottom: widget.mode.gap ? 8 : 0),
              child: _wrapTap(itemWidget(item), zoom: false),
            );
          },
        ),
      );
    }

    return PageView.builder(
      controller: _pager,
      scrollDirection: widget.mode.isVertical ? Axis.vertical : Axis.horizontal,
      // 反向阅读只反转视觉和手势方向，条目顺序仍然是阅读顺序。
      reverse: widget.mode.reversed,
      physics: const BouncingScrollPhysics(),
      itemCount: items.length,
      onPageChanged: _onPage,
      itemBuilder: (context, i) {
        final item = items[i];
        return _wrapTap(itemWidget(item), zoom: item is ReaderPage);
      },
    );
  }

  GlobalKey _keyOf(Object item) => _keys.putIfAbsent(
        item is ReaderPage ? '${item.chapter.uuid}#${item.index}' : 'T${(item as ChapterTransition).from.uuid}>${item.to?.uuid}',
        GlobalKey.new,
      );
}
