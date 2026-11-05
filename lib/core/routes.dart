import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'store.dart';

/// 一台主机的存活情况。
class HostHealth {
  HostHealth({this.latencyMs, this.checkedAt, this.coolUntil});

  /// 最近一次成功请求的耗时（毫秒）。
  int? latencyMs;
  DateTime? checkedAt;

  /// 网络层失败后暂停使用到什么时候。
  DateTime? coolUntil;

  bool cooling(DateTime now) => coolUntil != null && coolUntil!.isAfter(now);
}

/// 线路选择：按用户偏好给出主机的尝试顺序，并记住测速与失败。
///
/// 三种模式（[ReaderPrefs.apiMode]）：
/// - 自动：启动时把每条线路的域名都测一遍，从最快的那台开始；
/// - 固定：只用用户选的线路；
/// - 自定义：只用自己的基址（自建反代）。
///
/// 选路刻意不做「按权重随机」：实测每台主机首包 1.4–2s、之后 270ms，
/// 随机等于每个请求都重付一次 TLS 握手。粘住最快的一台才划算。
class RouteSelector extends ChangeNotifier {
  RouteSelector._();

  static final instance = RouteSelector._();

  final health = <String, HostHealth>{};

  /// 测速进行中，界面用来显示转圈。
  final probing = ValueNotifier<bool>(false);

  final _prefs = ReaderPrefs.instance;

  ApiRoute? get fixedRoute {
    final id = _prefs.apiRoute;
    for (final r in AppConfig.routes) {
      if (r.id == id) return r;
    }
    return AppConfig.routes.first;
  }

  /// 某个基址属于哪条线路；自定义基址返回 null。
  ApiRoute? routeOf(String base) {
    for (final r in AppConfig.routes) {
      if (r.hosts.contains(base)) return r;
    }
    return null;
  }

  /// 当前正在用的线路名：自定义基址为「自定义」，否则是对应线路。
  String get activeRouteName {
    if (usingCustom) return '自定义';
    return routeOf(activeBase)?.name ?? '自动';
  }

  /// 自定义基址规范化：补 `https://`、去掉末尾斜杠。空串表示没填。
  static String normalizeBase(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return '';
    if (!v.startsWith('http://') && !v.startsWith('https://')) v = 'https://$v';
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  bool get usingCustom => _prefs.apiMode == 2 && normalizeBase(_prefs.apiCustom).isNotEmpty;

  /// 当前模式下的全部候选基址（未排序）。
  List<String> get pool {
    if (usingCustom) return [normalizeBase(_prefs.apiCustom)];
    if (_prefs.apiMode == 1) return [...fixedRoute!.hosts];
    return [for (final r in AppConfig.routes) ...r.hosts];
  }

  /// 按「直连可用 → 其它可用 → 未测速 → 冷却中」排序，同级按实测延迟升序。
  ///
  /// 直连线路优先不是拍脑袋：宿主机实测国内直连 `mapi.hotmangas*.com` 40/40 通
  /// （中位 269ms），Cloudflare 那两组 0–4/5、常 15–30s 超时。模拟器里 CF 有时
  /// 也能 400ms 返回，但那是模拟器的网络出口不同，不代表真机；所以只要直连线路
  /// 还活着就用它，全灭（冷却）才退到 CF。
  List<String> candidates() {
    final now = DateTime.now();
    final order = {for (final (i, h) in pool.indexed) h: i};
    int rank(String h) {
      final s = health[h];
      if (s == null) return 2;
      if (s.cooling(now)) return 3;
      if (s.latencyMs == null) return 2;
      return routeOf(h)?.direct ?? false ? 0 : 1;
    }

    final list = [...pool]..sort((a, b) {
        final d = rank(a) - rank(b);
        if (d != 0) return d;
        final la = health[a]?.latencyMs ?? 1 << 30;
        final lb = health[b]?.latencyMs ?? 1 << 30;
        if (la != lb) return la - lb;
        return (order[a] ?? 0) - (order[b] ?? 0);
      });
    return list;
  }

  /// 下次请求会用的基址；没有可用项时返回第一台（让它去试一次）。
  String get activeBase => candidates().first;

  String get activeHost => Uri.parse(activeBase).host;

  void reportSuccess(String base, int ms) {
    health[base] = HostHealth(latencyMs: ms, checkedAt: DateTime.now());
    notifyListeners();
  }

  /// 网络层失败：这台冷却 60 秒，不永久拉黑。
  void reportFailure(String base) {
    final h = health.putIfAbsent(base, HostHealth.new);
    h.coolUntil = DateTime.now().add(const Duration(seconds: 60));
    notifyListeners();
  }

  void reset() {
    health.clear();
    notifyListeners();
  }

  /// 并发测速。每台测两轮，取第二轮（第一轮在付 TLS 冷启动的钱）。
  ///
  /// 只在「自动」模式或用户主动点测速时调用；固定/自定义模式下测速只更新
  /// 界面上的延迟数字，不改变用户的选择。
  Future<void> probe(Dio? dio, {bool all = true}) async {
    if (probing.value) return;
    probing.value = true;
    notifyListeners();
    final targets = all ? {for (final r in AppConfig.routes) ...r.hosts} : pool.toSet();
    try {
      await _round(dio, targets.toList());
      await _round(dio, targets.toList());
    } finally {
      probing.value = false;
      notifyListeners();
    }
  }

  Future<void> _round(Dio? dio, List<String> hosts) async {
    if (dio == null) return;
    await Future.wait(hosts.map((base) async {
      final sw = Stopwatch()..start();
      try {
        final res = await dio.get<Object>(
          '$base/api/v3/comics',
          queryParameters: const {'limit': 1, 'offset': 0, 'platform': 3, 'region': 0},
          options: Options(receiveTimeout: const Duration(seconds: 6), validateStatus: (s) => s != null && s < 500),
        );
        final body = res.data is String ? jsonDecode(res.data as String) : res.data;
        if (body is Map && body['results'] is Map) {
          health[base] = HostHealth(latencyMs: sw.elapsedMilliseconds, checkedAt: DateTime.now());
        } else {
          health[base] = HostHealth(coolUntil: DateTime.now().add(const Duration(minutes: 5)));
        }
      } catch (_) {
        health[base] = HostHealth(coolUntil: DateTime.now().add(const Duration(seconds: 60)));
      }
    }));
    notifyListeners();
  }
}
