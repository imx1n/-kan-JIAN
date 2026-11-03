import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/store.dart';
import '../core/update_service.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';
import 'home_shell.dart';
import 'novel_reader_page.dart';
import 'reader_settings_sheet.dart';
import 'update_dialog.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  final _prefs = ReaderPrefs.instance;
  final _store = LibraryStore.instance;

  String? _ping;
  bool _pingOk = false;
  bool _pinging = false;
  DateTime? _pingedAt;

  int? _cacheBytes;
  String _version = '';
  bool _checking = false;
  UpdateResult? _update;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_changed);
    _store.addListener(_changed);
    HomeShell.tab.addListener(_onTab);
    UpdateService.instance.currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    _prefs.removeListener(_changed);
    _store.removeListener(_changed);
    HomeShell.tab.removeListener(_onTab);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// 切到「我的」时测一次数据源（一分钟内不重复），并刷新缓存大小。
  void _onTab() {
    if (HomeShell.tab.value != 2) return;
    if (_pingedAt == null || DateTime.now().difference(_pingedAt!) > const Duration(minutes: 1)) _testSource();
    _measureCache();
  }

  Future<void> _testSource() async {
    setState(() => _pinging = true);
    try {
      final d = await MangaApi.instance.ping();
      _ping = '正常 · ${d.inMilliseconds}ms';
      _pingOk = true;
    } catch (e) {
      _ping = '连接失败';
      _pingOk = false;
    }
    _pingedAt = DateTime.now();
    if (mounted) setState(() => _pinging = false);
  }

  Future<Directory> _cacheDir() async => Directory('${(await getTemporaryDirectory()).path}/${DefaultCacheManager.key}');

  Future<void> _measureCache() async {
    var total = 0;
    try {
      final dir = await _cacheDir();
      if (await dir.exists()) {
        await for (final f in dir.list(recursive: true, followLinks: false)) {
          if (f is File) total += await f.length();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _cacheBytes = total);
  }

  Future<void> _clearCache() async {
    await DefaultCacheManager().emptyCache();
    imageCache.clear();
    await _measureCache();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('图片缓存已清除')));
  }

  Future<void> _clearHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('清除阅读记录？'),
        content: const Text('会清掉每部作品读到哪一页和已读标记。书架上的作品和追更状态会保留。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialog, true), style: TextButton.styleFrom(foregroundColor: Palette.accent), child: const Text('清除')),
        ],
      ),
    );
    if (ok == true) _store.clearHistory();
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final r = await runManualUpdateCheck(context);
    if (mounted) {
      setState(() {
        _checking = false;
        _update = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final novelTheme = ReaderTheme.all[_prefs.theme].name;
    return SafeArea(
      bottom: false,
      child: ListView(padding: const EdgeInsets.only(bottom: 28), children: [
        const SizedBox(
          height: 56,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('我的', style: TextStyle(fontFamily: kSerif, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 1, height: 1)),
            ),
          ),
        ),
        const _GroupTitle('阅读'),
        _Card(children: [
          _Row(
            icon: 'direction',
            title: '漫画翻页方向',
            trailing: _InlineSeg(options: const ['从右向左', '从左向右'], selected: _prefs.mangaRtl ? 0 : 1, onChanged: (i) => _prefs.mangaRtl = i == 0),
          ),
          _Row(
            icon: 'pages',
            title: '默认阅读方式',
            subtitle: '阅读器里也可以随时切换',
            trailing: _InlineSeg(options: const ['单页', '条漫'], selected: _prefs.mangaScroll ? 1 : 0, onChanged: (i) => _prefs.mangaScroll = i == 1),
          ),
          _Row(
            icon: 'image',
            title: '图片画质',
            subtitle: '省流用 800px 高的图，标准为 1500px',
            trailing: _InlineSeg(options: const ['标准', '省流'], selected: _prefs.mangaSaver ? 1 : 0, onChanged: (i) => _prefs.mangaSaver = i == 1),
          ),
          _Row(
            icon: 'type',
            title: '轻小说外观',
            subtitle: '在示例《雨停之前》里调整',
            value: '$novelTheme · ${_prefs.fontSize.round()}px',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NovelReaderPage())),
          ),
        ]),
        const _GroupTitle('网络'),
        _Card(children: [
          _Row(
            icon: 'globe',
            title: '数据源',
            subtitle: Uri.parse(MangaApi.instance.activeHost).host,
            valueWidget: _pinging
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_ping != null) ...[
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: _pingOk ? Palette.sage : Palette.accent, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                    ],
                    Text(_ping ?? '点按测试', style: TextStyle(fontSize: 13, color: _ping != null && !_pingOk ? Palette.accent : Palette.ink2)),
                  ]),
            onTap: _pinging ? null : _testSource,
          ),
          _Row(
            icon: 'route',
            title: '网络代理',
            subtitle: '模拟器内 10.0.2.2 指向电脑；重启后生效',
            value: _prefs.proxy.isEmpty ? '直连' : _prefs.proxy,
            onTap: () => showProxyEditor(context),
          ),
        ]),
        const _GroupTitle('存储'),
        _Card(children: [
          _Row(
            icon: 'database',
            title: '图片缓存',
            subtitle: '只缓存看过的页，不做批量下载',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_cacheBytes == null ? '—' : formatBytes(_cacheBytes!), style: const TextStyle(fontSize: 13, color: Palette.ink2)),
              TextButton(onPressed: _clearCache, style: TextButton.styleFrom(foregroundColor: Palette.ink, minimumSize: const Size(48, 40)), child: const Text('清除')),
            ]),
          ),
          _Row(
            icon: 'history',
            title: '阅读记录',
            subtitle: '书架 ${_store.entries.length} 部 · 已读 ${_store.readChapterCount} 话',
            trailing: TextButton(onPressed: _clearHistory, style: TextButton.styleFrom(foregroundColor: Palette.ink, minimumSize: const Size(48, 40)), child: const Text('清除')),
          ),
        ]),
        const _GroupTitle('关于'),
        _Card(children: [
          _Row(
            icon: 'download',
            title: '检查更新',
            subtitle: '当前 v$_version · 从 GitHub Releases 获取',
            valueWidget: _checking
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : switch (_update?.status) {
                    UpdateStatus.available => NewBadge('v${_update!.release!.version}'),
                    UpdateStatus.upToDate => const Text('已是最新', style: TextStyle(fontSize: 13, color: Palette.ink2)),
                    UpdateStatus.noRelease => const Text('暂无发布', style: TextStyle(fontSize: 13, color: Palette.ink2)),
                    UpdateStatus.failed => const Text('检查失败', style: TextStyle(fontSize: 13, color: Palette.accent)),
                    null => const SizedBox.shrink(),
                  },
            onTap: _checking ? null : _checkUpdate,
          ),
          _Row(
            icon: 'github',
            title: '项目主页',
            subtitle: AppConfig.githubPage.replaceFirst('https://', ''),
            onTap: () => launchUrl(Uri.parse(AppConfig.githubPage), mode: LaunchMode.externalApplication),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            '栞间只是阅读器：不内置账号，不绕过付费与会员限制。作品实时来自源站，版权归原作者与权利人所有。',
            style: TextStyle(fontSize: 12, height: 1.7, color: Palette.ink3),
          ),
        ),
      ]),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Palette.ink2)),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: Palette.bar, borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 50, color: Palette.line),
            children[i],
          ],
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, this.subtitle, this.value, this.valueWidget, this.trailing, this.onTap});

  final String icon;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? valueWidget;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              AppIcon(icon, size: 22, color: Palette.ink2),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: const TextStyle(fontSize: 15)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.ink3)),
                  ],
                ]),
              ),
              const SizedBox(width: 10),
              if (trailing != null)
                trailing!
              else ...[
                ?valueWidget,
                if (value != null) Text(value!, style: const TextStyle(fontSize: 13, color: Palette.ink2)),
                if (onTap != null) ...[const SizedBox(width: 4), const AppIcon('right', size: 16, color: Palette.ink3)],
              ],
            ]),
          ),
        ),
      );
}

/// 行内的小分段控件。
class _InlineSeg extends StatelessWidget {
  const _InlineSeg({required this.options, required this.selected, required this.onChanged});

  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: Palette.tonal, borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < options.length; i++)
            Semantics(
              selected: i == selected,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? Palette.bg : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: i == selected ? const [BoxShadow(color: Color(0x1F203028), blurRadius: 3, offset: Offset(0, 1))] : null,
                  ),
                  child: Text(options[i], style: TextStyle(fontSize: 12, color: i == selected ? Palette.ink : Palette.ink2, fontWeight: i == selected ? FontWeight.w600 : FontWeight.w400)),
                ),
              ),
            ),
        ]),
      );
}
