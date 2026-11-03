import 'package:flutter/material.dart';

import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// 文字阅读的四种页面配色。
class ReaderTheme {
  const ReaderTheme({
    required this.name,
    required this.bg,
    required this.ink,
    required this.muted,
    required this.track,
    required this.progress,
    required this.sheet,
    required this.card,
    required this.segment,
    required this.segmentActive,
    this.dark = false,
  });

  final String name;
  final Color bg, ink, muted, track, progress, sheet, card, segment, segmentActive;
  final bool dark;

  static const all = [
    ReaderTheme(
      name: '纸白',
      bg: Color(0xFFF6F5EF),
      ink: Color(0xFF303E38),
      muted: Color(0xFF606D61),
      track: Color(0xFFDEDFD7),
      progress: Color(0xFF7F9286),
      sheet: Color(0xFFF2F3EE),
      card: Color(0xFFFCFCF9),
      segment: Color(0xFFE6EAE2),
      segmentActive: Color(0xFFFCFCF9),
    ),
    ReaderTheme(
      name: '暖纸',
      bg: Color(0xFFEEE2C8),
      ink: Color(0xFF4A4032),
      muted: Color(0xFF76674F),
      track: Color(0xFFD4C6A7),
      progress: Color(0xFFA08359),
      sheet: Color(0xFFF4EBDB),
      card: Color(0xFFFAF3E7),
      segment: Color(0xFFE8DCC6),
      segmentActive: Color(0xFFFAF3E7),
    ),
    ReaderTheme(
      name: '雾绿',
      bg: Color(0xFFE6ECE3),
      ink: Color(0xFF344637),
      muted: Color(0xFF50634F),
      track: Color(0xFFC9D6C3),
      progress: Color(0xFF6D8367),
      sheet: Color(0xFFEEF2EA),
      card: Color(0xFFF7F9F4),
      segment: Color(0xFFDCE5D7),
      segmentActive: Color(0xFFF7F9F4),
    ),
    ReaderTheme(
      name: '夜间',
      bg: Color(0xFF202725),
      ink: Color(0xFFC9D0C7),
      muted: Color(0xFFA4B3A7),
      track: Color(0xFF414D46),
      progress: Color(0xFF91AA94),
      sheet: Color(0xFF29322E),
      card: Color(0xFF353F39),
      segment: Color(0xFF202A25),
      segmentActive: Color(0xFF50614D),
      dark: true,
    ),
  ];
}

/// 排版选项与它们的显示名。
class Typo {
  Typo._();

  static const fonts = [('思源宋体', kSerif), ('思源黑体', 'sans-serif'), ('等宽', 'monospace')];
  static const lines = [('紧凑', 1.6), ('适中', 1.91), ('宽松', 2.2)];
  static const weights = [('常规', FontWeight.w400), ('适中', FontWeight.w500), ('加粗', FontWeight.w700)];
  static const margins = [('紧凑', 18.0), ('标准', 27.0), ('宽阔', 38.0)];
  static const inks = ['默认', '柔和', '浓墨'];

  static Color inkOf(ReaderTheme t, int i) => switch (i) {
        1 => t.ink.withValues(alpha: .72),
        2 => t.dark ? const Color(0xFFE8EDE6) : const Color(0xFF1B2622),
        _ => t.ink,
      };

  static TextStyle body(ReaderPrefs p, ReaderTheme t, {double? size}) => TextStyle(
        fontFamily: fonts[p.font].$2,
        fontSize: size ?? p.fontSize,
        height: lines[p.line].$2,
        fontWeight: weights[p.weight].$2,
        letterSpacing: p.spacing,
        color: inkOf(t, p.ink),
      );
}

Future<void> showReaderSettings(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x3D17251E),
      builder: (_) => const ReaderSettingsSheet(),
    );

