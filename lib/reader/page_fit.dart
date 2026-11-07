import 'package:flutter/painting.dart';

import 'reading_mode.dart';

/// 图片怎么放进这一页。
///
/// 之前只有两种行为写死在代码里：条漫一律 `fitWidth`，其余一律 `contain`。
/// 结果纵向单页阅读时，一张 3:5 的图放在 9:20 的屏幕上，上下会各留一大条
/// 背板色——看上去就是「上下都是白边」。这里把适配方式做成可选项，
/// 和 Mihon 的 `PageScaleType`（FIT_SCREEN / FIT_WIDTH / FIT_HEIGHT /
/// ORIGINAL_SIZE）对齐。
enum PageFit {
  /// 自动：纵向阅读（上下翻页、条漫）用宽度铺满，横向翻页用整页适应。
  auto('自动'),

  /// 宽度铺满，高度按原比例——纵向阅读没有白边，长了会超出屏幕。
  width('适应宽度'),

  /// 高度铺满，宽度按原比例。
  height('适应高度'),

  /// 整页放进屏幕，比例不合适时上下或左右留边。
  screen('适应屏幕'),

  /// 原始像素，不缩放（适合图本身和屏幕差不多大时）。
  original('原始尺寸');

  const PageFit(this.label);

  final String label;

  /// 设置项的存储值。新选项只能往后加，不能改已有数字。
  static PageFit fromValue(int v) => switch (v) {
        1 => PageFit.width,
        2 => PageFit.height,
        3 => PageFit.screen,
        4 => PageFit.original,
        _ => PageFit.auto,
      };

  int get value => index;

  /// 这一页实际该用的适配方式。
  ///
  /// [continuous] 是条漫（上下连续滚动）：它本来就没有「一整页」的概念，
  /// 一律按宽度铺满，否则页面之间会出现横向留白。真正要区分的是纵向单页。
  PageFit resolve({required ReadingMode mode}) => switch (this) {
        PageFit.auto => mode.continuous || mode.isVertical ? PageFit.width : PageFit.screen,
        _ => this,
      };

  /// 对应的 [BoxFit]。
  ///
  /// 原始尺寸用 `none`：比屏幕小的图保持原大，不做任何放大。
  BoxFit get boxFit => switch (this) {
        PageFit.width => BoxFit.fitWidth,
        PageFit.height => BoxFit.fitHeight,
        PageFit.screen || PageFit.auto => BoxFit.contain,
        PageFit.original => BoxFit.none,
      };

  /// 是否按宽度撑满。渲染时要显式给宽度，图片才会先占住位置再淡入，
  /// 否则加载完成的那一下会把整列内容顶一下。
  bool get fillsWidth => this == PageFit.width;
}
