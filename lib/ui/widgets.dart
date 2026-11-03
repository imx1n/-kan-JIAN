import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/config.dart';
import '../core/models.dart';
import 'icons.dart';
import 'theme.dart';

/// 内置示例作品的封面以 `sample:` 开头，由 [SampleCover] 绘制。
const kSampleCoverPrefix = 'sample:';

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
              placeholder: (_, _) => const ColoredBox(color: Palette.tonal),
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
        color: Palette.tonal,
        padding: const EdgeInsets.all(8),
        alignment: Alignment.center,
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: kSerif, fontSize: 12, color: Palette.secondary),
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
                  fontFamily: kSerif,
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

/// 带透视的立体书：轻微转角 + 书脊高光 + 投影。
class Book3D extends StatelessWidget {
  const Book3D({
    super.key,
    required this.child,
    this.rotateY = 0,
    this.rotateZ = 0,
    this.ribbon = false,
    this.elevation = 1,
  });

  final Widget child;
  final double rotateY;
  final double rotateZ;
  final bool ribbon;
  final double elevation;

  @override
  Widget build(BuildContext context) => Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(rotateY)
          ..rotateZ(rotateZ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(left: Radius.circular(1), right: Radius.circular(3)),
            boxShadow: [
              BoxShadow(color: Color.fromRGBO(35, 61, 57, .19 * elevation), offset: Offset(13 * elevation, 14 * elevation), blurRadius: 16),
              BoxShadow(color: Color.fromRGBO(21, 39, 33, .27 * elevation), offset: const Offset(1, 1), blurRadius: 2),
            ],
          ),
          child: Stack(clipBehavior: Clip.none, children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    gradient: const LinearGradient(
                      colors: [Color(0x33152721), Color(0x00152721), Color(0x2BFFFFFF), Color(0x00FFFFFF)],
                      stops: [0, .02, .04, .06],
                    ),
                  ),
                ),
              ),
            ),
            if (ribbon)
              Positioned(
                right: 15,
                top: -1,
                child: ClipPath(
                  clipper: _RibbonClipper(),
                  child: Container(width: 12, height: 29, color: Palette.accent),
                ),
              ),
          ]),
        ),
      );
}

class _RibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width / 2, s.height * .8)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// 品牌标：书本轮廓 + 锈红书签。
class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(size: const Size(18, 25), painter: _BrandPainter());
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Palette.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final r = RRect.fromRectAndCorners(
      Rect.fromLTWH(.8, .8, size.width - 1.6, size.height - 1.6),
      topRight: const Radius.circular(6),
    );
    canvas.drawRRect(r, stroke);
    canvas.drawLine(const Offset(4.8, .8), Offset(4.8, size.height - .8), stroke..strokeWidth = 1.5);
    final ribbon = Path()
      ..moveTo(8.8, 0)
      ..lineTo(12.8, 0)
      ..lineTo(12.8, 13)
      ..lineTo(10.8, 10)
      ..lineTo(8.8, 13)
      ..close();
    canvas.drawPath(ribbon, Paint()..color = Palette.accent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ToolButton extends StatelessWidget {
  const ToolButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.color,
    this.background,
    this.size = 44,
    this.iconSize = 24,
  });

  final String icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: background ?? Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Center(child: AppIcon(icon, size: iconSize, color: color)),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 深墨主按钮：左文字右箭头。
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onTap, this.height = 50, this.radius = 11});

  final String label;
  final VoidCallback? onTap;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
        color: onTap == null ? Palette.secondary : Palette.ink,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: SizedBox(
            height: height,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                Expanded(
                  child: Text(label,
                      style: const TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 1, fontWeight: FontWeight.w500)),
                ),
                const AppIcon('arrow', size: 22, color: Colors.white, stroke: 1.4),
              ]),
            ),
          ),
        ),
      );
}

