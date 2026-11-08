import 'dart:ui' show Offset;

import 'reading_mode.dart';

/// 点按后要执行的动作。
enum ReaderAction { menu, forward, backward }

/// 分区类型。命名照搬 Mihon 的 `NavigationRegion`。
enum _RegionType { menu, prev, next, left, right }

/// 一个矩形分区，坐标是 0–1 的归一化值，和屏幕尺寸无关。
class _Zone {
  const _Zone(this.left, this.top, this.right, this.bottom, this.type);

  final double left;
  final double top;
  final double right;
  final double bottom;
  final _RegionType type;

  bool hit(Offset p) => p.dx >= left && p.dx <= right && p.dy >= top && p.dy <= bottom;

  /// 镜像：横向反转时左右对调，纵向反转时上下对调。
  _Zone mirror({required bool horizontal, required bool vertical}) => _Zone(
        horizontal ? 1 - right : left,
        vertical ? 1 - bottom : top,
        horizontal ? 1 - left : right,
        vertical ? 1 - top : bottom,
        type,
      );
}

/// 点击分区引擎，照搬 Mihon 的 `ViewerNavigation`（Apache-2.0）。
///
/// 每种分区方案只是一组归一化矩形；命中后由 [_actionOf] 把
/// 「左边 / 右边」翻译成「上一页 / 下一页」，反向阅读时两者互换。
/// 这样新增一种分区方案只要加一组矩形，不需要动翻页逻辑。
class ReaderNavigation {
  const ReaderNavigation({
    required this.area,
    required this.mode,
    this.invertHorizontal = false,
    this.invertVertical = false,
  });

  /// 分区方案：0 关闭，1 自适应，2 左右，3 L 形，4 边缘，5 Kindle 式。
  final int area;
  final ReadingMode mode;
  final bool invertHorizontal;
  final bool invertVertical;

  bool get _reversed => mode.reversed;

  /// 自适应：竖向阅读（上下翻页 / 条漫）用 L 形，横向用左右。
  List<_Zone> get _zones {
    final preset = area == 1 ? (mode.isVertical ? 3 : 2) : area;
    final zones = switch (preset) {
      // 关闭：全部区域都是「切换控件」。
      0 => const <_Zone>[],
      // 左右三分：左 1/3 上一页，右 1/3 下一页，中间切换控件。
      2 => const [
          _Zone(0, 0, 1 / 3, 1, _RegionType.left),
          _Zone(2 / 3, 0, 1, 1, _RegionType.right),
        ],
      // 上下三分：上 1/3 上一页，下 1/3 下一页，中间整条都是切换控件。
      //
      // 这里原本是「L 形」——中间只有正中一个 1/3×1/3 的小方块是切换控件，
      // 左右两条是翻页。实际用下来几乎没人能点中那个方块，点偏一点就翻页，
      // 体感就是「点好几下控件才出来」。中间带整宽之后目标大了 3 倍，
      // 而且「上下翻页、中间切控件」只要说一次就能记住。
      3 => const [
          _Zone(0, 0, 1, 1 / 3, _RegionType.prev),
          _Zone(0, 2 / 3, 1, 1, _RegionType.next),
        ],
      // 边缘：两侧 1/3 都是下一页，中间一条底部是上一页（单手持机时拇指够得着）。
      4 => const [
          _Zone(0, 0, 1 / 3, 1, _RegionType.next),
          _Zone(1 / 3, 2 / 3, 2 / 3, 1, _RegionType.prev),
          _Zone(2 / 3, 0, 1, 1, _RegionType.next),
        ],
      // Kindle 式：左侧 1/3 上一页，其余 2/3 下一页，顶部一条切换控件。
      5 => const [
          _Zone(1 / 3, 1 / 3, 1, 1, _RegionType.next),
          _Zone(0, 1 / 3, 1 / 3, 1, _RegionType.prev),
        ],
      _ => const <_Zone>[],
    };
    if (!invertHorizontal && !invertVertical) return zones;
    return [for (final z in zones) z.mirror(horizontal: invertHorizontal, vertical: invertVertical)];
  }

  /// 命中 [p]（0–1 归一化坐标）对应的动作；没有命中任何分区就是切换控件。
  ReaderAction actionAt(Offset p) {
    for (final z in _zones) {
      if (z.hit(p)) return _actionOf(z.type);
    }
    return ReaderAction.menu;
  }

  /// 「左 / 右」在反向阅读时互换：从右向左时右边是上一页。
  ReaderAction _actionOf(_RegionType type) => switch (type) {
        _RegionType.menu => ReaderAction.menu,
        _RegionType.next => ReaderAction.forward,
        _RegionType.prev => ReaderAction.backward,
        _RegionType.right => _reversed ? ReaderAction.backward : ReaderAction.forward,
        _RegionType.left => _reversed ? ReaderAction.forward : ReaderAction.backward,
      };
}
