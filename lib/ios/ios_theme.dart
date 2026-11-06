import 'dart:io' show Platform;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/motion.dart';

/// iOS 26 设计稿的色板：近白实底承载内容，暖棕为唯一强调色；深色模式按设计稿的 dark 变量。
/// 阅读器始终是深色，直接用下面 d 开头的常量。
class IosColors {
  IosColors._();

  /// 当前是否深色模式，由 [IosApp] 根据「外观设置」和系统外观决定。
  static bool isDark = false;

  static Color get bg => isDark ? dBg : const Color(0xFFF9F9FB);
  static Color get surface => isDark ? dSurface : const Color(0xFFFFFFFF);
  static Color get ink => isDark ? dInk : const Color(0xFF222328);
  static Color get muted => isDark ? dMuted : const Color(0xFF62636B);
  static Color get faint => isDark ? dFaint : const Color(0xFFE9E9EE);
  static Color get line => isDark ? dLine : const Color(0xFFE2E2E8);
  static Color get accent => isDark ? dAccent : const Color(0xFF914638);
  static Color get accentSoft => isDark ? const Color(0xFF45312D) : const Color(0xFFF3E9E5);
  static Color get tab => isDark ? dMuted : const Color(0xFF5C5D65);

  /// 实心强调按钮上的文字：浅色模式白字，深色模式（浅色按钮）深字。
  static Color get onAccent => isDark ? const Color(0xFF291C18) : const Color(0xFFFFFFFF);

  static const dBg = Color(0xFF15161A);
  static const dSurface = Color(0xFF25262C);
  static const dInk = Color(0xFFF5F5F7);
  static const dMuted = Color(0xFFB5B5C0);
  static const dLine = Color(0xFF45454D);
  static const dFaint = Color(0xFF35363E);
  static const dAccent = Color(0xFFF1B4A4);
}

/// 系统栏：状态栏和 Android 导航栏都透明，内容画到后面。浅色页面用深色图标。
const kLightChrome = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.dark,
  statusBarBrightness: Brightness.light,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.dark,
  systemNavigationBarContrastEnforced: false,
);

/// 普通页面的系统栏：跟随深色模式。
SystemUiOverlayStyle get pageChrome => IosColors.isDark ? kDarkChrome : kLightChrome;

/// 深色页面（漫画阅读器、深色纸张）用浅色图标。
const kDarkChrome = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: Colors.transparent,
  systemNavigationBarDividerColor: Colors.transparent,
  systemNavigationBarIconBrightness: Brightness.light,
  systemNavigationBarContrastEnforced: false,
);

/// 小说正文用系统宋体（iOS 自带 Songti SC），Android 回退到 serif（Noto Serif CJK）。
const kIosSerif = TextStyle(fontFamily: 'Songti SC', fontFamilyFallback: ['STSong', 'serif']);

/// 应用主题。两端都按 iOS 平台处理：回弹滚动、右滑返回、Cupertino 控件。
ThemeData buildAppTheme() => ThemeData(
      platform: TargetPlatform.iOS,
      brightness: IosColors.isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: IosColors.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: IosColors.accent,
        brightness: IosColors.isDark ? Brightness.dark : Brightness.light,
        primary: IosColors.accent,
        surface: IosColors.bg,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      cupertinoOverrideTheme: CupertinoThemeData(primaryColor: IosColors.accent, brightness: IosColors.isDark ? Brightness.dark : Brightness.light),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      }),
    );

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

