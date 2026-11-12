import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 动效参数，按 `design/reader-motion`（2026-11-04 版，含优化）：
/// - iOS 为基准；Android 时长取 85%，位移更短。
/// - 主缓动 `cubic-bezier(.22,.75,.18,1)`，退场 `cubic-bezier(.4,0,1,1)`。
/// - 系统开了减少动态（iOS「减弱动态效果」/ Android「移除动画」）时时长为 0，状态直接到位。
/// - 状态先变、动画只是表现：动画不阻塞操作。
class Motion {
  Motion._();

  static const ease = Cubic(.22, .75, .18, 1);
  static const exit = Cubic(.4, 0, 1, 1);

  static bool get android => defaultTargetPlatform == TargetPlatform.android;

  /// 设计稿里的 iOS 毫秒数 → 当前平台的时长（不看减少动态，用于路由这类拿不到 context 的地方）。
  static Duration ms(int ios) => Duration(milliseconds: (ios * (android ? .85 : 1)).round());

  /// 同上，并跟随系统的减少动态。
  static Duration of(BuildContext context, int ios) => reduced(context) ? Duration.zero : ms(ios);

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// 位移：iOS / Android 两个值。
  static double dist(double ios, double androidPx) => android ? androidPx : ios;
}

/* ─────────── 页面转场 ─────────── */

/// 普通页面（详情、设置子页、搜索、账号…）。
///
/// iOS 保留系统的整页滑入和左缘滑动返回：设计稿的 30px 淡入会让返回手势跟不上手指，不用。
/// Android 用设计稿的短位移淡入：新页从右侧 20px 归位，旧页向左 8px 淡出；返回反向。
Route<T> appRoute<T>(WidgetBuilder builder) => Motion.android ? ShiftFadeRoute<T>(builder: builder, distance: 20) : CupertinoPageRoute<T>(builder: builder);

/// 进入 / 离开阅读器：两端都只做透明度交接，画面不横移。
/// 也不挂左缘返回手势：它会和横向翻页抢手势。返回用左上角按钮或系统返回。
Route<T> readerRoute<T>(WidgetBuilder builder) => ShiftFadeRoute<T>(builder: builder, distance: 0);

/// 搜索页：从触发它的那个控件「长出来」，而不是整页侧滑进来。
///
/// 搜索不是往下一层钻，它是从放大镜 / 搜索框那儿铺开的一块浮层。整页侧滑
/// 会让它读成「换了个页面」，还暗示左边缘能划回去——但搜索页没有下级，
/// 那个手势是空的。
///
/// [origin] 是触发控件的全局矩形（用 [rectOf] 取）。给了就从那个点缩放，
/// 没给就按屏幕中心缩放。
Route<T> searchRoute<T>(WidgetBuilder builder, {Rect? origin}) =>
    _GrowFadeRoute<T>(builder: builder, origin: origin);

/// 取一个控件在屏幕上的矩形，供 [searchRoute] 的起点用。
/// 拿不到（还没布局）就返回 null，转场退化成屏幕中心缩放。
Rect? rectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

class _GrowFadeRoute<T> extends PageRoute<T> {
  _GrowFadeRoute({required this.builder, this.origin});

  final WidgetBuilder builder;
  final Rect? origin;

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Motion.ms(260);

  @override
  Duration get reverseTransitionDuration => Motion.ms(160);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => builder(context);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final reduced = Motion.reduced(context);
    final size = MediaQuery.sizeOf(context);
    // 起点换算成 -1..1 的对齐坐标：Alignment(0,0) 是屏幕中心。
    var ax = 0.0;
    var ay = 0.0;
    final o = origin;
    if (o != null && size.width > 0 && size.height > 0) {
      ax = ((o.center.dx / size.width) * 2 - 1).clamp(-1.0, 1.0);
      ay = ((o.center.dy / size.height) * 2 - 1).clamp(-1.0, 1.0);
    }
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        if (reduced) return child!;
        double p;
        if (animation.status == AnimationStatus.reverse) {
          // 退场：已经决定了，系统快速回应
          p = Motion.exit.transform(1 - t);
        } else {
          p = Motion.ease.transform(t);
        }
        final scale = .92 + .08 * (animation.status == AnimationStatus.reverse ? 1 - p : p);
        final opacity = animation.status == AnimationStatus.reverse ? 1 - p : .2 + .8 * p;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale.clamp(.92, 1.0), alignment: Alignment(ax, ay), child: child),
        );
      },
    );
  }
}

