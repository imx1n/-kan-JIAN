import 'package:flutter/widgets.dart';

/// 全局间距刻度。
///
/// 之前每个页面各写各的 `EdgeInsets`，左边距在 16 / 20 / 36 之间跳，
/// 区块上下留白在 6 / 10 / 12 / 22 / 26 之间随机，滚动到底部时又会突然
/// 撞上一大块空白——看上去就是「没有视觉居中」。这里只留一档刻度，
/// 页面只用 [page] 作为唯一外边距，纵向节奏只用下面几个命名值。
class Space {
  Space._();

  static const x1 = 4.0;
  static const x2 = 8.0;
  static const x3 = 12.0;
  static const x4 = 16.0;
  static const x5 = 20.0;
  static const x6 = 28.0;
  static const x7 = 36.0;

  /// 全 App 唯一的页面左右外边距。标题、筛选、列表、网格左边缘都落在这一条线。
  static const page = x5;

  /// 大标题下沿到第一个内容块。
  static const afterTitle = x2;

  /// 区块标题的上沿留白（上一个区块的内容到此结束）。
  static const beforeSection = x6;

  /// 区块标题下沿到内容。
  static const afterSection = x3;

  /// 列表中每一行与上一行的最小间隔，也是相邻卡片的间隔。
  static const rowGap = x3;
}

/// 悬浮标签栏的几何。
///
/// 关键点：标签栏必须整体抬到系统手势区（安卓小白条 / iOS Home 指示条）
/// 之上，不能像以前那样 `bottom: inset - 6` 直接压进去——那样手势条会盖住
/// 胶囊底部和「搜索」球。
class Dock {
  Dock._();

  static const height = 64.0;

  /// 胶囊与手势条之间留的距离。
  static const gap = Space.x2;

  /// 系统手势区高度。
  static double inset(BuildContext context) => MediaQuery.paddingOf(context).bottom;

  /// 标签栏底边距屏幕底边的距离。
  static double bottom(BuildContext context) => inset(context) + gap;

  /// 页面内容需要给标签栏让出的高度：标签栏 + 它下面的留白 + 一点呼吸空间。
  static double clearance(BuildContext context) => height + bottom(context) + Space.x4;
}