/// 浅底分段选择（行距/字重/页边距/榜单周期等）。
class Segmented extends StatelessWidget {
  const Segmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.background = const Color(0xFFE9EEE5),
    this.active = const Color(0xFFFAFBF8),
    this.ink = Palette.ink,
    this.muted = const Color(0xFF586852),
    this.height = 44,
  });

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final Color background;
  final Color active;
  final Color ink;
  final Color muted;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(11)),
        child: Row(children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? active : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: i == selected ? const [BoxShadow(color: Color(0x1029422A), blurRadius: 4, offset: Offset(0, 1))] : null,
                  ),
                  child: Text(
                    options[i],
                    style: TextStyle(
                      fontSize: 13,
                      color: i == selected ? ink : muted,
                      fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.color = Palette.secondary});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2, color: color)),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry, this.dark = false});

  final String message;
  final VoidCallback onRetry;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Palette.mangaInk : Palette.ink;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: fg, fontSize: 14, height: 1.6)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: AppIcon('refresh', size: 16, color: fg),
            label: Text('重试', style: TextStyle(color: fg)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: fg.withValues(alpha: .4))),
          ),
        ]),
      ),
    );
  }
}

/// 单行输入对话框。控制器由对话框自己持有，避免退场动画期间被提前释放。
/// 返回输入内容；点 [clearLabel] 返回空串；取消返回 null。
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String? help,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  String? clearLabel,
  Color? background,
  Color? ink,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _TextPrompt(
        title: title,
        initial: initial,
        hint: hint,
        help: help,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        clearLabel: clearLabel,
        background: background,
        ink: ink,
      ),
    );

class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.initial,
    required this.confirmLabel,
    required this.cancelLabel,
    this.hint,
    this.help,
    this.clearLabel,
    this.background,
    this.ink,
  });

  final String title;
  final String initial;
  final String? hint;
  final String? help;
  final String confirmLabel;
  final String cancelLabel;
  final String? clearLabel;
  final Color? background;
  final Color? ink;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  late final _input = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: widget.background,
        title: Text(widget.title, style: TextStyle(color: widget.ink, fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            controller: _input,
            autofocus: true,
            style: TextStyle(color: widget.ink),
            decoration: InputDecoration(hintText: widget.hint),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
          if (widget.help != null) ...[
            const SizedBox(height: 12),
            Text(widget.help!, style: const TextStyle(fontSize: 12, color: Palette.secondary, height: 1.5)),
          ],
        ]),
        actions: [
          if (widget.clearLabel != null)
            TextButton(onPressed: () => Navigator.pop(context, ''), child: Text(widget.clearLabel!))
          else
            TextButton(onPressed: () => Navigator.pop(context), child: Text(widget.cancelLabel)),
          TextButton(onPressed: () => Navigator.pop(context, _input.text), child: Text(widget.confirmLabel)),
        ],
      );
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

/// 横向滚动的筛选胶囊。选中项为深墨实底。
class FilterChips extends StatelessWidget {
  const FilterChips({super.key, required this.items, required this.selected, required this.onSelect, this.padding});

  /// (标签, 计数或 null, 是否带更新圆点)
  final List<(String, int?, bool)> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final (label, count, dot) = items[i];
            final on = i == selected;
            return Semantics(
              selected: on,
              button: true,
              child: Material(
                color: on ? Palette.ink : Colors.transparent,
                shape: StadiumBorder(side: on ? BorderSide.none : const BorderSide(color: Palette.line)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSelect(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (dot) ...[
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: on ? const Color(0xFFE7B3A3) : Palette.accent, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                      ],
                      Text(label, style: TextStyle(fontSize: 13, color: on ? Palette.onInk : Palette.ink2, fontWeight: on ? FontWeight.w500 : FontWeight.w400)),
                      if (count != null) ...[
                        const SizedBox(width: 6),
                        Text('$count', style: TextStyle(fontSize: 12, color: on ? const Color(0xFFC9D3D1) : Palette.ink3, fontWeight: FontWeight.w500)),
                      ],
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.count, this.trailing, this.padding});

  final String title;
  final String? count;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(20, 22, 12, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(count!, style: const TextStyle(fontSize: 12, color: Palette.ink3)),
          ],
          const Spacer(),
          ?trailing,
        ]),
      );
}

