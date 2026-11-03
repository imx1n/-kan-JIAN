import 'package:flutter/foundation.dart';

import 'api.dart';
import 'store.dart';

/// 书架追更同步：逐部拉取详情，更新“最新话 / 章节数 / 连载状态”。
/// 默认 10 分钟内只同步一次；下拉刷新时强制同步。
class ShelfSync extends ChangeNotifier {
  ShelfSync._();

  static final instance = ShelfSync._();

  static const interval = Duration(minutes: 10);
  static const _concurrency = 3;

  bool running = false;
  String? lastError;

  /// 测试里关掉，避免发网络请求。
  @visibleForTesting
  static bool enabled = true;

  Future<void> refresh({bool force = false}) async {
    if (!enabled || running) return;
    final prefs = ReaderPrefs.instance;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - prefs.lastShelfSync < interval.inMilliseconds) return;
    final store = LibraryStore.instance;
    final ids = [for (final e in store.entries) if (e.kind == ShelfKind.manga) e.id];
    if (ids.isEmpty) return;

    running = true;
    lastError = null;
    notifyListeners();
    var next = 0, failed = 0, changed = 0;
    Future<void> worker() async {
      while (next < ids.length) {
        final id = ids[next++];
        try {
          final d = await MangaApi.instance.detail(id);
          store.applyRemote(d, notify: false);
          changed++;
        } catch (e) {
          failed++;
          lastError = e.toString();
        }
      }
    }

    await Future.wait([for (var i = 0; i < _concurrency; i++) worker()]);
    if (changed > 0) store.commit();
    // 全部失败时不记时间，下次打开书架还会重试。
    if (failed < ids.length) prefs.lastShelfSync = now;
    running = false;
    notifyListeners();
  }
}
