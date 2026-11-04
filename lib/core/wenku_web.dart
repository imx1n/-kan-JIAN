import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'wenku.dart';

/// 用一个看不见的 WebView 读源站页面。
///
/// 源站前面的 Cloudflare 会拦下 Dart 的 HTTP 客户端，但放行真实浏览器内核。被拦时
/// [WenkuService] 改用这里：页面由系统 WebView 正常加载（和用户自己打开网页一样），
/// 读回 `outerHTML` 交给原来的解析器。不移植验证 Cookie，也不做任何验证破解；
/// 如果浏览器内核也要人工验证，就超时报 [WenkuBlocked]，由界面打开可见的网页让用户自己过。
class WenkuWebFetcher implements WenkuWeb {
  WenkuWebFetcher._();

  static final instance = WenkuWebFetcher._();

  WebViewController? _c;
  Completer<String>? _pending;
  Future<void> _queue = Future.value();

  /// 有请求时才把 WebView 挂进界面树（1×1，不可见、不可点）。
  final active = ValueNotifier(false);

  WebViewController get _controller => _c ??= WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setUserAgent(WenkuService.userAgent)
    ..addJavaScriptChannel('PmxHtml', onMessageReceived: (m) => _onHtml(m.message))
    ..setNavigationDelegate(NavigationDelegate(
      onPageFinished: (_) => _c?.runJavaScript('PmxHtml.postMessage(document.documentElement.outerHTML)'),
      onWebResourceError: (e) {
        if (e.isForMainFrame ?? true) _pending?.completeError(WenkuWebError(e.description));
      },
    ));

  /// 挂在 App 根部的宿主。
  Widget host() => ValueListenableBuilder<bool>(
        valueListenable: active,
        builder: (_, on, _) => on
            ? IgnorePointer(child: SizedBox(width: 1, height: 1, child: Opacity(opacity: .01, child: WebViewWidget(controller: _controller))))
            : const SizedBox.shrink(),
      );

  /// Cloudflare 的验证页：浏览器内核会自己算完并跳回原页，这期间继续等。
  static bool _isChallenge(String html) {
    final head = html.length > 4000 ? html.substring(0, 4000) : html;
    return head.contains('<title>Just a moment') || head.contains('<title>请稍候') || head.contains('cf-chl-');
  }

  void _onHtml(String html) {
    final p = _pending;
    if (p == null || p.isCompleted || _isChallenge(html)) return;
    p.complete(html);
  }

  Future<String> _run(Uri url, {LoadRequestMethod method = LoadRequestMethod.get, Uint8List? body, Map<String, String> headers = const {}}) {
    final job = _queue.then((_) async {
      active.value = true;
      final done = _pending = Completer<String>();
      await _controller.loadRequest(url, method: method, body: body, headers: headers);
      try {
        return await done.future.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        throw const WenkuBlocked();
      } on WenkuWebError catch (e) {
        throw WenkuWebError(e.message);
      } finally {
        _pending = null;
      }
    });
    _queue = job.then((_) {}, onError: (_) {});
    return job;
  }

  @override
  Future<String> get(Uri url, {String? referer}) => _run(url, headers: {'Referer': ?referer});

  @override
  Future<String> post(Uri url, String formBody, {String? referer}) => _run(
        url,
        method: LoadRequestMethod.post,
        body: Uint8List.fromList(ascii.encode(formBody)),
        headers: {'Content-Type': 'application/x-www-form-urlencoded', 'Referer': ?referer},
      );

  @override
  Future<Map<String, String>> cookies() async {
    final list = await WebViewCookieManager().getCookies(domain: Uri.parse(WenkuService.base));
    return {for (final c in list) c.name: c.value};
  }
}
