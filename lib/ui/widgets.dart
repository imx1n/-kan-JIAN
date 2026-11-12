import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../core/config.dart';
import '../core/models.dart';

/// 内置示例作品的封面以 `sample:` 开头，由 [SampleCover] 绘制。
const kSampleCoverPrefix = 'sample:';

/// 全部封面的统一宽高比（高 / 宽）。
///
/// 以前每个用到封面的地方各写一个尺寸：书架续读卡片 74×103（1.395）、
/// 藏书网格 3:4（1.333）、详情 112×156（1.393）、发现 104×140（1.346）、
/// 搜索 64×86（1.344）。`BoxFit.cover` 是按容器比例裁切的，容器比例不同，
/// 同一本书裁掉的量就不同——同一屏里并排看就是「大小不一、比例不一」。
///
/// 这里只留一个比例，所有位置的高度都从宽度算（[coverHeightFor]），
/// 尺寸大小仍然可以按层级不同（续读卡片小、详情页大），但形状永远一致。
///
/// 选 3:4 而不是源站的 328×422（1.287）：3:4 是竖版封面最常见的比例，
/// 现有代码里已经是最多处采用的值；源站图放进 3:4 只裁掉 3.5% 的上下边。
const double kCoverAspect = 4 / 3;

/// 按统一比例从宽度算高度。
double coverHeightFor(double width) => width * kCoverAspect;

/// 封面加载中和没有封面时的底色、书名颜色，随主题深浅变化。
bool _darkTheme(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
Color _coverTonal(BuildContext context) => _darkTheme(context) ? const Color(0xFF26272B) : const Color(0xFFEFEFF1);
Color _coverInk(BuildContext context) => _darkTheme(context) ? const Color(0xFF9C9DA5) : const Color(0xFF71727A);

class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.title = '',
    this.radius = 2,
  });

  final String url;
  final double width;
  final double height;
  final String title;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (url.startsWith(kSampleCoverPrefix)) {
      child = SampleCover(title: url.substring(kSampleCoverPrefix.length));
    } else {
      final fallback = _TitleCover(title: title);
      child = url.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: url,
              httpHeaders: AppConfig.imageHeaders,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 180),
              memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
              placeholder: (context, _) => ColoredBox(color: _coverTonal(context)),
              errorWidget: (_, _, _) => fallback,
            );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: width, height: height, child: child),
    );
  }
}

class _TitleCover extends StatelessWidget {
  const _TitleCover({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Container(
        color: _coverTonal(context),
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontFamily: 'serif', fontSize: 12, color: _coverInk(context)),
        ),
      );
}

/// 示例轻小说的排印封面：雨后天色 + 竖排书名。
class SampleCover extends StatelessWidget {
  const SampleCover({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final s = c.maxWidth / 151;
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF6F8FA6), Color(0xFFB9CBD0), Color(0xFFE9E4D4)],
              stops: [0, .55, 1],
            ),
          ),
          child: Stack(children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: c.maxHeight * .22,
              child: Container(height: 1.2 * s, color: const Color(0x80FFFFFF)),
            ),
            Positioned(
              right: 16 * s,
              top: 18 * s,
              child: Text(
                title.split('').join('\n'),
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 20 * s,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  shadows: const [Shadow(color: Color(0x40263C40), blurRadius: 6)],
                ),
              ),
            ),
            Positioned(
              left: 14 * s,
              bottom: 14 * s,
              child: Text(
                '示例短篇',
                style: TextStyle(fontSize: 10 * s, color: const Color(0xFF4F6364), letterSpacing: 2 * s),
              ),
            ),
          ]),
        );
      });
}

/// 简单的分页加载器：列表 + 加载中 + 错误 + 是否还有更多。
class Pager<T> extends ChangeNotifier {
  Pager(this._fetch);

  final Future<PageResult<T>> Function(int offset) _fetch;

  final items = <T>[];
  bool loading = false;
  String? error;
  bool hasMore = true;
  int total = 0;
  int _generation = 0;

  Future<void> loadMore() async {
    if (loading || !hasMore) return;
    loading = true;
    error = null;
    notifyListeners();
    final gen = _generation;
    try {
      final page = await _fetch(items.length);
      if (gen != _generation) return;
      items.addAll(page.list);
      total = page.total;
      hasMore = page.list.isNotEmpty && page.hasMore;
    } catch (e) {
      if (gen != _generation) return;
      error = e.toString();
    } finally {
      if (gen == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> refresh() {
    _generation++;
    items.clear();
    loading = false;
    error = null;
    hasMore = true;
    return loadMore();
  }
}

/// 列表滚到底部附近时触发 [onEnd]。
bool onScrollEnd(ScrollNotification n, VoidCallback onEnd) {
  if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) onEnd();
  return false;
}

/// 把第 [index] 条章节滚到视口里。列表是懒构建的，远处的行还不存在，
/// 所以先按固定行高 [rowExtent] 从第一行的位置估算并跳过去，再对齐到真实的行。
Future<void> revealChapterRow({required GlobalKey firstKey, required GlobalKey targetKey, required int index, required double rowExtent}) async {
  final built = targetKey.currentContext;
  if (built != null) {
    await Scrollable.ensureVisible(built, alignment: .35, duration: const Duration(milliseconds: 250));
    return;
  }
  final first = firstKey.currentContext;
  final box = first?.findRenderObject();
  if (first == null || box is! RenderBox || !box.attached) return;
  final position = Scrollable.of(first).position;
  final firstOffset = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
  final to = (firstOffset + index * rowExtent - position.viewportDimension * .35).clamp(position.minScrollExtent, position.maxScrollExtent);
  position.jumpTo(to);
  await WidgetsBinding.instance.endOfFrame;
  final target = targetKey.currentContext;
  if (target != null && target.mounted) await Scrollable.ensureVisible(target, alignment: .35, duration: const Duration(milliseconds: 200));
}
