import 'package:flutter/widgets.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' show ProgressiveBlur, ProgressiveBlurDirection;

/// 顶部边栏的渐进模糊：贴着屏幕顶端最糊，往下渐次回到完全清楚。
///
/// 对应 iOS 26 的 scroll edge effect（UIKit 是 `UIScrollView.topEdgeEffect`，
/// SwiftUI 是 `scrollEdgeEffectStyle(_:for:)` 的 `.soft`）：滚动内容经过控制条
/// 时从清楚平滑过渡到近乎不透明，而不是被一条硬边切断。
///
/// 底层用 `liquid_glass_widgets` 的 [ProgressiveBlur]：模糊做成 `BackdropFilter`
/// 的单通道 shader，一次 backdrop 采样就得到连续渐变。自己叠
/// `BackdropFilter` 也能凑，但每层多一次采样、层间还会留台阶。
///
/// **只有顶部。** 底部标签栏不需要全宽渐隐——那会白吃一行内容；标签栏自己的
/// 玻璃已经负责了贴在它下面的那部分。参考的界面里，胶囊外侧的内容一直到
/// 屏幕底边都是清楚的。
///
/// **高度就是全部**：给多高就只影响多高，不额外铺过渡段。大标题就在状态栏
/// 正下方，多出来的每一像素都是拿内容换的。
///
/// 半透明底色单独压一层，不做进 shader：光靠模糊压不住高对比的封面，
/// 糊完还能认出轮廓，标题压上去就脏了。系统材质一直是「模糊 + 半透明底」。
class EdgeBlur extends StatelessWidget {
  const EdgeBlur({
    super.key,
    required this.height,
    this.sigma = 14,
    this.tint,
    this.tintAlpha = .5,
  });

  /// 模糊带高度（逻辑像素）。带子之外的内容完全不受影响。
  final double height;

  /// 顶端处的 sigma；往下渐弱到 0。
  final double sigma;

  /// 压在模糊上面的底色。给 null 就只模糊、不染色。
  final Color? tint;

  /// 底色在顶端的不透明度，往下线性降到 0。
  final double tintAlpha;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();
    final ink = tint;
    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: ProgressiveBlur(maxSigma: sigma, direction: ProgressiveBlurDirection.topToBottom),
            ),
            if (ink != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
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
