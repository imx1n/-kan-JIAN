import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/store.dart';
import '../ui/icons.dart';

/// iOS 26 设计稿的色板：近白实底承载内容，暖棕为唯一强调色；阅读器为深色。
class IosColors {
  IosColors._();

  static const bg = Color(0xFFF9F9FB);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF222328);
  static const muted = Color(0xFF62636B);
  static const faint = Color(0xFFE9E9EE);
  static const line = Color(0xFFE2E2E8);
  static const accent = Color(0xFF914638);
  static const accentSoft = Color(0xFFF3E9E5);
  static const tab = Color(0xFF5C5D65);

  static const dBg = Color(0xFF15161A);
  static const dSurface = Color(0xFF25262C);
  static const dInk = Color(0xFFF5F5F7);
  static const dMuted = Color(0xFFB5B5C0);
  static const dLine = Color(0xFF45454D);
  static const dFaint = Color(0xFF35363E);
  static const dAccent = Color(0xFFF1B4A4);
}

/// 小说正文用系统宋体（iOS 自带 Songti SC），其他平台回退到 serif。
const kIosSerif = TextStyle(fontFamily: 'Songti SC', fontFamilyFallback: ['STSong', 'serif']);

/// 「减少透明度」：开启后玻璃控件改为实底。设置变化时依赖它的控件会重建。
class GlassScope extends InheritedNotifier<ValueNotifier<bool>> {
  const GlassScope({super.key, required ValueNotifier<bool> reduce, required super.child}) : super(notifier: reduce);

  static final reduce = ValueNotifier<bool>(false);

  static bool reduced(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<GlassScope>();
    return (scope?.notifier?.value ?? false) || MediaQuery.highContrastOf(context);
  }

  static void set(bool v) {
    ReaderPrefs.instance.reduceTransparency = v;
    reduce.value = v;
  }
}

/// 玻璃材质：模糊 + 半透明 + 细亮边 + 克制阴影。只用于导航、工具和暂态面板，内容层保持实底。
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 22, this.dark = false, this.padding, this.shadow = true});

  final Widget child;
  final double radius;
  final bool dark;
  final EdgeInsetsGeometry? padding;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final reduce = GlassScope.reduced(context);
    final r = BorderRadius.circular(radius);
    final fill = dark
        ? (reduce ? IosColors.dSurface : const Color(0xB3292A31))
        : (reduce ? const Color(0xFFF2F2F6) : const Color(0xB0F8F8FB));
    Widget body = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: r,
        border: Border.all(color: dark ? const Color(0x2EFFFFFF) : const Color(0x8CFFFFFF), width: .8),
      ),
      child: child,
    );
    if (!reduce) body = BackdropFilter(filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22), child: body);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: shadow ? [BoxShadow(color: dark ? const Color(0x59000000) : const Color(0x1F1A1A28), blurRadius: 18, offset: const Offset(0, 6))] : null,
      ),
      child: ClipRRect(borderRadius: r, child: body),
    );
  }
}

/// 按下时轻微缩放、变淡，替代 Material 水波纹。
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.onLongPress, this.haptic = false, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap != null && v != _down) setState(() => _down = v);
  }

  @override
  // 有自己的读屏标签时，不再把里面的文字重复读一遍。
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.semanticLabel,
        excludeSemantics: widget.semanticLabel != null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _set(true),
          onTapUp: (_) => _set(false),
          onTapCancel: () => _set(false),
          onLongPress: widget.onLongPress,
          onTap: widget.onTap == null
              ? null
              : () {
                  if (widget.haptic) HapticFeedback.selectionClick();
                  widget.onTap!();
                },
          child: AnimatedScale(
            scale: _down ? .97 : 1,
            duration: const Duration(milliseconds: 100),
            child: AnimatedOpacity(opacity: _down ? .7 : (widget.onTap == null ? .4 : 1), duration: const Duration(milliseconds: 100), child: widget.child),
          ),
        ),
      );
}

/// 44pt 圆形玻璃按钮（返回、更多、关闭等）。
class GlassButton extends StatelessWidget {
  const GlassButton({super.key, required this.icon, required this.onTap, required this.label, this.dark = false, this.size = 44, this.iconSize = 21, this.color});

  final String icon;
  final VoidCallback? onTap;
  final String label;
  final bool dark;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: Glass(
          radius: size / 2,
          dark: dark,
          child: SizedBox.square(
            dimension: size,
            child: Center(child: AppIcon(icon, size: iconSize, color: color ?? (dark ? IosColors.dInk : IosColors.ink), stroke: 1.8)),
          ),
        ),
      );
}