/// 区块右侧的文字按钮，例如「全部 ›」「最近阅读 ▾」。
class HeaderAction extends StatelessWidget {
  const HeaderAction({super.key, required this.label, required this.onTap, this.icon = 'right'});

  final String label;
  final VoidCallback onTap;
  final String icon;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: Palette.ink2, minimumSize: const Size(48, 40), padding: const EdgeInsets.symmetric(horizontal: 8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 2),
          AppIcon(icon, size: 14, color: Palette.ink2),
        ]),
      );
}

class NewBadge extends StatelessWidget {
  const NewBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(color: Palette.accentSoft, borderRadius: BorderRadius.circular(12)),
        child: Center(widthFactor: 1, child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Palette.accent))),
      );
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.background = Palette.tonal, this.color = Palette.ink2, this.bold = false});

  final String text;
  final Color background;
  final Color color;
  final bool bold;

  @override
  // 宽度跟随文字；不能用 alignment，否则在 Wrap/Stack 里会被撑满整行。
  Widget build(BuildContext context) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
        child: Center(widthFactor: 1, child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: bold ? FontWeight.w500 : FontWeight.w400))),
      );
}

/// 3px 圆角进度条；阅读进度统一用锈红。
class ProgressLine extends StatelessWidget {
  const ProgressLine(this.value, {super.key, this.color = Palette.accent, this.background = Palette.track, this.height = 3});

  final double value;
  final Color color;
  final Color background;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: height, color: color, backgroundColor: background),
      );
}

/// 骨架占位：布局与真实内容一致，带流光；系统关闭动画时静止。
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, required this.height, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.disableAnimationsOf(context) ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + 3 * _c.value - 1, 0),
              end: Alignment(1 + 3 * _c.value - 1, 0),
              colors: const [Palette.tonal, Color(0xFFEFF4F0), Palette.tonal],
            ),
          ),
        ),
      );
}

/// 网络异常面板：说明 + 诊断（数据源、代理、最近一次失败）+ 重试 / 代理设置。
class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, required this.onRetry, this.onProxy, this.host, this.proxy, this.failedAt});

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onProxy;
  final String? host;
  final String? proxy;
  final DateTime? failedAt;

  @override
  Widget build(BuildContext context) {
    Widget diag(String k, String v, {bool bad = false}) => Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Palette.line))),
          child: Row(children: [
            Text(k, style: const TextStyle(fontSize: 12, color: Palette.ink3)),
            const SizedBox(width: 12),
            Expanded(child: Text(v, textAlign: TextAlign.right, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: bad ? Palette.accent : Palette.ink))),
          ]),
        );
    final at = failedAt;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      decoration: BoxDecoration(color: Palette.bar, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Palette.accentSoft, shape: BoxShape.circle),
          child: const AppIcon('wifiOff', size: 22, color: Palette.accent),
        ),
        const SizedBox(height: 14),
        const Text('连不上数据源', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('$message。书架和已缓存的页面仍可离线查看。', style: const TextStyle(fontSize: 13, height: 1.7, color: Palette.ink2)),
        const SizedBox(height: 14),
        const Divider(height: 1, color: Palette.line),
        if (host != null) diag('数据源', host!),
        diag('网络代理', (proxy ?? '').isEmpty ? '直连' : proxy!),
        if (at != null) diag('最近一次', '失败 · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}', bad: true),
        const SizedBox(height: 16),
        Row(children: [
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: Palette.ink, minimumSize: const Size(0, 44)),
            icon: const AppIcon('refresh', size: 18, color: Palette.onInk),
            label: const Text('重试'),
          ),
          if (onProxy != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onProxy, style: TextButton.styleFrom(foregroundColor: Palette.ink, minimumSize: const Size(0, 44)), child: const Text('代理设置')),
          ],
        ]),
      ]),
    );
  }
}

/// 列表滚到底部附近时触发 [onEnd]。
bool onScrollEnd(ScrollNotification n, VoidCallback onEnd) {
  if (n.metrics.pixels > n.metrics.maxScrollExtent - 600) onEnd();
  return false;
}
