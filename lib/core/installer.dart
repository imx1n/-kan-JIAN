import 'dart:io';

import 'package:flutter/services.dart';

/// 调起系统安装器（Android）。iOS 上不支持，直接返回 false 让调用方退回浏览器下载。
class AppInstaller {
  AppInstaller._();

  static const _channel = MethodChannel('pmx/installer');

  /// 这台设备能不能应用内安装（目前只有 Android 有）。
  static Future<bool> get supported async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('canInstall');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// 打开系统安装器。
  ///
  /// 返回 true 表示安装界面已经弹出；false 表示没有「安装未知应用」权限，
  /// 已经帮用户跳到了授权页，回来再点一次即可。
  static Future<bool> install(String path) async {
    if (!Platform.isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('install', {'path': path});
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
