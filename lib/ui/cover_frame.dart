import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 封面上的「书本框」：书脊折痕、暗角、覆光、纸纹、内描边。
///
/// 全部是程序画的，不占图片体积。只有在「我的 → 外观 → 自定义封面效果」
/// 打开时才挂上去；关闭时封面上一个额外图层都没有，加载和绘制都是原图的成本。
///
/// 数值照搬原型 `design/ui-v3/board.css` 的 `.cover .cl.*`，小尺寸封面
/// （40px 那种）用一组收窄的参数，否则整张脸全是麻点。
class CoverFrame extends StatelessWidget {
  const CoverFrame({super.key, this.small = false, this.plain = false, this.radius = 2});

  final bool small;

  /// 和外面 `ClipRRect` 用同一个圆角。写死会让描边和裁切对不上：
  /// 裁切 r=4、描边 r=3 时四角的弧露在描边外，差得越多越明显。
  final double radius;

  /// 没有真实封面（占位底色 + 书名）时关掉颗粒：纸纹要靠画面本身的明暗撑着，
  /// 铺在一片平底上只会显得脏。
  final bool plain;

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(foregroundPainter: _FramePainter(small: small, plain: plain, radius: radius), size: Size.infinite));
}

/// 140×140 的纸纹瓦片，只会生成一次，全 App 的封面共用。
///
/// 瓦片本身是 140 格噪点，平铺时再整体缩放到 140dp / 64dp，所以一格的
/// 实际大小是「跨度 ÷ 140」，不是 1dp——见 `_FramePainter._grain`。
ui.Image? _grainTile;

const int _grainSize = 140;

ui.Image _grainImage() {
  final cached = _grainTile;
  if (cached != null) return cached;
  const n = _grainSize;
  final noise = Float32List(n * n);
  // xorshift：固定种子，每次启动的颗粒一模一样，截图比对不会抖。
  var s = 0x2545F491;
  for (var i = 0; i < noise.length; i++) {
    s ^= (s << 13) & 0xFFFFFFFF;
    s ^= s >> 17;
    s ^= (s << 5) & 0xFFFFFFFF;
    s &= 0xFFFFFFFF;
    noise[i] = (s & 0xFF) / 255.0;
  }
  // 3×3 环绕均值：把单像素白噪声压成柔和的小颗粒，不然就是电视雪花。
  final soft = Float32List(n * n);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      var sum = 0.0;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = (y + dy + n) % n;
        for (var dx = -1; dx <= 1; dx++) {
          sum += noise[yy * n + (x + dx + n) % n];
        }
      }
      soft[y * n + x] = sum / 9;
    }
  }
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final d = (soft[y * n + x] - .5) * 2;
      final a = d.abs() * .16;
      if (a < .004) continue;
      paint.color = (d > 0 ? const Color(0xFFFFFFFF) : const Color(0xFF000000)).withValues(alpha: a);
      canvas.drawRect(Rect.fromLTWH(x * 1.0, y * 1.0, 1, 1), paint);
    }
  }
  return _grainTile = recorder.endRecording().toImageSync(n, n);
}

class _FramePainter extends CustomPainter {
  const _FramePainter({required this.small, required this.plain, required this.radius});

  final bool small;
  final bool plain;
  final double radius;

  // ── 着色器缓存 ───────────────────────────────────────────────────────────
  //
  // 这四层全是渐变 / 平铺。`ui.Gradient.*` 和 `ui.ImageShader` 每次调用都
  // 分配一个原生对象，以前是每帧每个封面各建四个、从不释放，靠 GC 慢慢收。
  // 三列网格一屏六到九个封面，滚动时就是每帧几十次分配。
  //
  // 渐变只跟封面尺寸走（尺寸就那么几档），所以按尺寸缓存；纸纹只跟
  // [small] 走。缓存不设上限也没事——档位数由布局决定，几十个封顶。
  static final _spineCache = <String, ui.Shader>{};
  static final _sheenCache = <String, ui.Shader>{};
  static final _grainCache = <bool, ui.ImageShader>{};
  static ui.Shader? _vignetteShader;

