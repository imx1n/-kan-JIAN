import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/motion.dart';
import 'ios_novel.dart' show novelPaperName, showNovelAppearance;
import 'ios_theme.dart';

/// 「我的」下的二级设置页：玻璃返回按钮 + 居中标题 + 分组列表。账号同步页也用它。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: IosColors.bg,
      body: ListenableBuilder(
        listenable: ReaderPrefs.instance,
        builder: (context, _) => Stack(children: [
          ListView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(top: top + 60, bottom: 40),
            children: children,
          ),
          Positioned(
            top: top + 4,
            left: 16,
            right: 16,
            child: SizedBox(
              height: 44,
              child: Stack(alignment: Alignment.center, children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: IosColors.ink)),
                Align(alignment: Alignment.centerLeft, child: GlassButton(icon: 'chevronLeft', label: '返回', onTap: () => Navigator.pop(context))),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

void _push(BuildContext context, Widget page) => Navigator.of(context).push(appRoute<void>((_) => page));

Future<void> _pick(BuildContext context, String title, List<String> options, int selected, ValueChanged<int> onPick) async {
  final i = await showIosChoices(context, title: title, options: options, selected: selected);
  if (i != null) onPick(i);
}

const _appearanceNames = ['跟随系统', '浅色', '深色'];

String appearanceName(int v) => _appearanceNames[v.clamp(0, 2)];

/// 外观设置：深色模式、减少透明度。
class IosAppearancePage extends StatelessWidget {
  const IosAppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ReaderPrefs.instance;
    return SettingsPage(title: '外观设置', children: [
      InsetGroup(title: '界面外观', children: [
        IosRow(title: '深色模式', value: appearanceName(p.appearance), onTap: () => _push(context, const IosThemePage())),
      ]),
      InsetGroup(title: '显示效果', footer: '降低导航栏与浮动控件的透明度，让文字更清晰。', children: [
        IosRow(
          title: '减少透明度',
          chevron: false,
          valueWidget: CupertinoSwitch(value: p.reduceTransparency, activeTrackColor: IosColors.accent, onChanged: GlassScope.set),
          onTap: () => GlassScope.set(!p.reduceTransparency),
        ),
      ]),
    ]);
  }
}

/// 深色模式：跟随系统 / 浅色 / 深色。小说纸张单独在阅读设置里调。
class IosThemePage extends StatelessWidget {
  const IosThemePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ReaderPrefs.instance;
    return SettingsPage(title: '深色模式', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 26),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _PhonePreview(dark: false, onTap: () => p.appearance = 1),
          const SizedBox(width: 28),
          _PhonePreview(dark: true, onTap: () => p.appearance = 2),
        ]),
      ),
      InsetGroup(
        footer: '跟随系统时，外观会随系统的浅色与深色模式自动切换。小说纸张可在阅读设置中单独调整。',
        children: [
          for (var i = 0; i < _appearanceNames.length; i++)
            IosRow(
              title: _appearanceNames[i],
              chevron: false,
              valueWidget: p.appearance == i ? AppIcon('check', size: 18, color: IosColors.accent, stroke: 2.2) : const SizedBox(width: 18),
              onTap: () => p.appearance = i,
            ),
        ],
      ),
    ]);
  }
}

/// 深浅两种外观的缩略示意：书架标题、三本书、进度线和底栏。
class _PhonePreview extends StatelessWidget {
  const _PhonePreview({required this.dark, required this.onTap});

  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = dark ? IosColors.dBg : const Color(0xFFF9F9FB);
    final ink = dark ? IosColors.dInk : const Color(0xFF222328);
    final faint = dark ? IosColors.dFaint : const Color(0xFFE5E5EA);
    return Pressable(
      onTap: onTap,
      semanticLabel: dark ? '深色' : '浅色',
      child: Container(
        width: 104,
        height: 176,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: dark ? const Color(0xFF45454D) : const Color(0xFFCFCFD6)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 34, height: 8, decoration: BoxDecoration(color: const Color(0xFF09090B), borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 12),
          Text('书架', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ink)),
          const SizedBox(height: 8),
          Row(children: [
            for (final c in const [Color(0xFFDCC3B8), Color(0xFFB1BFB4), Color(0xFFC4C0D1)]) ...[
              if (c != const Color(0xFFDCC3B8)) const SizedBox(width: 5),
              Expanded(child: Container(height: 40, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3)))),
            ],
          ]),
          const SizedBox(height: 10),
          Container(width: 58, height: 3, decoration: BoxDecoration(color: faint, borderRadius: BorderRadius.circular(2))),
          const Spacer(),
          Container(height: 16, decoration: BoxDecoration(color: faint, borderRadius: BorderRadius.circular(8))),
        ]),
      ),
    );
  }
}

/// 阅读设置：漫画阅读方式、翻页方向、画质；轻小说纸张与排版。
class IosReadingSettingsPage extends StatelessWidget {
  const IosReadingSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = ReaderPrefs.instance;
    return SettingsPage(title: '阅读设置', children: [
      InsetGroup(title: '漫画', footer: '画质更改将在下次载入图片时应用。阅读器里也可以随时切换。', children: [
        IosRow(
          title: '阅读方式',
          value: p.mangaScroll ? '条漫' : '单页',
          onTap: () => _pick(context, '阅读方式', const ['单页', '条漫'], p.mangaScroll ? 1 : 0, (i) => p.mangaScroll = i == 1),
        ),
        IosRow(
          title: '翻页方向',
          value: p.mangaRtl ? '从右向左' : '从左向右',
          onTap: () => _pick(context, '翻页方向', const ['从右向左', '从左向右'], p.mangaRtl ? 0 : 1, (i) => p.mangaRtl = i == 0),
        ),
        IosRow(
          title: '图片画质',
          value: p.mangaSaver ? '省流' : '标准',
          onTap: () => _pick(context, '图片画质', const ['省流 · 800px', '标准 · 1500px'], p.mangaSaver ? 0 : 1, (i) => p.mangaSaver = i == 0),
        ),
      ]),
      InsetGroup(title: '轻小说', children: [
        IosRow(
          title: '纸张与排版',
          subtitle: '纸张、字体、字号与行距',
          value: '${novelPaperName(p.theme)} · ${p.fontSize.round()} 磅',
          onTap: () => showNovelAppearance(context),
        ),
      ]),
    ]);
  }
}