/// 大标题行：34pt 粗体，右侧放玻璃按钮。
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.title, {super.key, this.trailing = const []});

  final String title;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 16, 6),
        child: SizedBox(
          height: 54,
          child: Row(children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(title, style: const TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -.4, color: IosColors.ink)),
              ),
            ),
            for (final t in trailing) ...[const SizedBox(width: 8), t],
          ]),
        ),
      );
}

/// 系统风格的分段控件。
class IosSegmented extends StatelessWidget {
  const IosSegmented({super.key, required this.options, required this.selected, required this.onChanged, this.dark = false, this.counts});

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool dark;
  final List<int?>? counts;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<int>(
          groupValue: selected,
          backgroundColor: dark ? IosColors.dFaint : IosColors.faint,
          thumbColor: dark ? const Color(0xFF55565E) : IosColors.surface,
          padding: const EdgeInsets.all(3),
          onValueChanged: (v) {
            if (v == null) return;
            HapticFeedback.selectionClick();
            onChanged(v);
          },
          children: {
            for (var i = 0; i < options.length; i++)
              i: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: options[i]),
                    if (counts != null && counts![i] != null)
                      TextSpan(text: '  ${counts![i]}', style: TextStyle(fontWeight: FontWeight.w400, color: dark ? IosColors.dMuted : IosColors.muted)),
                  ]),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400,
                    color: dark ? IosColors.dInk : IosColors.ink,
                  ),
                ),
              ),
          },
        ),
      );
}

/// 横向文字筛选：选中项为浅灰胶囊。
class TextChips extends StatelessWidget {
  const TextChips({super.key, required this.items, required this.selected, required this.onSelect});

  /// (标签, 计数, 是否带更新圆点)
  final List<(String, int?, bool)> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 4),
          itemBuilder: (context, i) {
            final (label, count, dot) = items[i];
            final on = i == selected;
            return Pressable(
              haptic: true,
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(color: on ? IosColors.faint : Colors.transparent, borderRadius: BorderRadius.circular(18)),
                child: Center(
                  widthFactor: 1,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (dot) ...[
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: IosColors.accent, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                    ],
                    Text(label, style: TextStyle(fontSize: 15, color: on ? IosColors.ink : IosColors.muted, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
                    if (count != null) ...[
                      const SizedBox(width: 5),
                      Text('$count', style: TextStyle(fontSize: 13, color: on ? IosColors.ink : IosColors.muted)),
                    ],
                  ]),
                ),
              ),
            );
          },
        ),
      );
}

/// 区块标题：20pt 粗体 + 计数 + 右侧暖棕文字按钮。
class IosSection extends StatelessWidget {
  const IosSection(this.title, {super.key, this.count, this.action, this.onAction, this.actionIcon = 'right', this.note});

  final String title;
  final String? count;
  final String? action;
  final VoidCallback? onAction;
  final String actionIcon;
  final String? note;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 16, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: IosColors.ink)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(count!, style: const TextStyle(fontSize: 15, color: IosColors.muted)),
          ],
          const Spacer(),
          if (note != null) Text(note!, style: const TextStyle(fontSize: 13, color: IosColors.muted)),
          if (action != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(action!, style: const TextStyle(fontSize: 15, color: IosColors.accent)),
                  const SizedBox(width: 2),
                  AppIcon(actionIcon, size: 14, color: IosColors.accent, stroke: 2),
                ]),
              ),
            ),
        ]),
      );
}

/// 圆角分组列表（设置页）。
class InsetGroup extends StatelessWidget {
  const InsetGroup({super.key, this.title, required this.children, this.footer});

  final String? title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 22, 20, 7),
            child: Text(title!, style: const TextStyle(fontSize: 13, color: IosColors.muted)),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: IosColors.surface, borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Padding(padding: EdgeInsets.only(left: 52), child: Divider(height: 1, thickness: .5, color: IosColors.line)),
              children[i],
            ],
          ]),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 7, 32, 0),
            child: Text(footer!, style: const TextStyle(fontSize: 13, height: 1.45, color: IosColors.muted)),
          ),
      ]);
}

class IosRow extends StatelessWidget {
  const IosRow({super.key, this.icon, required this.title, this.subtitle, this.value, this.valueWidget, this.onTap, this.chevron = true, this.destructive = false});

  final String? icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? valueWidget;
  final VoidCallback? onTap;
  final bool chevron;
  final bool destructive;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            child: Row(children: [
              if (icon != null) ...[AppIcon(icon!, size: 22, color: IosColors.muted, stroke: 1.6), const SizedBox(width: 14)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: TextStyle(fontSize: 17, color: destructive ? IosColors.accent : IosColors.ink)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: IosColors.muted)),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              ?valueWidget,
              if (value != null) Text(value!, style: const TextStyle(fontSize: 15, color: IosColors.muted)),
              if (chevron && onTap != null) ...[const SizedBox(width: 6), const AppIcon('right', size: 14, color: IosColors.muted, stroke: 2)],
            ]),
          ),
        ),
      );
}

