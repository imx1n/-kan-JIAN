import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/wenku.dart';
import 'ios_theme.dart';

/// 网页登录：直接打开源站登录页，用户自己输入账号密码。
///
/// 站点前面有 Cloudflare 的人机验证，纯请求过不去；用系统浏览器内核打开时，
/// 验证由浏览器自己完成，和平时上网一样。我们不自动破解验证。
/// 登录成功后从 WebView 读回 Cookie（`jieqiUserInfo` 是 HttpOnly，只有这里读得到）。
class WenkuWebLoginPage extends StatefulWidget {
  const WenkuWebLoginPage({super.key});

  @override
  State<WenkuWebLoginPage> createState() => _WenkuWebLoginPageState();
}

class _WenkuWebLoginPageState extends State<WenkuWebLoginPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(WenkuService.userAgent)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (url) {
          if (!mounted) return;
          setState(() => _loading = false);
          // 登录成功后源站会跳到会员页或书目页；回到首页时顺手试一次读取。
          if (!_saving && (url.contains('userdetail') || url.contains('bookcase') || url.contains('index.php'))) _grab(quiet: true);
        },
      ))
      ..loadRequest(Uri.parse('${WenkuService.base}/login.php'));
  }

  /// 从 WebView 读 Cookie 交给服务层校验。[quiet] 为 true 时失败不弹提示（用于自动探测）。
  Future<void> _grab({bool quiet = false}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      if (!quiet) _error = null;
    });
    try {
      final cookies = await WebViewCookieManager().getCookies(domain: Uri.parse(WenkuService.base));
      final map = {for (final c in cookies) c.name: c.value};
      await WenkuService.instance.importCookies(map);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = quiet ? null : '$e');
      if (!quiet) showIosToast(context, '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: IosColors.bg,
      body: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(top: top + 56, bottom: bottom),
            child: WebViewWidget(controller: _controller),
          ),
        ),
        Positioned(
          top: top + 4,
          left: 16,
          right: 16,
          child: SizedBox(
            height: 44,
            child: Stack(alignment: Alignment.center, children: [
              Text('登录轻小说账号', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: IosColors.ink)),
              Align(alignment: Alignment.centerLeft, child: GlassButton(icon: 'chevronLeft', label: '返回', onTap: () => Navigator.pop(context))),
            ]),
          ),
        ),
        if (_loading) const Positioned(top: 0, left: 0, right: 0, child: CupertinoActivityIndicator()),
        Positioned(
          left: 20,
          right: 20,
          bottom: bottom + 12,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: IosColors.accent)),
              ),
            Pressable(
              onTap: _saving ? null : _grab,
              semanticLabel: '已完成登录',
              child: Container(
                height: 50,
                decoration: BoxDecoration(color: IosColors.accent, borderRadius: BorderRadius.circular(25)),
                child: Center(
                  child: _saving
                      ? CupertinoActivityIndicator(color: IosColors.onAccent)
                      : Text('我已登录，读取凭证', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: IosColors.onAccent)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('在这个页面里登录源站，然后点上面的按钮。应用只保存登录凭证，不保存密码。',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, height: 1.4, color: IosColors.muted)),
          ]),
        ),
      ]),
    );
  }
}
