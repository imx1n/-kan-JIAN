import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/account.dart';
import '../core/api.dart';
import '../core/config.dart';
import '../core/store.dart';
import '../core/update_service.dart';
import '../ui/format.dart' show formatBytes;
import '../ui/icons.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart' show Dock, Space;
import 'ios_account.dart';
import 'ios_app.dart';
import 'ios_settings.dart';
import 'ios_source.dart';
import 'ios_theme.dart';

/// 修改网络代理。默认「跟随系统」：系统 VPN 类代理会自动生效；需要 HTTP 代理时再填 host:port。
Future<void> iosEditProxy(BuildContext context) async {
  final prefs = ReaderPrefs.instance;
  final v = await showIosPrompt(
    context,
    title: '网络代理',
    message: '留空即跟随系统（VPN 类代理自动生效）。需要 HTTP 代理时填写 host:port，重启应用后生效。',
    initial: prefs.proxy,
    placeholder: '例如 192.168.1.10:7890',
    confirm: '保存',
  );
  if (v == null) return;
  prefs.proxy = v;
  if (context.mounted) showIosToast(context, '已保存，重启应用后生效');
}

/// 「我的」：母项列表。每项点进去才是子项，一屏只留一件事，
/// 不再把外观、阅读、网络、存储、关于全铺在同一页上。
class IosMinePage extends StatefulWidget {
  const IosMinePage({super.key});

  @override
  State<IosMinePage> createState() => _IosMinePageState();
}

class _IosMinePageState extends State<IosMinePage> {
  final _prefs = ReaderPrefs.instance;
  final _store = LibraryStore.instance;
  final _account = AccountService.instance;
  String? _ping;
  bool _pingOk = false;
  bool _pinging = false;
  DateTime? _pingedAt;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_changed);
    _store.addListener(_changed);
    _account.addListener(_changed);
    IosShell.tab.addListener(_onTab);
  }

  @override
  void dispose() {
    _prefs.removeListener(_changed);
    _store.removeListener(_changed);
    _account.removeListener(_changed);
    IosShell.tab.removeListener(_onTab);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onTab() {
    if (IosShell.tab.value != 2) return;
    if (_pingedAt == null || DateTime.now().difference(_pingedAt!) > const Duration(minutes: 1)) _testSource();
  }

  Future<void> _testSource() async {
    if (_pinging) return;
    setState(() => _pinging = true);
    try {
      final d = await MangaApi.instance.ping();
      _ping = '${d.inMilliseconds}ms';
      _pingOk = true;
    } catch (_) {
      _ping = '连接失败';
      _pingOk = false;
    }
    _pingedAt = DateTime.now();
    if (mounted) setState(() => _pinging = false);
  }

  void _open(Widget page) => Navigator.of(context).push(appRoute<void>((_) => page));

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, bottom: Dock.clearance(context)),
      children: [
        const LargeTitle('我的'),
        _syncCard(),
        InsetGroup(children: [
          IosRow(icon: 'book', title: '阅读器', subtitle: '翻页方式、手势分区、画质、小说排版', onTap: () => _open(const IosReadingSettingsPage())),
          IosRow(
            icon: 'database',
            title: '内容源',
            subtitle: '线路、代理与实测延迟',
            valueWidget: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_pinging)
                const CupertinoActivityIndicator()
              else if (_ping != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: _pingOk ? const Color(0xFF3E8E5A) : IosColors.accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              if (_ping != null)
                Text(_ping!, style: TextStyle(fontSize: 15, color: _pingOk ? IosColors.muted : IosColors.accent)),
            ]),
            onTap: () => _open(const IosSourcePage()),
          ),
          IosRow(icon: 'palette', title: '外观', subtitle: '深色模式、透明度、封面效果', onTap: () => _open(const IosAppearancePage())),
          IosRow(
            icon: 'history',
            title: '数据管理',
            subtitle: '书架 ${_store.entries.length} 部 · 已读 ${_store.readChapterCount} 话',
            onTap: () => _open(const IosDataPage()),
          ),
        ]),
        InsetGroup(children: [
          IosRow(icon: 'info', title: '关于 栞间', onTap: () => _open(const IosAboutPage())),
        ]),
      ],
    );
  }

  /// 云同步卡：登录拷贝漫画账号，书架与阅读进度在设备间同步。
  Widget _syncCard() {
    final loggedIn = _account.loggedIn;
    final busy = _account.busy;
    return Container(
      // 下边距交给下面的 InsetGroup：它自己会补 [Space.beforeSection]，
      // 这里再留一段就是两段叠在一起。
      margin: const EdgeInsets.fromLTRB(Space.page, Space.x1, Space.page, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: IosColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon('cloud', size: 22, color: IosColors.muted, stroke: 1.6),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(loggedIn ? '已同步' : '云同步', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: IosColors.ink)),
              const SizedBox(height: 3),
              Text(
                loggedIn ? '已登录 ${_account.displayName}，书架与阅读进度会在设备间同步。' : '登录拷贝漫画账号，在设备间同步你的书架和阅读进度。',
                style: TextStyle(fontSize: 13, height: 1.45, color: IosColors.muted),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Pressable(
          onTap: busy ? null : () => _open(const IosAccountPage()),
          dimWhenDisabled: true,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: IosColors.faint, borderRadius: BorderRadius.circular(12)),
            child: busy
                ? const CupertinoActivityIndicator()
                : Text(
                    loggedIn ? '管理账号' : '登录拷贝漫画',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: IosColors.ink),
                  ),
          ),
        ),
      ]),
    );
  }
}

