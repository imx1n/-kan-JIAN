/// 阅读方式的划分，照搬 Mihon 的 `ReadingMode`（Apache-2.0）。
///
/// 它把阅读方式拆成三个互相独立的开关——翻页方向是否反向、翻页轴是横是纵、
/// 是否连续滚动——所有排版差异都由这三个开关推导，不再为每种模式写一套逻辑。
enum ReadingMode {
  /// 单页横向，从左向右。
  leftToRight(reversed: false, isVertical: false, continuous: false),

  /// 单页横向，从右向左（日漫）。
  rightToLeft(reversed: true, isVertical: false, continuous: false),

  /// 单页纵向，从上向下。
  vertical(reversed: false, isVertical: true, continuous: false),

  /// 单页纵向，从下向上。
  verticalReversed(reversed: true, isVertical: true, continuous: false),

  /// 条漫，图片之间不留缝。
  webtoon(reversed: false, isVertical: true, continuous: true, gap: false),

  /// 条漫，图片之间留白（Mihon 的 CONTINUOUS_VERTICAL）。
  continuousVertical(reversed: false, isVertical: true, continuous: true, gap: true);

  const ReadingMode({required this.reversed, required this.isVertical, required this.continuous, this.gap = false});

  /// 阅读方向反过来：横向从右向左，纵向从下向上。
  final bool reversed;

  /// 翻页轴是纵向（上下翻页或连续滚动）。
  final bool isVertical;

  /// 连续滚动（条漫）。为 false 时是一页一屏的 `PageView`。
  final bool continuous;

  /// 连续滚动时图片之间是否留缝。
  final bool gap;

  /// 是否按「一条」纵向排布（页面首尾相接，不再一页一屏）。
  ///
  /// 上下翻页的两种模式（从上向下 / 从下向上）也归到这里：一页一屏时，
  /// 一张 3:4 的图放在 9:20 的屏幕上，按宽度铺满后上下会各空出一大条背板色，
  /// 两张图之间断成一段一段。改成首尾相接之后，纵向阅读是连贯的一条，
  /// 和条漫的观感一致，只是方向可以反过来。
  bool get stacked => continuous || isVertical;

  /// 偏好值 → 模式。数值沿用仓库里已有的 0–4，5 是本轮新增。
  static ReadingMode fromPreference(int v) => switch (v) {
        1 => rightToLeft,
        2 => vertical,
        3 => verticalReversed,
        4 => webtoon,
        5 => continuousVertical,
        _ => leftToRight,
      };

  int get preference => index;

  /// 面板和选择器里显示的名字。
  String get label => switch (this) {
        leftToRight => '单页 · 从左向右',
        rightToLeft => '单页 · 从右向左',
        vertical => '单页 · 从上向下',
        verticalReversed => '单页 · 从下向上',
        webtoon => '条漫 · 无缝',
        continuousVertical => '条漫 · 留白',
      };

  /// 设置面板瓦片上的短名。瓦片本身很小（100 宽），全名会折成三行把图标挤掉，
  /// 「单页 / 条漫」这层信息瓦片图标自己已经表达了，这里只留方向。
  String get shortLabel => switch (this) {
        leftToRight => '从左向右',
        rightToLeft => '从右向左',
        vertical => '从上向下',
        verticalReversed => '从下向上',
        webtoon => '无缝滚动',
        continuousVertical => '留白滚动',
      };
}