/// 位移 + 透明度的页面转场。前进 320ms、返回 230ms（Android 85%）；
/// 离场的一方 180ms 内淡出、只移动 0.4 倍距离。
class ShiftFadeRoute<T> extends PageRoute<T> {
  ShiftFadeRoute({required this.builder, required this.distance, super.settings});

  final WidgetBuilder builder;

  /// 前进时新页的起始偏移（向右为正）。0 表示只做透明度。
  final double distance;

  @override
  bool get opaque => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Motion.ms(320);

  @override
  Duration get reverseTransitionDuration => Motion.ms(230);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => builder(context);

  /// 离场：在整段时长里的前 [part] 比例内用退场缓动完成。
  static double _leave(double q, double part) => Motion.exit.transform((q / part).clamp(0.0, 1.0));

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    // 注意：始终返回同一结构（Opacity → Transform），动画结束也不能直接返回 child，
    // 否则组件树形状一变，整页会被重新挂载、状态丢失。
    final reduced = Motion.reduced(context);
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        var opacity = 1.0;
        var dx = 0.0;
        // 本页：被推入 / 被弹出。
        final t = animation.value;
        if (t < 1) {
          if (animation.status == AnimationStatus.reverse) {
            final k = _leave(1 - t, 180 / 230);
            opacity = 1 - k;
            dx = distance * .4 * k;
          } else {
            final p = Motion.ease.transform(t);
            opacity = .15 + .85 * p;
            dx = distance * (1 - p);
          }
        }
        // 上面又压了一页（或上面那页正在离开）。
        final s = secondaryAnimation.value;
        if (s > 0) {
          if (secondaryAnimation.status == AnimationStatus.reverse) {
            final p = Motion.ease.transform(1 - s);
            opacity *= .15 + .85 * p;
            dx += -distance * (1 - p);
          } else {
            final k = _leave(s, 180 / 320);
            opacity *= 1 - k;
            dx += -distance * .4 * k;
          }
        }
        if (reduced) {
          opacity = 1;
          dx = 0;
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
      },
    );
  }
}

/* ─────────── 底部面板 ─────────── */

/// 面板遮罩：设计稿 `.sheet-scrim` 是 rgba(0,0,0,.36)。
///
/// 遮罩太重会把玻璃背面的内容全压暗，折射就看不出来了——面板会变成一块
/// 实心灰板。漫画阅读器用更轻的 [kSheetScrimReader]（对应 `.comic-settings
/// .sheet-scrim{background:#0002}`），阅读时尽量不打断画面。
const Color kSheetScrim = Color(0x5C000000);
const Color kSheetScrimReader = Color(0x14000000);

/// 底部面板（阅读设置、目录、阅读外观）：从下方 56px（Android 42px）淡入归位，340ms；
/// 完成时向下退出 220ms。设计稿表达不了的下拉关闭在这里补上。
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder, {Color scrim = kSheetScrim}) => Navigator.of(context)
    .push(_SheetRoute<T>(builder: builder, barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel, scrim: scrim));

class _SheetRoute<T> extends PopupRoute<T> {
  _SheetRoute({required this.builder, required this.barrierLabel, this.scrim = kSheetScrim});

  final WidgetBuilder builder;

  @override
  final String? barrierLabel;

  final Color scrim;

  @override
  Color? get barrierColor => scrim;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => Motion.ms(300);

  @override
  Duration get reverseTransitionDuration => Motion.ms(200);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) => Material(
    type: MaterialType.transparency,
    child: Align(
      alignment: Alignment.bottomCenter,
      child: _SheetDrag(child: Builder(builder: builder)),
    ),
  );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final reduced = Motion.reduced(context);
    final d = Motion.dist(56, 42);
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final t = animation.value;
        double opacity = 1, dy = 0;
        if (reduced || t >= 1) return Opacity(opacity: 1, child: Transform.translate(offset: Offset.zero, child: child));
        if (animation.status == AnimationStatus.reverse) {
          final k = Motion.exit.transform(1 - t);
          opacity = 1 - k;
          dy = d * k;
        } else {
          final p = Motion.ease.transform(t);
          opacity = .15 + .85 * p;
          dy = d * (1 - p);
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, dy), child: child),
        );
      },
    );
  }
}

