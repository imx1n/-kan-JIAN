import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'icons.dart';
import 'novel_pages.dart';

/// 小说正文：左右分页（默认）或整章上下滚动。
///
/// 排版沿用设计稿：段间留白、不缩进、两端对齐。分页是按可用宽高用
/// [paginateNovel] 现算的，所以改字号、行距、转屏后都会重新分页，并按
/// 「已读字数」估算新的页码，不会跳回第一页。
class NovelBody extends StatefulWidget {
  const NovelBody({
    super.key,
    required this.contentId,
    required this.blocks,
    required this.style,
    required this.ink,
    required this.muted,
    required this.padding,
    required this.paged,
    this.initialProgress = 0,
    this.onProgress,
    this.onTapLeft,
    this.onTapCenter,
    this.onTapRight,
    this.header,
    this.endCard,
    this.imageBuilder,
  });

  /// 内容的身份（例如 `书号:章节 id`）。只有它变了才算换了一章，
  /// 否则父组件重建时传入的新列表会把分页结果冲掉。
  final String contentId;

  /// [String] 段落、[NovelImageBlock] 插图、[NovelEndBlock] 章末卡片的混合列表。
  final List<Object> blocks;
  final TextStyle style;
  final Color ink;
  final Color muted;

  /// 正文区域内边距：左右是留白，上下要避开顶栏和底栏。
  final EdgeInsets padding;

  /// true 为左右分页，false 为整章上下滚动。
  final bool paged;

  /// 上次读到这一章的百分比（0–1）。
  final double initialProgress;

  /// 页码变化时回调：当前页（从 1 开始）、总页数、百分比。
  final void Function(int page, int pages, double progress)? onProgress;

  /// 三个点按区。返回 true 表示外层已经处理（例如翻到上一章）。
  final bool Function()? onTapLeft;
  final VoidCallback? onTapCenter;
  final bool Function()? onTapRight;

  /// 章节标题，只出现在第一页顶部（滚动模式在顶部）。
  final Widget? header;

  /// 章末卡片（上一章 / 下一章 / 加入书架），放在 [NovelEndBlock] 里。
  final Widget? endCard;

  /// 插图渲染，宽度由正文决定。
  final Widget Function(String url, double width)? imageBuilder;

  @override
  State<NovelBody> createState() => NovelBodyState();
}

class NovelBodyState extends State<NovelBody> {
  PageController? _pager;
  final _scroll = ScrollController();
  List<NovelPage> _pages = const [];
  Size _size = Size.zero;
  int _index = 0;
  double _scrollProgress = 0;
  double _lastScale = 1;