class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({super.key});

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  final _p = ReaderPrefs.instance;
  bool _typography = false;
  bool _more = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _p,
        builder: (context, _) {
          final t = ReaderTheme.all[_p.theme];
          return Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.paddingOf(context).bottom),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .82),
              decoration: BoxDecoration(
                color: t.sheet,
                borderRadius: BorderRadius.circular(26),
                boxShadow: const [BoxShadow(color: Color(0x14182B24), blurRadius: 36, offset: Offset(0, -8))],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: DefaultTextStyle(
                  style: TextStyle(color: t.ink, fontSize: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                    Center(
                      child: Container(
                        width: 32,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 6),
                        decoration: BoxDecoration(color: t.track, borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 170),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(position: Tween(begin: const Offset(.04, 0), end: Offset.zero).animate(a), child: child),
                      ),
                      child: _typography ? _typographyPage(t) : _appearancePage(t),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      );

  Widget _circle(ReaderTheme t, String icon, VoidCallback onTap, String tip) =>
      ToolButton(icon: icon, onTap: onTap, tooltip: tip, background: t.card, color: t.ink, iconSize: 20);

  Widget _label(ReaderTheme t, String text, [String? trailing]) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Row(children: [
          Text(text, style: TextStyle(fontSize: 13, color: t.ink, fontWeight: FontWeight.w500)),
          const Spacer(),
          if (trailing != null) Text(trailing, style: TextStyle(fontSize: 12, color: t.muted)),
        ]),
      );

  Widget _segmented(ReaderTheme t, List<String> options, int selected, ValueChanged<int> onChanged) => Segmented(
        options: options,
        selected: selected,
        onChanged: onChanged,
        background: t.segment,
        active: t.segmentActive,
        ink: t.dark ? Colors.white : t.ink,
        muted: t.muted,
      );

  Widget _slider(ReaderTheme t, {required double value, required double min, required double max, int? divisions, required ValueChanged<double> onChanged}) =>
      SliderTheme(
        data: SliderTheme.of(context).copyWith(activeTrackColor: t.progress, inactiveTrackColor: t.track, thumbColor: t.card),
        child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
      );

  Widget _appearancePage(ReaderTheme t) => Column(
        key: const ValueKey('appearance'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Text('阅读外观', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const Spacer(),
            _circle(t, 'close', () => Navigator.pop(context), '关闭'),
          ]),
          _label(t, '页面配色', t.name),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i < ReaderTheme.all.length; i++) _themeChoice(t, i),
          ]),
          _label(t, '亮度', '${(_p.brightness * 100).round()}%'),
          Row(children: [
            AppIcon('sun', size: 14, color: t.muted),
            Expanded(child: _slider(t, value: _p.brightness, min: .3, max: 1, onChanged: (v) => _p.brightness = v)),
            AppIcon('sun', size: 19, color: t.muted),
          ]),
          const SizedBox(height: 14),
          Material(
            color: t.card,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => _typography = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(children: [
                  AppIcon('type', size: 22, color: t.ink),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('字体与排版', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${Typo.fonts[_p.font].$1}  ·  ${_p.fontSize.round()} px', style: TextStyle(fontSize: 12, color: t.muted)),
                    ]),
                  ),
                  AppIcon('right', size: 18, color: t.muted),
                ]),
              ),
            ),
          ),
          _label(t, '页边距'),
          _segmented(t, [for (final m in Typo.margins) m.$1], _p.margin, (v) => _p.margin = v),
        ],
      );

  Widget _themeChoice(ReaderTheme t, int i) {
    final c = ReaderTheme.all[i];
    final active = _p.theme == i;
    return GestureDetector(
      onTap: () => _p.theme = i,
      child: Column(children: [
        Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: active ? (t.dark ? const Color(0xFFA8BF97) : const Color(0xFF526C65)) : Colors.transparent, width: 1.5),
            ),
            child: Container(
              decoration: BoxDecoration(color: c.bg, shape: BoxShape.circle, border: Border.all(color: c.track)),
              alignment: Alignment.center,
              child: Text('字', style: TextStyle(fontFamily: kSerif, fontSize: 22, color: c.ink)),
            ),
          ),
          if (active)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: Palette.ink, shape: BoxShape.circle, border: Border.all(color: t.sheet, width: 2)),
                alignment: Alignment.center,
                child: const AppIcon('check', size: 11, color: Colors.white, stroke: 2.4),
              ),
            ),
        ]),
        const SizedBox(height: 7),
        Text(c.name, style: TextStyle(fontSize: 12, color: active ? t.ink : t.muted, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      ]),
    );
  }

  Widget _typographyPage(ReaderTheme t) => Column(
        key: const ValueKey('typography'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            _circle(t, 'left', () => setState(() => _typography = false), '返回阅读外观'),
            const SizedBox(width: 12),
            const Text('字体与排版', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const Spacer(),
            _circle(t, 'close', () => Navigator.pop(context), '关闭'),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(color: t.card, borderRadius: BorderRadius.circular(16)),
            child: Text('此刻，风轻轻吹过。\n下一页，故事继续。', textAlign: TextAlign.center, style: Typo.body(_p, t)),
          ),
          const SizedBox(height: 12),
          Material(
            color: t.card,
            borderRadius: BorderRadius.circular(16),
            child: PopupMenuButton<int>(
              initialValue: _p.font,
              onSelected: (v) => _p.font = v,
              color: t.card,
              itemBuilder: (_) => [
                for (var i = 0; i < Typo.fonts.length; i++)
                  PopupMenuItem(value: i, child: Text(Typo.fonts[i].$1, style: TextStyle(fontFamily: Typo.fonts[i].$2, color: t.ink))),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Row(children: [
                  const Text('阅读字体', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  Text(Typo.fonts[_p.font].$1, style: TextStyle(fontSize: 13, color: t.muted)),
                  const SizedBox(width: 8),
                  AppIcon('right', size: 16, color: t.muted),
                ]),
              ),
            ),
          ),
          _label(t, '字体大小', '${_p.fontSize.round()} px'),
          _slider(t, value: _p.fontSize, min: 16, max: 26, divisions: 10, onChanged: (v) => _p.fontSize = v),
          _label(t, '行距'),
          _segmented(t, [for (final l in Typo.lines) l.$1], _p.line, (v) => _p.line = v),
          _label(t, '字重'),
          _segmented(t, [for (final w in Typo.weights) w.$1], _p.weight, (v) => _p.weight = v),
          const SizedBox(height: 16),
          Divider(height: 1, color: t.track),
          InkWell(
            onTap: () => setState(() => _more = !_more),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(children: [
                const Text('更多排版', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const Spacer(),
                Text('字色、字间距', style: TextStyle(fontSize: 12, color: t.muted)),
                const SizedBox(width: 6),
                AnimatedRotation(turns: _more ? .5 : 0, duration: const Duration(milliseconds: 160), child: AppIcon('down', size: 14, color: t.muted)),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            alignment: Alignment.topCenter,
            child: _more
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _segmented(t, Typo.inks, _p.ink, (v) => _p.ink = v),
                    _label(t, '字间距', _p.spacing.toStringAsFixed(1)),
                    _slider(t, value: _p.spacing, min: 0, max: 3, divisions: 6, onChanged: (v) => _p.spacing = v),
                  ])
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 8),
          Material(
            color: t.card,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _p.resetTypography,
              child: const SizedBox(height: 48, child: Center(child: Text('恢复默认排版', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)))),
            ),
          ),
        ],
      );
}
