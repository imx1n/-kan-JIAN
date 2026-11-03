import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/store.dart';
import 'pages/home_shell.dart';
import 'ui/theme.dart';

/// 让 dio 与图片加载（dart:io HttpClient）统一走代理，失败时回退直连。
class _ProxyOverrides extends HttpOverrides {
  _ProxyOverrides(this.proxy);

  final String proxy;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'PROXY $proxy; DIRECT';
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initStores();
  final proxy = ReaderPrefs.instance.proxy;
  if (proxy.isNotEmpty) HttpOverrides.global = _ProxyOverrides(proxy);
  // 界面按竖屏手机设计。
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Palette.bar,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const ShioriApp());
}

class ShioriApp extends StatelessWidget {
  const ShioriApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '栞间',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const HomeShell(),
      );
}