  /// 暗角：椭圆 122% × 94%、圆心在 50% / 38%，从 56% 处开始压暗到 11%。
  ///
  /// 它是唯一不依赖尺寸的一层——坐标在 [Canvas] 的变换里，shader 本身永远是
  /// 单位圆，所以全进程一份就够。
  static ui.Shader _vignetteUnit() =>
      _vignetteShader ??= ui.Gradient.radial(
        Offset.zero,
        1,
        [const Color(0x00000000), const Color(0xFF000000).withValues(alpha: .11)],
        [.56, 1],
      );

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    _spine(canvas, w, h);
    _vignette(canvas, w, h);
    _sheen(canvas, w, h);
    if (!plain) _grain(canvas, size);
    _edge(canvas, size);
  }

  /// 书脊：左边缘一条「白高光 → 深折痕 → 渐淡」的横向渐变。
  void _spine(Canvas canvas, double w, double h) {
    const clear = Color(0xFFFFFFFF);
    final key = '${small ? 's' : 'l'}:${w.toStringAsFixed(2)}x${h.toStringAsFixed(2)}';
    final shader = _spineCache[key] ??= () {
      final stops = small
          ? <double>[0, .6 / w, 1.2 / w, 2.2 / w, .22]
          : <double>[0, .7 / w, 1.5 / w, 3 / w, 6 / w, .16];
      final colors = small
          ? <Color>[
              clear.withValues(alpha: 0),
              clear.withValues(alpha: .10),
              const Color(0xFF000000).withValues(alpha: .26),
              const Color(0xFF000000).withValues(alpha: .10),
              const Color(0xFF000000).withValues(alpha: 0),
            ]
          : <Color>[
              clear.withValues(alpha: 0),
              clear.withValues(alpha: .10),
              const Color(0xFF000000).withValues(alpha: .30),
              const Color(0xFF000000).withValues(alpha: .14),
              const Color(0xFF000000).withValues(alpha: .045),
              const Color(0xFF000000).withValues(alpha: 0),
            ];
      return ui.Gradient.linear(
        Offset.zero,
        Offset(w, 0),
        colors,
        [for (final s in stops) s.clamp(0.0, 1.0)],
      );
    }();
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = shader);
  }

  /// 暗角：椭圆 122% × 94%、圆心在 50% / 38%，从 56% 处开始压暗到 11%。
  void _vignette(Canvas canvas, double w, double h) {
    canvas.save();
    canvas.translate(w * .5, h * .38);
    canvas.scale(w * 1.22, h * .94);
    canvas.drawRect(const Rect.fromLTWH(-1, -1, 2, 2), Paint()..shader = _vignetteUnit());
    canvas.restore();
  }

  /// 覆光：148° 方向的一道柔光，左上白 .17，到 34% 处收干净。
  void _sheen(Canvas canvas, double w, double h) {
    const dx = .52992; // sin 148°
    const dy = .84805; // -cos 148°
    final key = '${w.toStringAsFixed(2)}x${h.toStringAsFixed(2)}';
    final shader = _sheenCache[key] ??= () {
      final len = w * dx + h * dy;
      final mid = Offset(w / 2, h / 2);
      const white = Color(0xFFFFFFFF);
      return ui.Gradient.linear(
        mid - Offset(dx, dy) * (len / 2),
        mid + Offset(dx, dy) * (len / 2),
        [
          white.withValues(alpha: .17),
          white.withValues(alpha: .04),
          white.withValues(alpha: 0),
        ],
        [0, .17, .34],
      );
    }();
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..shader = shader);
  }

  /// 纸纹：一张固定种子的 140×140 颗粒图平铺。
  ///
  /// 拼接变换把瓦片跨度缩到 [tile]（140 / 64dp），所以一格噪点的实际大小是
  /// `tile / _grainSize`：大封面约 1dp，小封面约 .46dp。在 2.75 倍屏上
  /// 正好是「一个物理像素一个噪点」——再密就会细过像素、和屏幕栅格
  /// 打出摩尔纹，看起来像电视雪花而不是纸。
  void _grain(Canvas canvas, Size size) {
    final shader = _grainCache[small] ??= () {
      const n = _grainSize;
      final tile = small ? 64.0 : 140.0;
      final k = tile / n;
      final m = Float64List.fromList(<double>[k, 0, 0, 0, 0, k, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
      return ui.ImageShader(_grainImage(), TileMode.repeated, TileMode.repeated, m);
    }();
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  /// 内描边：外一道 1.4px 的黑、里一道 .6px 的白，让封面像压在纸面上。
  void _edge(Canvas canvas, Size size) {
    final r = Radius.circular(radius);
    final outer = RRect.fromRectAndRadius((Offset.zero & size).deflate(.7), r);
    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = small ? 1.2 : 1.4
        ..color = const Color(0xFF000000).withValues(alpha: small ? .09 : .10),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius((Offset.zero & size).deflate(.3), r),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = small ? .5 : .6
        ..color = const Color(0xFFFFFFFF).withValues(alpha: small ? .10 : .13),
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.small != small || old.plain != plain || old.radius != radius;
}
