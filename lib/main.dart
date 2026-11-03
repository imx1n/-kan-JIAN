import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/store.dart';
import 'ios/ios_app.dart';
import 'pages/home_shell.dart';
import 'ui/theme.dart';

/// iOS 用 iOS 26 设计稿的界面，其余平台用安卓（Material 3）界面。
/// `--dart-define=FORCE_IOS_UI=true` 可以在安卓设备上预览 iOS 界面。
bool get useIosUi => defaultTargetPlatform == TargetPlatform.iOS || const bool.fromEnvironment('FORCE_IOS_UI');

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
  if (useIosUi) {
    runApp(const IosApp());
    return;
  }
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