/// 玻璃材质：iOS 用 Liquid Glass（着色器折射），安卓用毛玻璃；减少透明度时都退回实底。
///
/// 只用于导航、工具和暂态面板，内容层保持实底。全 App 的玻璃都走这一个组件
/// （标签栏、浮动按钮、底部面板、阅读工具条），所以换材质只需要改这里。
///
/// **两端分开**：iOS 走 `liquid_glass_widgets` 的 [AdaptiveGlass]（Impeller 着色器，
/// 有折射、色散和高光）；安卓没有 Impeller 那套 `toImageSync` 背景抓取，库在安卓上
/// 只剩 2D 轻量路径或纯模糊，观感反而不如原来的毛玻璃，所以安卓保留
/// `BackdropFilter` + 半透明填充 + 细亮边的老实现。
///
/// iOS 上**必须显式选 `premium` 档**：库的默认值是 `standard`，走的是 2D 轻量着色器，
/// 只有模糊和高光，没有真正的折射——看上去和毛玻璃没区别。
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.radius = 22, this.dark = false, this.padding, this.shadow = true, this.quality = GlassQuality.premium});

  final Widget child;
  final double radius;
  final bool dark;
  final EdgeInsetsGeometry? padding;
  final bool shadow;

  /// 渲染档位，仅 iOS 生效。[GlassQuality.premium] 有折射；[GlassQuality.standard]
  /// 只有模糊，用在会跟着列表滚动的玻璃上（每帧抓背景纹理代价太高）。
  final GlassQuality quality;

  @override
  Widget build(BuildContext context) {
    final reduce = GlassScope.reduced(context);
    final dark = this.dark || IosColors.isDark;
    final r = BorderRadius.circular(radius);
    final content = padding == null ? child : Padding(padding: padding!, child: child);

    // 减少透明度：不参与折射，直接用实底，和 iOS「降低透明度」的行为一致。
    if (reduce) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: shadow ? [BoxShadow(color: dark ? const Color(0x59000000) : const Color(0x1F1A1A28), blurRadius: 18, offset: const Offset(0, 6))] : null,
        ),
        child: ClipRRect(
          borderRadius: r,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark ? IosColors.dSurface : const Color(0xFFF2F2F6),
              borderRadius: r,
              border: Border.all(color: dark ? const Color(0x2EFFFFFF) : const Color(0x8CFFFFFF), width: .8),
            ),
            child: content,
          ),
        ),
      );
    }

    // 安卓：毛玻璃。模糊 22 + 半透明填充 + 细亮边，和 0.3.6 之前一致。
    if (!Platform.isIOS) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: shadow ? [BoxShadow(color: dark ? const Color(0x59000000) : const Color(0x1F1A1A28), blurRadius: 18, offset: const Offset(0, 6))] : null,
        ),
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: dark ? const Color(0xAD292A31) : const Color(0xB0F8F8FB),
                borderRadius: r,
                border: Border.all(color: dark ? const Color(0x2EFFFFFF) : const Color(0x8CFFFFFF), width: .8),
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    return AdaptiveGlass(
      quality: quality,
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      // 这组数值是给 premium 档调的：premium 直接用原值（只有 standard 档会做归一化
      // 把 thickness 乘 0.4、lightIntensity 乘 0.6），所以光和色散要按 3D 着色的量级给。
      // 之前那组 .5 / .01 是按 2D 档试的，放到 premium 下折射几乎看不出来。
      settings: LiquidGlassSettings(
        blur: 10,
        thickness: 26,
        // 深色下用暗色染色，浅色下用极淡的白色，保留折射的同时压住背景杂色。
        glassColor: dark ? const Color(0x38292A31) : const Color(0x40F8F8FB),
        lightIntensity: 1.5,
        refractiveIndex: 1.2,
        chromaticAberration: .12,
        saturation: 1.5,
        shadowElevation: shadow ? 1.0 : 0.0,
      ),
      child: content,
    );
  }
}

/// 按下时轻微缩放、变淡，替代 Material 水波纹。
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.onLongPress, this.haptic = false, this.semanticLabel, this.dimWhenDisabled = true, this.pressedScale = .975});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  final String? semanticLabel;

  /// 没有 [onTap] 时是否变淡表示不可用。
  final bool dimWhenDisabled;

  /// 按下时的缩放：普通按钮 0.975，底部导航 0.96（设计稿）。
  final double pressedScale;

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
          // 按下 80ms 缩到 0.975、透明度 0.88；松开 180ms 恢复。
          child: AnimatedScale(
            scale: _down ? widget.pressedScale : 1,
            duration: Motion.of(context, _down ? 80 : 180),
            curve: Motion.ease,
            child: AnimatedOpacity(
              opacity: _down ? .88 : (widget.onTap == null && widget.dimWhenDisabled ? .4 : 1),
              duration: Motion.of(context, _down ? 80 : 140),
              child: widget.child,
            ),
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
                child: Text(title, style: TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -.4, color: IosColors.ink)),
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

