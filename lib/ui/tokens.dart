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

/// 滚动边缘模糊带（scroll edge effect）的几何。
///
/// 规范来自 iOS 26：Apple 把它定义为「滚动内容与固定控件之间的过渡」，
/// 并且作用在滚动方向上的**两端**，不只是顶部。所以这里两端都有，只是
/// **强度不同**——顶部压着状态栏，要够浓；底部是悬浮胶囊，只要一层薄雾。
///
/// 两端为什么不同，是有依据的：参考界面逐像素量过，底部白色胶囊只占距底
/// 36–92dp，胶囊**外侧**的封面、作者名一直到屏幕底边都是清楚的。所以底部
/// 不能铺全宽、不能拖长——那会平白吃掉一行内容。上一版给了 124dp 全宽带，
/// 就是「下面很长、很突兀」的来源。
///
/// 顶部则确实要探到状态栏下沿：参考图里正文从状态栏下面开始就是清晰的，
/// 带子不能再往下，否则会压住「书架」「发现」这些大标题。
class ScrollEdge {
  ScrollEdge._();

  /// 顶部带高：正好到状态栏下沿。
  ///
  /// 不额外铺过渡段——大标题就在状态栏正下方，多出来的每一像素都是拿内容
  /// 换的。带子内部由 [EdgeBlur] 自己从边缘渐到清楚。
  static double topHeight(BuildContext context) => MediaQuery.paddingOf(context).top;

  /// 底部带高：胶囊上沿再往上 20。
  ///
  /// 只盖住胶囊自身高度 + 一点点过渡，不像顶部那样按安全区算。胶囊是浮在
  /// 内容上的，它下面是手势条，没有「内容从系统栏下面钻出来」的问题。
  static double bottomHeight(BuildContext context) => Dock.height + 20;

  /// 顶部模糊强度。状态栏那一条是唯一的过渡，要浓。
  static const topSigma = 12.0;

  /// 底部模糊强度。比顶部小得多——它只是让胶囊「浮起来」的一层薄雾，
  /// 不是一条横贯屏幕的遮罩。数值偏小是刻意的：太大就会把胶囊上方的
  /// 内容糊成一片，读起来像卡顿。
  static const bottomSigma = 6.0;

  /// 顶部底色浓度。
  static const topTint = .45;

  /// 底部底色浓度。比顶部淡，理由同上。
  static const bottomTint = .28;
}
