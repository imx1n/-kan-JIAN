import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 语义色板：纸白底、深墨、锈红强调（由 OKLCH 换算成 sRGB）。
class Palette {
  Palette._();

  static const bg = Color(0xFFF2F5F3);
  static const bar = Color(0xFFF7FAF8);
  static const tonal = Color(0xFFE5EDE6);
  static const tonal2 = Color(0xFFD6E4D8);
  static const line = Color(0xFFD4DBD8);
  static const ink = Color(0xFF213D42);
  static const ink2 = Color(0xFF3E5153);

  /// 元信息文字；在 bg / tonal / bar 上都 ≥ 4.5:1。
  static const ink3 = Color(0xFF586767);
  static const ink4 = Color(0xFF9DA7A6);
  static const accent = Color(0xFF954B38);
  static const accentSoft = Color(0xFFFCE3DB);
  static const sage = Color(0xFF5E7E5F);
  static const sageInk = Color(0xFF2E4A34);
  static const onInk = Color(0xFFF8FBF9);
  static const track = Color(0xFFD3DDD5);

  // 阅读器（深墨画布）
  static const rBg = Color(0xFF12181A);
  static const rBar = Color(0xFF1A2224);
  static const rLine = Color(0xFF313A3B);
  static const rInk = Color(0xFFE3EAE7);
  static const rInk2 = Color(0xFFA9B4B1);
  static const rMute = Color(0xFF8A9594);
  static const rThumb = Color(0xFFD2E4D2);

  // v1 名称，供轻小说阅读器与外观面板继续使用。
  static const paper = bg;
  static const secondary = ink3;
  static const barLine = line;
  static const progress = sage;
  static const mangaBg = rBg;
  static const mangaInk = rInk;
  static const mangaMuted = rInk2;
  static const mangaTrack = rLine;
  static const mangaThumb = rThumb;
}

/// Android 上 `serif` 会回退到系统的 Noto Serif CJK。
const kSerif = 'serif';

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Palette.ink,
    surface: Palette.bg,
    primary: Palette.ink,
    onPrimary: Palette.onInk,
    secondary: Palette.accent,
    surfaceContainerHigh: Palette.bar,
    surfaceContainerHighest: Palette.tonal,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.bg,
    splashFactory: InkSparkle.splashFactory,
    textTheme: Typography.blackMountainView.apply(bodyColor: Palette.ink, displayColor: Palette.ink),
    dividerColor: Palette.line,
    sliderTheme: const SliderThemeData(
      activeTrackColor: Palette.sage,
      inactiveTrackColor: Palette.track,
      thumbColor: Palette.bar,
      trackHeight: 3,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 18),
    ),
    dialogTheme: const DialogThemeData(backgroundColor: Palette.bar),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Palette.bar, showDragHandle: true),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, backgroundColor: Palette.ink),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Palette.ink),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

String formatPopular(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
  if (n >= 10000000) return '${(n / 10000).round()}万';
  if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
  return '$n';
}

/// `2026-11-03` → 今天 / 昨天 / 11月3日 / 2025年10月。
String formatDay(String ymd, {DateTime? now}) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  final today = now ?? DateTime.now();
  final diff = DateTime(today.year, today.month, today.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  return d.year == today.year ? '${d.month}月${d.day}日' : '${d.year}年${d.month}月';
}

String formatBytes(int bytes) {
  if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
  if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
  if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).round()} KB';
  return '$bytes B';
}