/// 数据管理：图片缓存占用与清理、阅读记录。存储配额等以后再做。
class IosDataPage extends StatefulWidget {
  const IosDataPage({super.key});

  @override
  State<IosDataPage> createState() => _IosDataPageState();
}

class _IosDataPageState extends State<IosDataPage> {
  final _store = LibraryStore.instance;
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _measureCache();
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _measureCache() async {
    var total = 0;
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/${DefaultCacheManager.key}');
      if (await dir.exists()) {
        await for (final f in dir.list(recursive: true, followLinks: false)) {
          if (f is File) total += await f.length();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _cacheBytes = total);
  }

  Future<void> _cacheMenu() async {
    final i = await showIosChoices(
      context,
      title: '图片缓存 ${_cacheBytes == null ? '' : formatBytes(_cacheBytes!)}',
      options: const ['清除图片缓存'],
      destructiveIndex: 0,
    );
    if (i != 0) return;
    await DefaultCacheManager().emptyCache();
    imageCache.clear();
    await _measureCache();
    if (mounted) showIosToast(context, '图片缓存已清除');
  }

  Future<void> _clearHistory() async {
    final ok = await showAppConfirm(
      context,
      title: '清除阅读记录？',
      message: '会清掉每部作品读到哪一页和已读标记。书架上的作品和追更状态会保留。',
      confirm: '清除',
      destructive: true,
    );
    if (ok) _store.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: '数据管理', children: [
      InsetGroup(
        title: '存储',
        footer: '图片缓存只保存看过的页面，随时可以清；清掉不影响书架和阅读进度。',
        children: [
          IosRow(
            icon: 'database',
            title: '图片缓存',
            subtitle: '只保存看过的页面',
            value: _cacheBytes == null ? '—' : formatBytes(_cacheBytes!),
            onTap: _cacheMenu,
          ),
          IosRow(
            icon: 'history',
            title: '阅读记录',
            subtitle: '书架 ${_store.entries.length} 部 · 已读 ${_store.readChapterCount} 话',
            valueWidget: Text('清除', style: TextStyle(fontSize: 15, color: IosColors.accent)),
            chevron: false,
            onTap: _clearHistory,
          ),
        ],
      ),
    ]);
  }
}

/// 关于：版本、检查更新、自动检查、项目主页。
class IosAboutPage extends StatefulWidget {
  const IosAboutPage({super.key});

  @override
  State<IosAboutPage> createState() => _IosAboutPageState();
}

class _IosAboutPageState extends State<IosAboutPage> {
  final _prefs = ReaderPrefs.instance;
  String _version = '';
  bool _checking = false;
  UpdateResult? _update;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_changed);
    UpdateService.instance.currentVersion().then((v) {
      if (mounted) setState(() => _version = v);
    });
  }

  @override
  void dispose() {
    _prefs.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final r = await iosManualUpdateCheck(context);
    if (mounted) {
      setState(() {
        _checking = false;
        _update = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(title: '关于 栞间', children: [
      InsetGroup(
        footer: '栞间只是阅读器：不内置账号，不绕过付费与会员限制。作品实时来自源站，版权归原作者和权利人所有。',
        children: [
          IosRow(
            icon: 'download',
            title: '检查更新',
            subtitle: '当前 v$_version · GitHub Releases',
            valueWidget: _checking
                ? const CupertinoActivityIndicator()
                : Text(
                    switch (_update?.status) {
                      UpdateStatus.available => 'v${_update!.release!.version}',
                      UpdateStatus.upToDate => '已是最新',
                      UpdateStatus.noRelease => '暂无发布',
                      UpdateStatus.failed => '检查失败',
                      null => '',
                    },
                    style: TextStyle(
                      fontSize: 15,
                      color: _update?.status == UpdateStatus.available || _update?.status == UpdateStatus.failed ? IosColors.accent : IosColors.muted,
                    ),
                  ),
            onTap: _checking ? null : _checkUpdate,
          ),
          IosRow(
            title: '启动时自动检查',
            subtitle: '每次打开应用检查一次，可随时关闭',
            chevron: false,
            valueWidget: AppSwitch(value: _prefs.autoUpdate, onChanged: (v) => setState(() => _prefs.autoUpdate = v)),
            onTap: () => setState(() => _prefs.autoUpdate = !_prefs.autoUpdate),
          ),
          IosRow(
            icon: 'github',
            title: '项目主页',
            subtitle: AppConfig.githubPage.replaceFirst('https://', ''),
            onTap: () => launchUrl(Uri.parse(AppConfig.githubPage), mode: LaunchMode.externalApplication),
          ),
        ],
      ),
    ]);
  }
}