/// 「内容不可用」：图标、标题、说明和操作。
class Unavailable extends StatelessWidget {
  const Unavailable({super.key, required this.icon, required this.title, required this.message, this.actions = const [], this.dark = false, this.iconBackground});

  final String icon;
  final String title;
  final String message;
  final List<Widget> actions;
  final bool dark;
  final Color? iconBackground;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: iconBackground, borderRadius: BorderRadius.circular(18)),
            child: Center(child: AppIcon(icon, size: iconBackground == null ? 56 : 28, color: dark ? IosColors.dMuted : (iconBackground == null ? IosColors.muted : IosColors.accent), stroke: 1.3)),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: dark ? IosColors.dInk : IosColors.ink)),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, height: 1.55, color: dark ? IosColors.dMuted : IosColors.muted)),
          if (actions.isNotEmpty) ...[const SizedBox(height: 22), Wrap(spacing: 14, runSpacing: 10, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: actions)],
        ]),
      );
}

/// 暖棕实心胶囊按钮（每屏唯一的主操作）。
class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final String? icon;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(color: IosColors.accent, borderRadius: BorderRadius.circular(23)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
            if (icon != null) ...[const SizedBox(width: 8), AppIcon(icon!, size: 18, color: Colors.white, stroke: 1.9)],
          ]),
        ),
      );
}

class TextAction extends StatelessWidget {
  const TextAction({super.key, required this.label, required this.onTap, this.color = IosColors.accent});

  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Text(label, style: TextStyle(fontSize: 17, color: color, fontWeight: FontWeight.w500)),
        ),
      );
}

/// 加载中的占位块（redacted）。
class Redacted extends StatelessWidget {
  const Redacted({super.key, this.width, required this.height, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(width: width, height: height, decoration: BoxDecoration(color: IosColors.faint, borderRadius: BorderRadius.circular(radius)));
}

/// 底部的轻提示（玻璃胶囊，1.6 秒后消失）。
void showIosToast(BuildContext context, String text, {bool dark = false}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 24,
      right: 24,
      bottom: MediaQuery.paddingOf(context).bottom + 110,
      child: IgnorePointer(
        child: Center(
          child: _ToastBody(text: text, dark: dark, onDone: () => entry.remove()),
        ),
      ),
    ),
  );
  overlay.insert(entry);
}

class _ToastBody extends StatefulWidget {
  const _ToastBody({required this.text, required this.dark, required this.onDone});

  final String text;
  final bool dark;
  final VoidCallback onDone;

  @override
  State<_ToastBody> createState() => _ToastBodyState();
}

class _ToastBodyState extends State<_ToastBody> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () async {
      if (!mounted) return;
      await _c.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _c,
        child: Glass(
          radius: 22,
          dark: widget.dark,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Text(widget.text, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: widget.dark ? IosColors.dInk : IosColors.ink, decoration: TextDecoration.none, fontWeight: FontWeight.w500)),
        ),
      );
}

/// 系统风格的单行输入提示框。
Future<String?> showIosPrompt(BuildContext context, {required String title, String? message, String initial = '', String? placeholder, String confirm = '确定'}) {
  final input = TextEditingController(text: initial);
  return showCupertinoDialog<String>(
    context: context,
    builder: (dialog) => CupertinoAlertDialog(
      title: Text(title),
      content: Column(children: [
        if (message != null) Padding(padding: const EdgeInsets.only(top: 4, bottom: 10), child: Text(message)),
        CupertinoTextField(controller: input, placeholder: placeholder, autofocus: true, clearButtonMode: OverlayVisibilityMode.editing),
      ]),
      actions: [
        CupertinoDialogAction(onPressed: () => Navigator.pop(dialog), child: const Text('取消')),
        CupertinoDialogAction(isDefaultAction: true, onPressed: () => Navigator.pop(dialog, input.text), child: Text(confirm)),
      ],
    ),
  ).whenComplete(() => Future.delayed(const Duration(milliseconds: 400), input.dispose));
}

/// 系统风格的选择表（操作表）。返回选中的下标，取消返回 null。
Future<int?> showIosChoices(BuildContext context, {String? title, required List<String> options, int? selected, int? destructiveIndex}) =>
    showCupertinoModalPopup<int>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (var i = 0; i < options.length; i++)
            CupertinoActionSheetAction(
              isDestructiveAction: i == destructiveIndex,
              isDefaultAction: i == selected,
              onPressed: () => Navigator.pop(sheet, i),
              child: Text(i == selected ? '${options[i]}  ✓' : options[i]),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(onPressed: () => Navigator.pop(sheet), child: const Text('取消')),
      ),
    );