/// 下拉关闭：拖动超过 96px 或下滑够快就关，否则弹回。面板里的列表、滑杆仍各自优先响应。
class _SheetDrag extends StatefulWidget {
  const _SheetDrag({required this.child});

  final Widget child;

  @override
  State<_SheetDrag> createState() => _SheetDragState();
}

class _SheetDragState extends State<_SheetDrag> with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(vsync: this)..addListener(() => setState(() => _dy = _from * (1 - Motion.ease.transform(_back.value))));
  double _dy = 0;
  double _from = 0;

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _end(DragEndDetails d) {
    if (_dy > 96 || (d.primaryVelocity ?? 0) > 700) {
      Navigator.of(context).maybePop();
      return;
    }
    _from = _dy;
    _back
      ..duration = Motion.of(context, 220)
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onVerticalDragStart: (_) => _back.stop(),
    onVerticalDragUpdate: (d) => setState(() => _dy = (_dy + d.delta.dy).clamp(0.0, double.infinity)),
    onVerticalDragEnd: _end,
    child: Transform.translate(offset: Offset(0, _dy), child: widget.child),
  );
}

/* ─────────── 小部件 ─────────── */

/// 阅读工具层的隐显：位置不变，只做 8px 位移（[dy]，上方工具为负、下方为正）和透明度。
/// 隐藏后不可点、读屏跳过；正文的排版和阅读位置不受影响。
class ChromeReveal extends StatelessWidget {
  const ChromeReveal({super.key, required this.visible, required this.dy, required this.child});

  final bool visible;
  final double dy;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: ExcludeSemantics(
      excluding: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: Motion.of(context, 200),
        curve: Motion.ease,
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: visible ? 0 : dy),
          duration: Motion.of(context, 240),
          curve: Motion.ease,
          builder: (_, v, c) => Transform.translate(offset: Offset(0, v), child: c),
          child: child,
        ),
      ),
    ),
  );
}

/// 第一次构建时从下方 [dy] 淡入归位（首次进入、同步结果）。换 key 可以重播。
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.dy = 7, this.from = .35, this.ms = 300, this.delayMs = 0});

  final Widget child;
  final double dy;
  final double from;
  final int ms;
  final int delayMs;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this);
  late final _curve = CurvedAnimation(parent: _c, curve: Interval(widget.delayMs / (widget.ms + widget.delayMs), 1, curve: Motion.ease));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final total = Motion.of(context, widget.ms + widget.delayMs);
    if (total == Duration.zero) {
      _c.value = 1;
      return;
    }
    _c
      ..duration = total
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    return AnimatedBuilder(
      animation: curve,
      child: widget.child,
      // 结束后也保持同一结构，避免子树重新挂载。
      builder: (_, c) => Opacity(
        opacity: widget.from + (1 - widget.from) * curve.value,
        child: Transform.translate(offset: Offset(0, widget.dy * (1 - curve.value)), child: c),
      ),
    );
  }
}

/// [value] 变化时让子组件弹一下：0.86 → 1.06 → 1，200ms（追更图标）。
///
/// 只是确认「听见了」，不该抢戏：之前 260ms、过冲到 1.10，点一下像按了个
/// 大按钮，手指已经松开了它还在动。
class BounceOnChange extends StatefulWidget {
  const BounceOnChange({super.key, required this.value, required this.child});

  final Object? value;
  final Widget child;

  @override
  State<BounceOnChange> createState() => _BounceOnChangeState();
}

class _BounceOnChangeState extends State<BounceOnChange> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, value: 1);
  static final _scale = TweenSequence([
    TweenSequenceItem(tween: Tween(begin: .86, end: 1.06).chain(CurveTween(curve: Motion.ease)), weight: 60),
    TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
  ]);

  @override
  void didUpdateWidget(BounceOnChange old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    final d = Motion.of(context, 200);
    if (d == Duration.zero) return;
    _c
      ..duration = d
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: _scale.animate(_c), child: widget.child);
}
