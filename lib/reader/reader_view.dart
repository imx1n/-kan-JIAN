import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show RenderObject, RenderSliverMultiBoxAdaptor, ScrollCacheExtent, SliverMultiBoxAdaptorParentData;

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

  /// 恢复流程要落到的条目。存**对象**而不是下标：预加载完成后上一话的页会
  /// 插到列表前面，所有下标整体后移，缓存的下标会指到别的页去。
  Object? _restoreItem;

  /// 这次进入是否已经发起过恢复。只发一次，之后交给用户自己滚。
  bool _restoreDone = false;

  /// 条漫 `ListView` 的 key：[_itemAtViewportMiddle] 从这里摸到渲染层的 sliver。
  final _listKey = GlobalKey();

  List<Object> get _items => widget.controller.chapters?.items ?? const [];

  /// 当前该停在哪一页：条目下标。
  ///
  /// 条漫**只认下标，不认像素**。每页高度要等图片量出来才知道，用估算值
  /// 去算 `initialScrollOffset` 只会在首帧被 `maxScrollExtent` 夹回前几页
  /// ——列表是懒构建的，首帧只量得出「一屏 + 缓存区」那么多内容。
  /// 所以控制器一律从 0 起，之后由 [_beginRestore] 逐帧推到位。
  ({int index, double offset}) _restingSpot() {
    final items = _items;
    final pages = widget.controller.current?.pages;
    if (items.isEmpty || pages == null || pages.isEmpty) return (index: 0, offset: 0);
    final target = pages[widget.controller.pageIndex.clamp(0, pages.length - 1)];
    final index = items.indexOf(target);
    return (index: index < 0 ? 0 : index, offset: 0);
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
    // 这里才拿得到 MediaQuery，所以控制器放在这建。
    final spot = _restingSpot();
    _pager = PageController(initialPage: spot.index);
    // 条漫的初始偏移一律是 0，位置交给逐帧恢复（[_beginRestore]）。
    _scroll = ScrollController();
  }

  /// 用目标位置重建两个控制器。旧的延后一帧再释放，避免它还在本帧被读取。
  void _rebuildControllers() {
    final spot = _restingSpot();
    final oldPager = _pager;
    final oldScroll = _scroll;
    _pager = PageController(initialPage: spot.index);
    _scroll = ScrollController();
    _restoreItem = null;
    _restoreDone = false;
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
      if (widget.mode.stacked) {
        _beginRestore();
      } else {
        _jump(items.indexOf(target));
      }
      return;
    }

    if (widget.mode.stacked) {
      // 条漫不强行对齐：用户自己在滚。只有首次进入或换模式才定位。
      if (_restoreItem != null) return;
      if (_anchor == null) {
        _anchor = target;
        _beginRestore();
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

  /// 发起一次「回到上次读到的那一页」。
  ///
  /// 只在条漫模式下需要：分页器可以直接用 `initialPage` 落到任意页，
  /// 条漫只能靠滚动，而列表是懒构建的。
  void _beginRestore() {
    if (!mounted || !widget.mode.stacked) return;
    if (_restoreDone || _restoreItem != null) return;
    final pages = widget.controller.current?.pages;
    if (pages == null || pages.isEmpty) return;
    final target = pages[widget.controller.pageIndex.clamp(0, pages.length - 1)];
    final items = _items;
    final index = items.indexOf(target);
    if (index <= 0) {
      // 第 1 页（或目标还没进列表）不用找，什么都不做也不会错。
      _restoreDone = true;
      return;
    }
    _restoreItem = target;
    widget.controller.restoring = true;
    unawaited(_walkTo(target, restore: true));
  }

  /// 逐帧把 [item] 推进视口。
  ///
  /// 条漫是懒构建的：目标离得远时它根本没被建出来，`Scrollable.ensureVisible`
  /// 拿到 null 就静默什么都不做——这正是「每次进来都是第 1 页」的直接原因。
  /// 所以这里先按「一屏 90%」一帧一帧往下跳，列表随之把后面的条目建出来，
  /// `maxScrollExtent` 跟着增长，直到目标真的出现。
  ///
  /// 认**条目对象**而不是下标：预加载完成后上一话的页会插到列表前面，
  /// 所有下标整体后移，缓存的下标会指到别的页、甚至翻过好几话。
  Future<void> _walkTo(Object item, {required bool restore}) async {
    var tries = 0;
    while (mounted && tries < 60) {
      final index = _items.indexOf(item);
      if (index < 0) break;
      final ctx = _keys[item]?.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(ctx, duration: Duration.zero);
        // 图片量出来之后条目高度会变，位置会漂，再对齐一次。
        await WidgetsBinding.instance.endOfFrame;
        final again = _keys[item]?.currentContext;
        if (again != null && again.mounted) {
          await Scrollable.ensureVisible(again, duration: Duration.zero);
        }
        _finishRestore(item, restore: restore);
        return;
      }
      if (!_scroll.hasClients) {
        await WidgetsBinding.instance.endOfFrame;
        tries++;
        continue;
      }
      final pos = _scroll.position;
      final next = math.min(pos.maxScrollExtent, pos.pixels + pos.viewportDimension * .9);
      if (next > pos.pixels + 1) _scroll.jumpTo(next);
      // 已经到底还没建出来，就等下一帧让列表把新条目建完再试。
      await WidgetsBinding.instance.endOfFrame;
      tries++;
    }
    _finishRestore(null, restore: restore);
  }

  /// [item] 为 null 表示没能把目标推到视口里。
  ///
  /// 失败时**什么都不写**：宁可停在第 1 页，也不能把用户真实的位置覆盖掉。
  void _finishRestore(Object? item, {required bool restore}) {
    _restoreItem = null;
    _restoreDone = true;
    if (!restore) {
      if (item != null) _adopt(item);
      return;
    }
    widget.controller.restoring = false;
    if (!mounted || item == null) return;
    // 落定之后才算出「真正停在哪一页」，这时候写盘是安全的。
    _adopt(item);
  }

  void _scrollTo(int index) {
    final items = _items;
    if (index < 0 || index >= items.length) return;
    unawaited(_walkTo(items[index], restore: false));
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
  ///
  /// 不能按「锚点 ±N 条目」去找。锚点只有在 `_adopt` 时才会动，而 `_adopt`
  /// 又要靠这里找出来——一旦用户连续滚动超过那个窗口，窗口里的条目早就被懒构建
  /// 回收了，`currentContext` 全是 null，`found` 永远是 null，页码从此不再前进。
  /// 这就是「除了左右翻页，进度条永远是 1」的真正原因。
  ///
  /// 改为直接读列表的渲染层：`ListView` 的真实子节点就是当前可见（含缓存）的条目，
  /// 从中挑出中线落在其中的那一个。条目上限只有一屏几个，代价可以忽略。
  bool _onScroll(ScrollNotification n) {
    if (n is! ScrollUpdateNotification) return false;
    // 恢复过程中视口扫过的页不是用户读到的页，不能 adopt（否则会写错位置）。
    if (widget.controller.restoring) return false;
    final index = _itemAtViewportMiddle();
    if (index == null) return false;
    final items = _items;
    if (index < 0 || index >= items.length) return false;
    final item = items[index];
    if (!identical(item, _anchor)) _adopt(item);
    return false;
  }

  /// 从 `ListView` 的渲染树里取出真正承载条目的 sliver。
  RenderSliverMultiBoxAdaptor? _sliver() {
    final root = _listKey.currentContext?.findRenderObject();
    if (root == null) return null;
    RenderSliverMultiBoxAdaptor? found;
    void find(RenderObject o) {
      if (found != null) return;
      if (o is RenderSliverMultiBoxAdaptor) {
        found = o;
        return;
      }
      o.visitChildren(find);
    }

    find(root);
    return found;
  }

  /// 视口中线当前压在哪个条目上。
  int? _itemAtViewportMiddle() {
    final s = _sliver();
    if (s == null) return null;

    final mid = MediaQuery.sizeOf(context).height / 2;
    int? hit;
    int? nearest;
    var nearestGap = double.infinity;
    for (var child = s.firstChild; child != null; child = s.childAfter(child)) {
      final data = child.parentData;
      if (data is! SliverMultiBoxAdaptorParentData) continue;
      final index = data.index;
      if (index == null) continue;
      final top = child.localToGlobal(Offset.zero).dy;
      final bottom = top + child.size.height;
      // 中线正落在这个条目里：最准确。
      if (top <= mid && mid <= bottom) {
        hit = index;
        break;
      }
      // 中线落在两张图之间的缝里时，取中心离中线最近的那一张。
      final gap = (mid - (top + bottom) / 2).abs();
      if (gap < nearestGap) {
        nearestGap = gap;
        nearest = index;
      }
    }
    return hit ?? nearest;
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
          key: _listKey,
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