  int get page => _pages.isEmpty ? 1 : _index + 1;
  int get pages => _pages.isEmpty ? 1 : _pages.length;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant NovelBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在「换了一章」或改排版时才重排；父组件每次 setState 都会给一个新列表，
    // 按列表身份比较会导致翻页时反复重算，页码永远回不到第一页之后。
    if (oldWidget.contentId != widget.contentId || oldWidget.style != widget.style || oldWidget.paged != widget.paged) {
      _index = 0;
      _rebuild();
    }
  }

  @override
  void dispose() {
    _pager?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    final v = max <= 0 ? 1.0 : (_scroll.offset / max).clamp(0.0, 1.0);
    if ((v - _scrollProgress).abs() > .005) {
      setState(() => _scrollProgress = v);
      widget.onProgress?.call(page, pages, v);
    }
  }

  /// 按当前尺寸与排版重新分页；旧页还在时按已读字数找回位置。
  void _rebuild() {
    if (!widget.paged) {
      _pages = const [];
      return;
    }
    final width = _size.width - widget.padding.horizontal;
    final height = _size.height - widget.padding.vertical;
    if (width <= 0 || height <= 0) {
      _pages = const [];
      return;
    }
    final old = _pages;
    final oldIndex = _index;
    _pages = paginateNovel(widget.blocks, style: widget.style, width: width, height: height);
    if (_pages.isEmpty) {
      _index = 0;
      return;
    }
    if (old.isEmpty) {
      final p = widget.initialProgress.clamp(0.0, 1.0);
      _index = ((_pages.length - 1) * p).round();
    } else {
      final before = old.take(oldIndex).expand((p) => p.blocks).whereType<NovelTextBlock>().fold<int>(0, (n, b) => n + b.text.length);
      final total = old.expand((p) => p.blocks).whereType<NovelTextBlock>().fold<int>(0, (n, b) => n + b.text.length);
      final ratio = total == 0 ? 0.0 : before / total;
      _index = ((_pages.length - 1) * ratio).round();
    }
    _index = _index.clamp(0, _pages.length - 1);
    _syncPager();
  }

  void _syncPager() {
    if (!widget.paged) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pager?.hasClients ?? false) {
        _pager!.jumpToPage(_index);
      }
      widget.onProgress?.call(page, pages, _pages.length <= 1 ? 1 : _index / (_pages.length - 1));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    if (scale != _lastScale) {
      _lastScale = scale;
      // 系统字体缩放会影响行高，延后一帧等布局尺寸稳定再重排。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_rebuild);
      });
    }
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        if (size != _size) {
          final first = _size == Size.zero;
          _size = size;
          _rebuild();
          if (first) _syncPager();
        }
        return widget.paged ? _paged() : _scrolled();
      },
    );
  }

  Widget _paged() {
    if (_pages.isEmpty) {
      return const Center(child: CupertinoActivityIndicator());
    }
    final controller = _pager ??= PageController(initialPage: _index);
    return PageView.builder(
      controller: controller,
      itemCount: _pages.length,
      onPageChanged: (i) {
        setState(() => _index = i);
        widget.onProgress?.call(page, pages, _pages.length <= 1 ? 1 : i / (_pages.length - 1));
      },
      itemBuilder: (context, i) => _pageView(_pages[i], i),
    );
  }

  /// 点按分区：左右三分之一翻页，中间切换工具层。
  ///
  /// 这个手势必须放在每一页内部，不能盖在 PageView 上面——盖上去的
  /// [GestureDetector] 会把横向拖动一并吞掉，左右滑动就翻不了页了。
  void _handleTap(TapUpDetails d, BoxConstraints c) {
    final x = d.globalPosition.dx;
    final third = c.maxWidth / 3;
    if (x < third) {
      if (widget.onTapLeft?.call() ?? false) return;
      if (_index > 0) _pager?.previousPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      return;
    }
    if (x > third * 2) {
      if (widget.onTapRight?.call() ?? false) return;
      if (_index < _pages.length - 1) _pager?.nextPage(duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
      return;
    }
    widget.onTapCenter?.call();
  }

  Widget _pageView(NovelPage page, int index) => LayoutBuilder(
        builder: (context, c) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _handleTap(d, c),
          child: Padding(
            padding: widget.padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (index == 0 && widget.header != null) widget.header!,
                // 分页已经算好高度，用裁剪兜住测量误差，避免最后一行被看到一半。
                Expanded(child: ClipRect(child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: _column(page.blocks)))),
              ],
            ),
          ),
        ),
      );

  Widget _scrolled() => NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          widget.onProgress?.call(page, pages, _scrollProgress);
          return false;
        },
        child: ListView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          padding: widget.padding,
          children: [
            if (widget.header != null) widget.header!,
            _column([for (final b in widget.blocks) b]),
          ],
        ),
      );

  Widget _column(List<Object> blocks) {
    final gap = (widget.style.fontSize ?? 18) * .9;
    final width = _size.width - widget.padding.horizontal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in blocks)
          // 滚动模式直接拿到原始段落字符串；分页模式拿到切好的 [NovelTextBlock]。
          if (b is String)
            Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: Text(b, style: widget.style, textAlign: TextAlign.justify),
            )
          else if (b is NovelTextBlock)
            Padding(
              padding: EdgeInsets.only(bottom: b.paragraphEnd ? gap : 0),
              child: Text(b.text, style: widget.style, textAlign: TextAlign.justify),
            )
          else if (b is NovelImageBlock)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: SizedBox(
                height: width * kNovelImageRatio,
                child: widget.imageBuilder?.call(b.url, width) ?? const Center(child: Icon(Icons.broken_image_outlined, size: 28)),
              ),
            )
          else if (b is NovelEndBlock)
            SizedBox(height: b.height, child: Center(child: widget.endCard)),
      ],
    );
  }
}

/// 页码：`3 / 31`，等宽数字不跳动。
class NovelPageLabel extends StatelessWidget {
  const NovelPageLabel({super.key, required this.page, required this.pages, required this.color});

  final int page;
  final int pages;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        '$page / $pages',
        style: TextStyle(fontSize: 15, color: color, fontFeatures: const [FontFeature.tabularFigures()]),
      );
}

/// 章节头：小字章节号 + 大标题。
class NovelChapterHeader extends StatelessWidget {
  const NovelChapterHeader({super.key, required this.label, required this.title, required this.ink, required this.muted});

  final String label;
  final String title;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: muted)),
            const SizedBox(height: 6),
            Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: ink)),
          ],
        ),
      );
}

/// 上下滚动 / 左右翻页切换：放在工具条上，和读书软件的常规位置一致。
class NovelModeToggle extends StatelessWidget {
  const NovelModeToggle({super.key, required this.paged, required this.color, required this.onChanged});

  final bool paged;
  final Color color;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: paged ? '切换为上下滚动' : '切换为左右翻页',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!paged),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(paged ? 'scroll' : 'pages', size: 17, color: color, stroke: 1.7),
                const SizedBox(width: 6),
                Text(paged ? '翻页' : '滚动', style: TextStyle(fontSize: 13, color: color)),
              ],
            ),
          ),
        ),
      );
}
