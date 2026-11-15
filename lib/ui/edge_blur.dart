import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show ProgressiveBlur, ProgressiveBlurDirection;

/// 模糊贴在哪条边上。
enum EdgeBlurSide { top, bottom }

/// 滚动内容与悬浮控件交界处的渐进模糊，对应 iOS 26 的 scroll edge effect。
///
/// ## 规范来自 Apple，不是我们拍的
///
/// SwiftUI 的 `scrollEdgeEffectStyle(_:for:)` / UIKit 的 `UIScrollView.topEdgeEffect`
/// 是同一件事。Apple 的定义是「**滚动内容与固定控件之间的过渡**」，并且明确
/// 作用在「滚动方向上**两端**」，不只是顶部。三档风格：
///
/// - `.hard`：近乎不透明、有一条清晰的直线分界。密集界面（日历、可排序表头）用。
/// - `.soft`：柔和模糊、**越靠近控件越浓**，没有分界线。常规情形。
/// - `.automatic`：由系统按平台和上下文决定。
///
/// 我们实现的是 `.soft`。Apple 反复强调的一条是「控件后面不要再自己加背景或
/// 压暗层，那会干扰这个效果」——所以我们这条带子只做模糊 + 极淡的底色，
/// 不做实底、不做描边。
///
/// 底层用 `liquid_glass_widgets` 的 [ProgressiveBlur]：它把模糊做成
/// `BackdropFilter` 的单通道 shader，一次 backdrop 采样就得到连续渐变。
/// 自己叠多层 `BackdropFilter` 也能凑，但每层多一次采样、层间还会留台阶。
///
/// ## 两端强度不同，是有意的
///
/// 顶部压着状态栏，那条带子是「内容从状态栏下面钻出来」的唯一过渡，要够浓；
/// 底部是悬浮胶囊，胶囊外侧的内容本来就该清楚（参考界面逐像素确认过），
/// 所以底部只在胶囊正上方铺一小段、用很小的力度——它是让胶囊「浮起来」的
/// 一层薄雾，不是一条横贯屏幕的遮罩。上一版底部给了 124dp 全宽带，
/// 白吃掉一整行内容，那才是「突兀」。
///
/// [reduce] 为真（系统「减少透明度」/ 高对比）时**不做模糊**，只留底色：
/// 模糊本身降低对比度，辅助功能开启时应该让字更清楚，不是更糊。
class EdgeBlur extends StatelessWidget {
  const EdgeBlur({
    super.key,
    required this.height,
    this.sigma = 14,
    this.side = EdgeBlurSide.top,
    this.tint,
    this.tintAlpha = .5,
    this.reduce = false,
  });

  /// 模糊带高度（逻辑像素）。带子之外的内容完全不受影响。
  final double height;

  /// 最靠边处的 sigma；往带子内沿渐弱到 0。
  final double sigma;

  final EdgeBlurSide side;

  /// 压在模糊上面的底色。给 null 就只模糊、不染色。
  final Color? tint;

  /// 底色在最靠边处的不透明度，往内沿线性降到 0。
  final double tintAlpha;

  /// 「减少透明度」是否开启。开启时退化成纯底色。
  final bool reduce;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();
    final bottom = side == EdgeBlurSide.bottom;
    final ink = tint;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            // 减少透明度：不模糊。模糊会把字形边缘化开，正好和这个设置要的相反。
            if (!reduce)
              Positioned.fill(
                child: ProgressiveBlur(
                  maxSigma: sigma,
                  direction: bottom ? ProgressiveBlurDirection.bottomToTop : ProgressiveBlurDirection.topToBottom,
                ),
              ),
            if (ink != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: bottom ? Alignment.bottomCenter : Alignment.topCenter,
                      end: bottom ? Alignment.topCenter : Alignment.bottomCenter,
                      colors: [ink.withValues(alpha: tintAlpha), ink.withValues(alpha: 0)],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
