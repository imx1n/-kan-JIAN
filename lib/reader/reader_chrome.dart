import 'package:flutter/cupertino.dart';

import '../core/store.dart';
import '../ios/ios_theme.dart';
import '../ui/icons.dart';
import '../ui/motion.dart';
import 'mode_glyph.dart';
import 'page_fit.dart';
import 'reader_theme.dart';
import 'reading_mode.dart';

/// 阅读页顶部栏：整条横贯屏幕的底色栏，左起返回箭头 + 书名 + 章节名。
///
/// 高度 93（不含状态栏），内边距 18 / 22 / 17。返回键与两行文字垂直居中成一组，
/// 文字左对齐、长了省略。底色跟着阅读页背板走，不再用纯黑。
class ReaderTopBar extends StatelessWidget {
  const ReaderTopBar({
    super.key,
    required this.mangaTitle,
    required this.chapterTitle,
    required this.onBack,
    this.topInset = 0,
  });

  final String mangaTitle;
  final String chapterTitle;
  final VoidCallback onBack;

  /// 状态栏高度，由调用方传 `MediaQuery.paddingOf(context).top`。
  final double topInset;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: ReaderPalette.reader,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, topInset + 18, 22, 17),
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                Pressable(
                  onTap: onBack,
                  semanticLabel: '返回',
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 27,
                      child: AppIcon('back', size: 23, color: ReaderPalette.text, stroke: 1.9),
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mangaTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 20, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: .015, color: ReaderPalette.text),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, height: 1.25, color: ReaderPalette.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 阅读设置面板（从底部弹出）。
///
/// 结构：把手 + 可滚动的设置组 + 固定在底部的「完成」。组标题 16/w600、
/// 说明 13/muted，阅读方式是一排 66 的图标瓦片（[ModeGlyph] 三色纸页），
/// 点击区域和画质用胶囊，预加载与亮度共用带刻度的细轨滑块。
class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.mode,
    required this.onMode,
    required this.prefetch,
    required this.onPrefetch,
    required this.area,
    required this.onArea,
    required this.onClose,
    this.saver = false,
    this.onSaver,
    this.brightness = 1,
    this.onBrightness,
  });

  final ReadingMode mode;
  final ValueChanged<ReadingMode> onMode;
  final int prefetch;
  final ValueChanged<int> onPrefetch;
  final int area;
  final ValueChanged<int> onArea;
  final VoidCallback onClose;

  /// 省流画质开关；[onSaver] 为 null 时整块不显示。
  final bool saver;
  final ValueChanged<bool>? onSaver;

  /// 页面亮度（0.3–1）；[onBrightness] 为 null 时整块不显示。
  final double brightness;
  final ValueChanged<double>? onBrightness;

  /// 预加载页数的可选区间，和 `ReaderPrefs.mangaPrefetch` 的 clamp 保持一致。
  static const _prefetchMin = 1;
  static const _prefetchMax = 8;

  /// 点击区域六种方案，下标即 `ReaderPrefs.mangaArea`。
  static const _areaNames = ['关闭', '自适应', '左右', 'L 型', '边缘', 'Kindle'];

  /// 瓦片整块高度：方块 66 + 间距 6 + 名字 18。
  /// 瓦片方块 + 间距 + 标签行，再加上列表自己的 3px 底部留白（给选中描边和
  /// 按下缩放留的余量）。这 3px 必须算进高度预算，少算就会把标签行裁掉并报溢出。
  static const _stripHeight = ReaderPalette.tile + ReaderPalette.tileGap + 18 + 3;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