/// 文字页签 + 选中项下方的短下划线，底部一条细分隔线。用于搜索范围和目录分组。
class UnderlineTabs extends StatelessWidget {
  const UnderlineTabs({super.key, required this.options, required this.selected, required this.onChanged, this.counts, this.padding = const EdgeInsets.symmetric(horizontal: 20)});

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;
  final List<int?>? counts;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: IosColors.line, width: .5))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (var i = 0; i < options.length; i++)
                Pressable(
                  onTap: () {
                    if (i == selected) return;
                    HapticFeedback.selectionClick();
                    onChanged(i);
                  },
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : 14, right: 14),
                    child: SizedBox(
                      height: 48,
                      child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(text: options[i]),
                            if (counts != null && counts![i] != null)
                              TextSpan(text: '  ${counts![i]}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, color: IosColors.muted)),
                          ]),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: i == selected ? FontWeight.w700 : FontWeight.w400,
                            color: i == selected ? IosColors.ink : IosColors.muted,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            opacity: i == selected ? 1 : 0,
                            child: Container(width: 22, height: 3, decoration: BoxDecoration(color: IosColors.accent, borderRadius: BorderRadius.circular(2))),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
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
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: IosColors.accent, shape: BoxShape.circle)),
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
          Text(title, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: IosColors.ink)),
          if (count != null) ...[
            const SizedBox(width: 8),
            Text(count!, style: TextStyle(fontSize: 15, color: IosColors.muted)),
          ],
          const Spacer(),
          if (note != null) Text(note!, style: TextStyle(fontSize: 13, color: IosColors.muted)),
          if (action != null)
            Pressable(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(action!, style: TextStyle(fontSize: 15, color: IosColors.accent)),
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
            child: Text(title!, style: TextStyle(fontSize: 13, color: IosColors.muted)),
          ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(color: IosColors.surface, borderRadius: BorderRadius.circular(18)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              // 有图标的行，分隔线从文字开始；没有图标时从行首的文字边距开始。
              if (i > 0) Padding(padding: EdgeInsets.only(left: children[i] is IosRow && (children[i] as IosRow).icon == null ? 16 : 52), child: Divider(height: 1, thickness: .5, color: IosColors.line)),
              children[i],
            ],
          ]),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 7, 32, 0),
            child: Text(footer!, style: TextStyle(fontSize: 13, height: 1.45, color: IosColors.muted)),
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

  /// 只展示信息、不能点的行（没有箭头也没有操作）照常显示，不按「不可用」变淡。
  bool get _informational => onTap == null && !chevron;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        dimWhenDisabled: !_informational,
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
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: IosColors.muted)),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              ?valueWidget,
              if (value != null) Text(value!, style: TextStyle(fontSize: 15, color: IosColors.muted)),
              if (chevron && onTap != null) ...[const SizedBox(width: 6), AppIcon('right', size: 14, color: IosColors.muted, stroke: 2)],
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
            Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: IosColors.onAccent)),
            if (icon != null) ...[const SizedBox(width: 8), AppIcon(icon!, size: 18, color: IosColors.onAccent, stroke: 1.9)],
          ]),
        ),
      );
}

class TextAction extends StatelessWidget {
  const TextAction({super.key, required this.label, required this.onTap, this.color});

  final String label;
  final VoidCallback? onTap;

  /// 默认强调色。
  final Color? color;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          child: Text(label, style: TextStyle(fontSize: 17, color: color ?? IosColors.accent, fontWeight: FontWeight.w500)),
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
  late final _c = AnimationController(vsync: this, duration: Motion.ms(220), reverseDuration: Motion.ms(150));
  late final _in = CurvedAnimation(parent: _c, curve: Motion.ease, reverseCurve: Motion.exit.flipped);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed && !_shown) {
      _shown = true;
      if (Motion.reduced(context)) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  bool _shown = false;

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
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _in,
        builder: (_, c) => Opacity(opacity: _in.value, child: Transform.translate(offset: Offset(0, 8 * (1 - _in.value)), child: c)),
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
