import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'config.dart';
import 'store.dart';

/// GitHub Releases 上的一个版本。
class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.title,
    required this.notes,
    required this.pageUrl,
    this.packageUrl,
    this.packageSize,
    this.publishedAt,
  });

  /// 不带 v 的版本号，例如 `0.3.0`。
  final String version;
  final String tag;
  final String title;
  final String notes;
  final String pageUrl;

  /// 当前平台的安装包（Android 为 .apk，iOS 为 .ipa）。
  final String? packageUrl;
  final int? packageSize;
  final DateTime? publishedAt;

  /// 下载地址：有安装包附件就直接下载，否则打开 Release 页面。
  String get downloadUrl => packageUrl ?? pageUrl;

  /// 解析 `GET /repos/{owner}/{repo}/releases/latest` 的响应；不是合法版本号时返回 null。
  /// [ext] 为当前平台安装包的扩展名。
  static AppRelease? fromJson(Map<String, dynamic> j, {String ext = '.apk'}) {
    final tag = (j['tag_name'] ?? '').toString().trim();
    final version = normalizeVersion(tag);
    if (version == null) return null;
    final assets = (j['assets'] is List ? j['assets'] as List : const [])
        .whereType<Map>()
        .where((a) => (a['name'] ?? '').toString().toLowerCase().endsWith(ext))
        .toList();
    // 多个 APK 时优先通用包，其次 arm64（真机最常见）。
    assets.sort((a, b) => _apkRank(a['name'].toString()).compareTo(_apkRank(b['name'].toString())));
    final apk = assets.firstOrNull;
    return AppRelease(
      version: version,
      tag: tag,
      title: (j['name'] ?? '').toString().trim().isEmpty ? tag : j['name'].toString().trim(),
      notes: (j['body'] ?? '').toString().trim(),
      pageUrl: (j['html_url'] ?? AppConfig.githubPage).toString(),
      packageUrl: apk?['browser_download_url']?.toString(),
      packageSize: apk?['size'] is int ? apk!['size'] as int : null,
      publishedAt: DateTime.tryParse((j['published_at'] ?? '').toString())?.toLocal(),
    );
  }

  static int _apkRank(String name) {
    final n = name.toLowerCase();
    if (n.contains('universal') || !RegExp('arm|x86|x64').hasMatch(n)) return 0;
    if (n.contains('arm64')) return 1;
    return 2;
  }
}

enum UpdateStatus { available, upToDate, noRelease, failed }

class UpdateResult {
  const UpdateResult(this.status, {required this.current, this.release, this.message});

  final UpdateStatus status;
  final String current;
  final AppRelease? release;
  final String? message;
}

/// 从 tag 里取出 `主.次.修订` 版本号：`v0.3.0`、`0.3`、`release-1.2.0` 都可以；取不出返回 null。
String? normalizeVersion(String tag) {
  final m = RegExp(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?').firstMatch(tag);
  if (m == null) return null;
  return [m.group(1), m.group(2) ?? '0', m.group(3) ?? '0'].map((s) => int.parse(s!)).join('.');
}

/// 比较两个版本号：a > b 返回正数。忽略 `+build` 和预发布后缀。
int compareVersions(String a, String b) {
  List<int> parts(String v) => (normalizeVersion(v) ?? '0.0.0').split('.').map(int.parse).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] - y[i];
  }
  return 0;
}

class UpdateService {
  UpdateService._();

  static final instance = UpdateService._();

  /// 自动检查的最短间隔。
  static const autoInterval = Duration(hours: 24);

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'kanjian-reader'},
    // 404（还没有发布版本）和 403（限流）自己处理，不当作异常。
    validateStatus: (s) => s != null && s < 500,
  ));

  String? _current;

  Future<String> currentVersion() async => _current ??= (await PackageInfo.fromPlatform()).version;

  /// 测试里替换当前版本号。
  @visibleForTesting
  set currentForTest(String v) => _current = v;

  /// iOS 只认带 .ipa 附件的版本，避免把只发了 APK 的版本推给 iOS 用户。
  static bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  Future<UpdateResult> check() async {
    final current = await currentVersion();
    try {
      final res = await _dio.get<Object>(AppConfig.releasesApi);
      ReaderPrefs.instance.lastUpdateCheck = DateTime.now().millisecondsSinceEpoch;
      return resolve(res.statusCode ?? 0, res.data, current, ext: _ios ? '.ipa' : '.apk', requirePackage: _ios);
    } on DioException catch (e) {
      final msg = switch (e.type) {
        DioExceptionType.connectionTimeout || DioExceptionType.receiveTimeout => '连接 GitHub 超时，请检查网络或代理',
        _ => '无法连接 GitHub，请检查网络或代理',
      };
      return UpdateResult(UpdateStatus.failed, current: current, message: msg);
    }
  }

  /// 根据 HTTP 状态和响应体得出结论（单独拿出来便于测试）。
  /// [requirePackage] 为 true 时，新版本没有对应安装包就视为“已是最新”。
  static UpdateResult resolve(int status, Object? body, String current, {String ext = '.apk', bool requirePackage = false}) {
    if (status == 404) {
      return UpdateResult(UpdateStatus.noRelease, current: current, message: '仓库还没有发布版本');
    }
    if (status == 403 || status == 429) {
      return UpdateResult(UpdateStatus.failed, current: current, message: 'GitHub 请求太频繁，请过一会儿再试');
    }
    if (status != 200 || body is! Map) {
      return UpdateResult(UpdateStatus.failed, current: current, message: 'GitHub 返回异常（HTTP $status）');
    }
    final release = AppRelease.fromJson(Map<String, dynamic>.from(body), ext: ext);
    if (release == null) {
      return UpdateResult(UpdateStatus.failed, current: current, message: '最新 Release 的标签不是版本号');
    }
    final newer = compareVersions(release.version, current) > 0;
    if (newer && requirePackage && release.packageUrl == null) {
      return UpdateResult(UpdateStatus.upToDate, current: current, release: release, message: 'v${release.version} 还没有本平台的安装包');
    }
    return UpdateResult(newer ? UpdateStatus.available : UpdateStatus.upToDate, current: current, release: release);
  }

  /// 启动时自动检查：24 小时内只查一次；有新版本且没被跳过时返回结果，否则返回 null。
  Future<UpdateResult?> autoCheck() async {
    final prefs = ReaderPrefs.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - prefs.lastUpdateCheck < autoInterval.inMilliseconds) return null;
    final r = await check();
    if (r.status != UpdateStatus.available) return null;
    if (r.release!.version == prefs.skipVersion) return null;
    return r;
  }
}