/// 面板自己持有一份设置副本。
///
/// 之前它是 `StatelessWidget`，选中态全靠外层 `setState` 传进来——每点一下
/// 都要走「回调 → 写偏好 → 通知 → 阅读页整树重建 → 面板重建」这一整圈，
/// 面板的高亮和描边要等这一圈走完才开始动，看上去就是点了没反应。
/// 现在点击立刻改本地状态、同一帧就出动画，外层只负责持久化。
class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReadingMode _mode = widget.mode;
  late int _prefetch = widget.prefetch;
  late int _area = widget.area;
  late bool _saver = widget.saver;
  late PageFit _fit = PageFit.fromValue(ReaderPrefs.instance.mangaFit);

  /// 亮度单独走通知器。
  ///
  /// 拖滑块每帧都在变，如果走 `setState`，整个面板（6 个 SVG 瓦片 + 所有文字）
  /// 每帧重建一次，滑动就发涩。现在只有滑块和右侧百分比跟着重建。
  late final _brightness = ValueNotifier<double>(widget.brightness);

  @override
  void dispose() {
    _brightness.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final screenH = MediaQuery.sizeOf(context).height;
    // 顶部至少留 120 给阅读页，同时不超过屏高 90%。
    // 面板最多占屏高 62%：上方留出足够高度让当前页留在视野里，
    // 打开设置时看到的是「盖在阅读页上的面板」，而不是一整块灰。
    final maxH = (screenH - pad.top - 160).clamp(0.0, screenH * .62);
    const shape = BorderRadius.vertical(top: Radius.circular(ReaderPalette.sheetRadius));

    return Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(color: IosColors.isDark ? const Color(0x33000000) : const Color(0x22000000), blurRadius: 22, offset: const Offset(0, -3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: ColoredBox(
          color: ReaderPalette.sheet,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: ReaderPalette.grip, borderRadius: BorderRadius.circular(2)),
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _group(
                          title: '阅读模式',
                          caption: '条漫是连续上下滚动；单页可以横向或纵向翻页。',
                          gap: 10,
                          child: SizedBox(
                            height: ReaderSettingsSheet._stripHeight,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              clipBehavior: Clip.none,
                              padding: const EdgeInsets.only(right: 22, bottom: 3),
                              itemCount: ReadingMode.values.length,
                              separatorBuilder: (_, _) => const SizedBox(width: ReaderPalette.tileStripGap),
                              itemBuilder: (context, i) => _ModeTile(
                                mode: ReadingMode.values[i],
                                selected: ReadingMode.values[i] == _mode,
                                onTap: () {
                                  if (ReadingMode.values[i] == _mode) return;
                                  // 先改本地状态：同一帧里描边和对勾就开始动。
                                  setState(() => _mode = ReadingMode.values[i]);
                                  widget.onMode(ReadingMode.values[i]);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _group(
                          title: '预加载页面个数',
                          caption: '当前页前后各预加载几页：数值越大越少等待，也越费流量。',
                          gap: 0,
                          child: Row(
                            children: [
                              Expanded(
                                child: _StepSlider(
                                  value: _prefetch.toDouble().clamp(ReaderSettingsSheet._prefetchMin.toDouble(), ReaderSettingsSheet._prefetchMax.toDouble()),
                                  min: ReaderSettingsSheet._prefetchMin.toDouble(),
                                  max: ReaderSettingsSheet._prefetchMax.toDouble(),
                                  ticks: ReaderSettingsSheet._prefetchMax - ReaderSettingsSheet._prefetchMin + 1,
                                  snap: true,
                                  onChanged: (v) {
                                    final n = v.round();
                                    if (n == _prefetch) return;
                                    setState(() => _prefetch = n);
                                    widget.onPrefetch(n);
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  '$_prefetch 页',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ReaderPalette.text, fontFeatures: const [FontFeature.tabularFigures()]),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _group(
                          title: '点击区域',
                          caption: '点按屏幕哪一块翻页；上下阅读建议 L 型，单手用大拇指够得着就选边缘。',
                          gap: 9,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            child: Row(
                              children: [
                                for (var i = 0; i < ReaderSettingsSheet._areaNames.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 6),
                                  ReaderPill(
                                    label: ReaderSettingsSheet._areaNames[i],
                                    selected: _area == i,
                                    onTap: () {
                                      if (_area == i) return;
                                      setState(() => _area = i);
                                      widget.onArea(i);
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _group(
                          title: '图片适配',
                          caption: '纵向阅读建议「适应宽度」，页面会首尾相接、不留白边。',
                          gap: 9,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            clipBehavior: Clip.none,
                            child: Row(
                              children: [
                                for (var i = 0; i < PageFit.values.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 6),
                                  ReaderPill(
                                    label: PageFit.values[i].label,
                                    selected: _fit == PageFit.values[i],
                                    onTap: () {
                                      if (_fit == PageFit.values[i]) return;
                                      setState(() => _fit = PageFit.values[i]);
                                      ReaderPrefs.instance.mangaFit = PageFit.values[i].value;
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (widget.onSaver != null) ...[
                          const SizedBox(height: 12),
                          _group(
                            title: '图片画质',
                            caption: '源站只提供 800px（省流）和 1500px（标准）两种。',
                            gap: 9,
                            child: Row(
                              children: [
                                ReaderPill(
                                  label: '省流',
                                  minWidth: 57,
                                  check: true,
                                  selected: _saver,
                                  onTap: () {
                                    if (_saver) return;
                                    setState(() => _saver = true);
                                    widget.onSaver!(true);
                                  },
                                ),
                                const SizedBox(width: 6),
                                ReaderPill(
                                  label: '标准',
                                  minWidth: 57,
                                  check: true,
                                  selected: !_saver,
                                  onTap: () {
                                    if (!_saver) return;
                                    setState(() => _saver = false);
                                    widget.onSaver!(false);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (widget.onBrightness != null) ...[
                          const SizedBox(height: 12),
                          _group(
                            title: '页面亮度',
                            caption: '只压暗画面，不改系统亮度；适合关灯看。',
                            gap: 0,
                            child: ValueListenableBuilder<double>(
                              valueListenable: _brightness,
                              builder: (context, b, _) => Row(
                                children: [
                                  Expanded(
                                    child: _StepSlider(
                                      value: b.clamp(.3, 1.0),
                                      min: .3,
                                      max: 1,
                                      ticks: 8,
                                      onChanged: (v) {
                                        _brightness.value = v;
                                        widget.onBrightness!(v);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '${(b * 100).round()}%',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ReaderPalette.text, fontFeatures: const [FontFeature.tabularFigures()]),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // 底部按钮固定在面板底，不跟内容一起滚。
                Padding(
                  padding: EdgeInsets.fromLTRB(22, 8, 22, pad.bottom + 16),
                  child: Pressable(
                    onTap: widget.onClose,
                    haptic: true,
                    child: Container(
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: ReaderPalette.button, borderRadius: BorderRadius.circular(ReaderPalette.buttonRadius)),
                      child: Text(
                        '完成',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .04, color: ReaderPalette.buttonInk),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 一组设置：标题 + 说明 + 间距 [gap] + 内容。
  Widget _group({required String title, required String caption, required double gap, required Widget child}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600, letterSpacing: .015, color: ReaderPalette.text)),
          const SizedBox(height: 3),
          Text(caption, style: TextStyle(fontSize: 13, height: 20 / 13, color: ReaderPalette.muted)),
          if (gap > 0) SizedBox(height: gap),
          child,
        ],
      );
}

/// 阅读方式瓦片：66 的圆角方块里放三色纸页图标（选中多一个对勾），下面挂一行短名。
class _ModeTile extends StatelessWidget {
  const _ModeTile({required this.mode, required this.selected, required this.onTap});

  final ReadingMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        pressedScale: .97,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: ReaderPalette.tile,
              height: ReaderPalette.tile,
              // 底色和描边都过渡：点下去是「逐渐描上边」而不是瞬间出现一个框。
              // 描边宽度不能动画（会重排），所以固定 1.5，只动颜色。
              child: AnimatedContainer(
                duration: Motion.of(context, 180),
                curve: Motion.ease,
                // 图标控件用描边：图标本身有纸页层次，反相会把层次压平。
                decoration: BoxDecoration(
                  color: selected ? ReaderPalette.selected : ReaderPalette.surface,
                  borderRadius: BorderRadius.circular(ReaderPalette.tileRadius),
                  border: Border.all(color: selected ? ReaderPalette.selectedLine : const Color(0x00000000), width: ReaderPalette.selectedStroke),
                ),
                child: Stack(
                  children: [
                    Center(child: ModeGlyph(mode: mode, selected: selected, size: ReaderPalette.tileGlyph)),
                    // 对勾用缩放 + 淡入，和描边同时到位。
                    Positioned(
                      top: 5,
                      right: 5,
                      child: AnimatedScale(
                        scale: selected ? 1 : .6,
                        duration: Motion.of(context, 180),
                        curve: Motion.ease,
                        child: AnimatedOpacity(
                          opacity: selected ? 1 : 0,
                          duration: Motion.of(context, 140),
                          child: AppIcon('check', size: 11, stroke: 2.2, color: ReaderPalette.selectedInk),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: ReaderPalette.tileGap),
            SizedBox(
              height: 18,
              child: AnimatedDefaultTextStyle(
                duration: Motion.of(context, 180),
                curve: Motion.ease,
                style: TextStyle(
                  fontSize: ReaderPalette.tileLabel,
                  height: 18 / ReaderPalette.tileLabel,
                  fontWeight: FontWeight.w500,
                  color: selected ? ReaderPalette.selectedInk : ReaderPalette.muted,
                ),
                child: Text(
                  mode.shortLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  // 这一行是固定 18 高的度量标签（设计稿 12/18），跟随系统字号会被
                  // 撑到 19 而溢出 1px，所以按设计稿锁死不缩放。
                  textScaler: TextScaler.noScaling,
                ),
              ),
            ),
          ],
        ),
      );
}

/// 胶囊选项：点击区域与图片画质共用。[check] 为真时选中态右侧加一个对勾。
class ReaderPill extends StatelessWidget {
  const ReaderPill({super.key, required this.label, required this.selected, required this.onTap, this.minWidth = 0, this.check = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double minWidth;
  final bool check;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis);
    // 反相是一次底色渐变，不是瞬间翻转——后者在「画质 / 点击区域」这种
    // 两三个选项并排时会有明显的闪。
    final box = AnimatedContainer(
      duration: Motion.of(context, 180),
      curve: Motion.ease,
      constraints: BoxConstraints(minHeight: ReaderPalette.choiceHeight, minWidth: minWidth),
      padding: EdgeInsets.fromLTRB(12, 10, check && selected ? 24 : 12, 10),
      alignment: Alignment.center,
      // 文字控件用反相：选中 = 实心主文字色 + 底色文字。没有色相可用时，
      // 这是唯一能在浅色和深色下都保持最高对比的做法。
      decoration: BoxDecoration(
        color: selected ? ReaderPalette.invert : ReaderPalette.surface,
        borderRadius: BorderRadius.circular(ReaderPalette.choiceRadius),
      ),
      child: AnimatedDefaultTextStyle(
        duration: Motion.of(context, 180),
        curve: Motion.ease,
        style: TextStyle(fontSize: 13, height: 22 / 13, fontWeight: FontWeight.w500, color: selected ? ReaderPalette.onInvert : ReaderPalette.text),
        child: text,
      ),
    );
    return Pressable(
      onTap: onTap,
      child: check
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                box,
                if (selected)
                  Positioned(
                    top: 16,
                    right: 7,
                    child: AnimatedOpacity(
                      opacity: selected ? 1 : 0,
                      duration: Motion.of(context, 160),
                      child: AppIcon('check', size: 10, stroke: 2.2, color: ReaderPalette.onInvert),
                    ),
                  ),
              ],
            )
          : box,
    );
  }
}

/// 细轨滑块：4 高轨道 + 均匀刻度点 + 16 的圆形手柄。
///
/// 没用 Material `Slider`：它没法在轨道上画刻度点，而且这里只需要「数值 + 拖一下」
/// 这一层能力，自己按位置算比调一套 SliderTheme 更直接。
class _StepSlider extends StatelessWidget {
  const _StepSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.ticks,
    this.snap = false,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// 刻度点个数（含两端）。
  final int ticks;

  /// 拖动时吸附到整数（预加载页数用）。
  final bool snap;

  static const _height = 44.0;

  @override
  Widget build(BuildContext context) {
    final span = max - min;
    return LayoutBuilder(
      builder: (context, box) {
        // 手柄半径即两端内缩，手柄到头时正好贴住轨道端头不掉出去。
        final inset = ReaderPalette.thumbSize / 2;
        final travel = box.maxWidth - inset * 2;
        final ratio = span <= 0 ? 0.0 : ((value - min) / span).clamp(0.0, 1.0);

        void pick(Offset local) {
          if (travel <= 0 || span <= 0) return;
          final r = ((local.dx - inset) / travel).clamp(0.0, 1.0);
          final v = min + r * span;
          onChanged((snap ? v.roundToDouble() : v).clamp(min, max));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => pick(d.localPosition),
          onHorizontalDragUpdate: (d) => pick(d.localPosition),
          child: SizedBox(
            height: _height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 轨道
                Positioned(
                  left: 0,
                  right: 0,
                  top: (_height - ReaderPalette.trackHeight) / 2,
                  height: ReaderPalette.trackHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: ReaderPalette.track, borderRadius: BorderRadius.circular(5)),
                  ),
                ),
                // 已选段
                Positioned(
                  left: 0,
                  top: (_height - ReaderPalette.trackHeight) / 2,
                  height: ReaderPalette.trackHeight,
                  width: inset + travel * ratio,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: ReaderPalette.accent, borderRadius: BorderRadius.circular(5)),
                  ),
                ),
                // 刻度点
                for (var i = 0; i < ticks; i++)
                  Positioned(
                    left: inset + travel * (ticks <= 1 ? 0 : i / (ticks - 1)) - ReaderPalette.tickSize / 2,
                    top: (_height - ReaderPalette.tickSize) / 2,
                    width: ReaderPalette.tickSize,
                    height: ReaderPalette.tickSize,
                    child: DecoratedBox(
                      decoration: BoxDecoration(shape: BoxShape.circle, color: ReaderPalette.tick),
                    ),
                  ),
                // 手柄
                Positioned(
                  left: inset + travel * ratio - ReaderPalette.thumbSize / 2,
                  top: (_height - ReaderPalette.thumbSize) / 2,
                  width: ReaderPalette.thumbSize,
                  height: ReaderPalette.thumbSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ReaderPalette.thumb,
                      boxShadow: const [BoxShadow(color: Color(0x26151724), blurRadius: 4, offset: Offset(0, 1))],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 阅读页底部主栏：上一话 · 页码滑块 · 下一话，下面一排小图标（设置 / 目录）。
///
/// 用实底 [ReaderPalette.sheet] 而不是毛玻璃：深浅两套主题下玻璃都会把浅色
/// 主题的底弄脏，实底 + 顶部一条发丝边 + 上方投影已经够分层。
class ReaderControlBar extends StatelessWidget {
  const ReaderControlBar({
    super.key,
    required this.onSettings,
    required this.onCatalog,
    this.onPrevChapter,
    this.onNextChapter,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChange,
    this.bottomInset = 0,
  });

  final VoidCallback onSettings;
  final VoidCallback onCatalog;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;

  /// 1 基，显示用。
  final int currentPage;
  final int totalPages;

  /// 传 0 基下标。
  final ValueChanged<int> onPageChange;

  final double bottomInset;

  static const _tabular = [FontFeature.tabularFigures()];

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: ReaderPalette.sheet,
          border: Border(top: BorderSide(color: ReaderPalette.border)),
          boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 20, offset: Offset(0, -5))],
        ),
        padding: EdgeInsets.only(bottom: bottomInset + 8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 46,
                child: Row(
                  children: [
                    _arrow('chevronLeft', '上一话', onPrevChapter),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Row(
                        children: [
                          Text('$currentPage', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ReaderPalette.text, fontFeatures: _tabular)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CupertinoSlider(
                              value: totalPages <= 0 ? 1 : currentPage.toDouble().clamp(1.0, totalPages.toDouble()),
                              min: 1,
                              max: totalPages <= 1 ? 2 : totalPages.toDouble(),
                              divisions: totalPages > 1 ? totalPages - 1 : null,
                              activeColor: ReaderPalette.accent,
                              onChanged: totalPages > 1 ? (v) => onPageChange(v.round() - 1) : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$totalPages', style: TextStyle(fontSize: 14, color: ReaderPalette.muted, fontFeatures: _tabular)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    _arrow('chevronRight', '下一话', onNextChapter),
                  ],
                ),
              ),
              Container(height: .5, color: ReaderPalette.border),
              SizedBox(
                height: 40,
                child: Row(
                  children: [
                    _mini('settings', '设置', onSettings),
                    _mini('list', '目录', onCatalog),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _arrow(String icon, String label, VoidCallback? onTap) {
    final disabled = onTap == null;
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Opacity(
        opacity: disabled ? .4 : 1,
        child: SizedBox.square(
          dimension: 40,
          child: Center(child: AppIcon(icon, size: 20, color: disabled ? ReaderPalette.muted : ReaderPalette.text, stroke: 2)),
        ),
      ),
    );
  }

  Widget _mini(String icon, String label, VoidCallback onTap) => Expanded(
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon, size: 17, color: ReaderPalette.text, stroke: 1.7),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12, color: ReaderPalette.text)),
            ],
          ),
        ),
      );
}
