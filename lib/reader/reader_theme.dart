import 'package:flutter/widgets.dart';

import '../ios/ios_theme.dart';

/// 阅读器专用色板与尺寸令牌，从设计稿 `reader-settings/index.html` 逐值搬来。
///
/// 和 [IosColors] 一样按 `IosColors.isDark` 分两套：深色是「炭灰 · 灰蓝」，
/// 浅色是「净白 · 灰蓝」。强调色是灰蓝而不是暖橙——暖色留给书名、收藏这类
/// 内容态的强调，阅读设置面板里的「选中」是状态而不是情绪，用冷色更安静。
///
/// 界面里所有颜色都从这里取，不再出现裸的 `Color(0x...)` 字面量。
/// 因为要跟着主题切换，这些是 getter 不是 const，调用处也就不能写 `const`。
class ReaderPalette {
  ReaderPalette._();

  static bool get _dark => IosColors.isDark;

  // ── 底层 ──

  /// 阅读页背板（图片周边）。
  static Color get reader => _dark ? const Color(0xFF1B1C20) : const Color(0xFFF1F1F4);

  /// 设置面板、顶部栏、底部栏。
  static Color get sheet => _dark ? const Color(0xFF26272C) : const Color(0xFFFCFCFD);

  /// 漫画纸面底色（图片还没到位时露出来的那层）。
  static Color get page => _dark ? const Color(0xFFFAFAFA) : const Color(0xFFFFFFFF);

  // ── 文字三级 ──
  static Color get text => _dark ? const Color(0xFFEEEEF1) : const Color(0xFF33343C);
  static Color get muted => _dark ? const Color(0xFFA9AAB4) : const Color(0xFF6B6D79);

  // ── 控件表面 ──

  /// 瓦片、选药丸的未选中底。
  static Color get surface => _dark ? const Color(0xFF313238) : const Color(0xFFF0F0F3);

  /// 发丝线与默认描边。
  static Color get border => _dark ? const Color(0xFF45464F) : const Color(0xFFDEDEE5);

  // ── 选中态 ──
  static Color get selected => _dark ? const Color(0xFF383E4D) : const Color(0xFFE8EBF3);
  static Color get selectedInk => _dark ? const Color(0xFFC8D1E6) : const Color(0xFF4E5D7E);
  static Color get selectedLine => _dark ? const Color(0xFF8998B8) : const Color(0xFF8A99BA);

  // ── 强调 ──

  /// 滑块已选段。
  static Color get accent => _dark ? const Color(0xFF9BAAC8) : const Color(0xFF7B8BAB);

  /// 完成按钮：深色是浅灰底深字，浅色是深灰底白字，两边都是「实心高对比」。
  static Color get button => _dark ? const Color(0xFFD5D6DC) : const Color(0xFF3B3D46);
  static Color get buttonInk => _dark ? const Color(0xFF292A31) : const Color(0xFFFFFFFF);
  static Color get buttonHover => _dark ? const Color(0xFFE3E4E9) : const Color(0xFF292B33);

  // ── 滑块 ──
  static Color get track => _dark ? const Color(0xFF43454E) : const Color(0xFFDFE1E8);
  static Color get tick => _dark ? const Color(0xFF838897) : const Color(0xFF999EAE);
  static Color get thumb => _dark ? const Color(0xFFB1BFDB) : const Color(0xFF7182A5);

  /// 面板顶部的拖拽把手。
  static Color get grip => _dark ? const Color(0xFF666975) : const Color(0xFFBABDC8);

  /// 面板后面压暗画面的遮罩。
  static Color get scrim => _dark ? const Color(0x2608090E) : const Color(0x0A161820);

  // ── 多色图标：纸页三层次 ──

  /// 前一张纸（压在后面的那张）。
  static Color get iconBack => _dark ? const Color(0xFF77849F) : const Color(0xFFD0D5E1);

  /// 正面的纸。
  static Color get iconPaper => _dark ? const Color(0xFFAEB8CE) : const Color(0xFFB8C2D7);

  /// 卷角。
  static Color get iconTab => _dark ? const Color(0xFFC4BBD2) : const Color(0xFFC6BED6);

  /// 纸上的线和箭头。
  static Color get iconInk => _dark ? const Color(0xFF3A465F) : const Color(0xFF586884);

  static Color get iconSelectedPaper => _dark ? const Color(0xFFC8D1E5) : const Color(0xFFBAC6DF);
  static Color get iconSelectedBack => _dark ? const Color(0xFF91A0C0) : const Color(0xFF94A4C4);
  static Color get iconSelectedTab => _dark ? const Color(0xFFD2CADD) : const Color(0xFFD3CCE2);
  static Color get iconSelectedInk => _dark ? const Color(0xFF465676) : const Color(0xFF4C5D80);

  // ── 尺寸（设计稿的 px 值，两端一致）──

  /// 阅读方式瓦片：一个只有图标的方块，名字挂在下面。
  static const tile = 66.0;
  static const tileRadius = 16.0;
  static const tileGlyph = 30.0;
  static const tileGap = 6.0;
  static const tileStripGap = 9.0;
  static const tileLabel = 12.0;

  /// 选药丸。
  static const choiceHeight = 44.0;
  static const choiceRadius = 13.0;

  /// 顶部提示面板圆角。
  static const sheetRadius = 27.0;

  /// 完成按钮。
  static const buttonRadius = 15.0;

  /// 滑块轨道与手柄。
  static const trackHeight = 4.0;
  static const thumbSize = 16.0;
  static const tickSize = 3.0;
}
