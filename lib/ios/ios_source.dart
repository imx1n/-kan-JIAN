import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';

import '../core/config.dart';
import '../core/routes.dart';
import '../core/store.dart';
import '../ui/icons.dart';
import 'ios_settings.dart' show SettingsPage;
import 'ios_theme.dart';

/// 「我的 → 数据源」：选线路，看每台主机的实测延迟，必要时填自建反代。
///
/// 默认「自动」：启动时把每条线路的域名都测一遍，用最快的那台。国内直连只有
/// `hotmangas` 那组通，Cloudflare 那两组一般要走代理，所以不让人手动猜。
class IosSourcePage extends StatefulWidget {
  const IosSourcePage({super.key, this.dio});

  /// 测试注入用；为空时现造一个。
  final Dio? dio;

  @override
  State<IosSourcePage> createState() => _IosSourcePageState();
}

class _IosSourcePageState extends State<IosSourcePage> {
  final _prefs = ReaderPrefs.instance;
  final _selector = RouteSelector.instance;
  Timer? _repaint;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_changed);
    _selector.addListener(_changed);
    _selector.probing.addListener(_changed);
    if (_selector.health.isEmpty) _probe();
    // 测速是并发请求，结果分几批回来；每 400ms 重画一次就够了。
    _repaint = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted && _selector.probing.value) setState(() {});
    });
  }

  @override
  void dispose() {
    _repaint?.cancel();
    _prefs.removeListener(_changed);
    _selector.removeListener(_changed);
    _selector.probing.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _probe() async {
    final dio = widget.dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          headers: AppConfig.apiHeaders,
        ));
    await _selector.probe(dio, all: _prefs.apiMode != 1);
    if (mounted) showIosToast(context, '测速完成');
  }

  Future<void> _editCustom() async {
    final v = await showIosPrompt(
      context,
      title: '自定义基址',
      message: '填自己的反代或中转地址，例如 https://api.example.com。留空则回到自动选择。',
      initial: _prefs.apiCustom,
      placeholder: 'https://',
    );
    if (v == null) return;
    final base = RouteSelector.normalizeBase(v);
    _prefs.apiCustom = base;
    _prefs.apiMode = base.isEmpty ? 0 : 2;
    _selector.reset();
    if (base.isNotEmpty) await _probe();
  }

  /// 「自动 / 固定 / 自定义」三选一。
  Future<void> _pickMode() async {
    final options = <String>['自动选择', '固定线路', '自定义基址'];
    final i = await showIosChoices(context, title: '线路模式', options: options, selected: _prefs.apiMode);
    if (i == null) return;
    if (i == 2 && RouteSelector.normalizeBase(_prefs.apiCustom).isEmpty) {
      await _editCustom();
      return;
    }
    _prefs.apiMode = i;
    _selector.reset();
    if (i != 2) await _probe();
  }

  String get _modeName => switch (_prefs.apiMode) {
        1 => '固定线路',
        2 => RouteSelector.normalizeBase(_prefs.apiCustom).isEmpty ? '自定义基址（未填）' : '自定义基址',
        _ => '自动选择',
      };

  /// 延迟文字：`269ms` / `超时` / `未测速`。
  (String, Color) _latency(String base) {
    final h = _selector.health[base];
    if (_selector.probing.value && h == null) return ('测速中', IosColors.muted);
    if (h?.cooling(DateTime.now()) ?? false) return ('超时', IosColors.accent);
    final ms = h?.latencyMs;
    if (ms == null) return ('未知', IosColors.muted);
    return ('$ms ms', ms <= 600 ? const Color(0xFF3E8E5A) : IosColors.muted);
  }

  @override
  Widget build(BuildContext context) {
    final active = _selector.activeBase;
    final (activeText, activeColor) = _latency(active);
    return SettingsPage(title: '数据源', children: [
      InsetGroup(
        title: '当前线路',
        footer: '作品与章节实时来自源站，本应用只做阅读器。',
        children: [
          IosRow(
            icon: 'globe',
            title: Uri.parse(active).host,
            subtitle: _selector.activeRouteName,
            chevron: false,
            valueWidget: _selector.probing.value
                ? const CupertinoActivityIndicator()
                : Text(activeText, style: TextStyle(fontSize: 15, color: activeColor)),
          ),
          IosRow(
            icon: 'refresh',
            title: '重新测速',
            subtitle: _selector.probing.value ? '正在并发测试各线路' : '测试每条线路的延迟',
            chevron: false,
            valueWidget: _selector.probing.value ? const CupertinoActivityIndicator() : null,
            onTap: _selector.probing.value ? null : _probe,
          ),
        ],
      ),
      InsetGroup(
        title: '选路方式',
        footer: '自动选择会在启动时把每条可用线路测一遍，用最快的那台；某台断开会自动换下一台并暂停它一分钟。'
            '国内网络通常只有「国内直连」这组可用。',
        children: [
          IosRow(title: '模式', value: _modeName, onTap: _pickMode),
          if (_prefs.apiMode == 2)
            IosRow(title: '自定义基址', value: RouteSelector.normalizeBase(_prefs.apiCustom).isEmpty ? '未填写' : RouteSelector.normalizeBase(_prefs.apiCustom), onTap: _editCustom),
        ],
      ),
      if (_prefs.apiMode != 2)
        for (final route in AppConfig.routes)
          InsetGroup(
            title: route.name,
            footer: route.note,
            children: [
              for (final base in route.hosts)
                _HostRow(
                  base: base,
                  selected: _prefs.apiMode == 1 && _selector.fixedRoute?.id == route.id,
                  active: base == active,
                  latency: _latency(base),
                  onTap: _prefs.apiMode != 1
                      ? null
                      : () {
                          _prefs.apiRoute = route.id;
                          _selector.reset();
                        },
                ),
            ],
          ),
      InsetGroup(
        title: '关于线路',
        footer: '线路由源站提供，应用不内置任何代理。若全部线路都不可用，可在上方填写自建的中转地址。',
        children: const [
          IosRow(icon: 'info', title: '应用不绕过付费与会员限制', chevron: false),
        ],
      ),
    ]);
  }
}

class _HostRow extends StatelessWidget {
  const _HostRow({required this.base, required this.selected, required this.active, required this.latency, this.onTap});

  final String base;
  final bool selected;
  final bool active;
  final (String, Color) latency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (text, color) = latency;
    return IosRow(
      title: Uri.parse(base).host,
      subtitle: active ? '正在使用' : null,
      chevron: false,
      onTap: onTap,
      valueWidget: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text, style: TextStyle(fontSize: 15, color: color)),
        if (selected) ...[const SizedBox(width: 8), AppIcon('check', size: 18, color: IosColors.accent, stroke: 2.2)],
      ]),
    );
  }
}
