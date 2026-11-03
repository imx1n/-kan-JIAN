import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/store.dart';
import '../ui/widgets.dart';

/// 修改网络代理（重启后生效）。
Future<void> showProxyEditor(BuildContext context) async {
  final prefs = ReaderPrefs.instance;
  final v = await showTextPrompt(
    context,
    title: '网络代理',
    initial: prefs.proxy,
    hint: '例如 10.0.2.2:7897，留空为直连',
    help: 'MuMu 等模拟器里，10.0.2.2 指向电脑本机。修改后需要重启应用才会生效。',
    confirmLabel: '保存',
  );
  if (v == null) return;
  prefs.proxy = v;
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，重启应用后生效')));
  }
}

/// 列表首屏加载失败时的错误面板，带上最近一次请求的诊断信息。
class ApiErrorPanel extends StatelessWidget {
  const ApiErrorPanel({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final diag = MangaApi.instance.lastError.value;
    return ErrorPanel(
      message: message,
      onRetry: onRetry,
      onProxy: () => showProxyEditor(context),
      host: diag?.host ?? Uri.parse(MangaApi.instance.activeHost).host,
      proxy: ReaderPrefs.instance.proxy,
      failedAt: diag?.at,
    );
  }
}
