import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/models.dart';
import 'reader_models.dart';

/// 阅读器的数据层：管当前话、上一话、下一话的载入与预载。
///
/// 照搬 Mihon 的 `ReaderViewModel` 里和阅读直接相关的部分（Apache-2.0）：维护一个
/// 「当前 ± 相邻一话」的三话窗口，进入时就把两侧排进预载。翻到话尾时不用等网络，
/// 因为两话的页在视图里本来就是连续的一条。
class ReaderController extends ChangeNotifier {
  ReaderController({required this.pathWord, required this.group});

  final String pathWord;
  final String group;

  ReaderChapter? _curr;
  ReaderChapter? _prev;
  ReaderChapter? _next;

  /// 按 uuid 缓存，来回翻时复用，不重复请求。
  final _cache = <String, ReaderChapter>{};

  /// 正在请求的 uuid，避免同一话并发请求两次。
  final _inflight = <String>{};

  bool _disposed = false;

  /// 当前阅读位置：话内页下标。
  int pageIndex = 0;

  /// 请求跳到某一页（话内下标）。ReaderView 消费后置回 null。
  /// 用 ValueNotifier 而不是回调，是因为跳转可能在 widget 还没建好时发出。
  final seek = ValueNotifier<int?>(null);

  /// 正在把上次的位置恢复出来。
  ///
  /// 条漫是懒构建的，`initialScrollOffset` 会在首帧被 `maxScrollExtent`
  /// 夹回前几页；恢复只能靠「逐帧往下推、直到目标条目被建出来」。
  /// 这个过程里视口中线扫过的页**不是**用户读到的页，所以这段时间
  /// 必须禁止 adopt 和写盘，否则错误位置会把真实进度覆盖掉。
  bool restoring = false;

  ReaderChapter? get current => _curr;
  ReaderChapter? get previous => _prev;
  ReaderChapter? get next => _next;

  /// 首次载入中（当前话还没有页，也没出错）。
  bool get loading => _curr != null && _curr!.pages == null && _curr!.state != ChapterState.error;

  String? get error => _curr?.error;
  bool get locked => _curr?.locked ?? false;

  ViewerChapters? get chapters => _curr == null ? null : ViewerChapters(curr: _curr!, prev: _prev, next: _next);

  @override
  void dispose() {
    seek.dispose();
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 进入某一话。已在缓存里的立即切换，否则先占位再载入。
  Future<void> open(String uuid, {int page = 0}) async {
    final cached = _cache[uuid];
    if (cached != null && cached.isLoaded) {
      _curr = cached;
      pageIndex = page;
    } else {
      _curr = cached ?? (_cache[uuid] = ReaderChapter(Chapter(uuid: uuid, name: '', index: 0, size: 0, groupPathWord: group)));
      pageIndex = page;
      _notify();
      await _load(_curr!);
      if (_disposed || !identical(_curr, cached ?? _curr)) return;
    }
    _curr!.requestedPage = page;
    _rebuildWindow();
    _notify();
  }

  /// 阅读中翻到了相邻话（跨话接续时调用）。
  ///
  /// 不重新请求：预载好的那一话直接成为当前话，窗口整体平移一格。
  void promote(ReaderChapter target, {int page = 0}) {
    if (identical(target, _curr)) return;
    _curr = target;
    pageIndex = page;
    _rebuildWindow();
    _notify();
  }

  /// 回到当前话的某一页（目录跳转、回到本话开头）。
  void setPage(int index) {
    pageIndex = index;
    _notify();
  }

  /// 请求阅读区跳到第 [index] 页。
  void jumpTo(int index) => seek.value = index;

  /// 以当前话为中心重建「当前 ±1」三话窗口。
  void _rebuildWindow() {
    final curr = _curr;
    if (curr == null) return;
    _prev = _neighborOf(curr.chapter.prev);
    _next = _neighborOf(curr.chapter.next);
    _evictFar(curr);
    unawaited(_preloadNeighbors());
  }

  ReaderChapter? _neighborOf(String? uuid) {
    if (uuid == null) return null;
    return _cache[uuid] ??= ReaderChapter(Chapter(uuid: uuid, name: '', index: 0, size: 0, groupPathWord: group));
  }

  /// 预载窗口里还没载入的话。串行发送，避免一次打出两个请求。
  Future<void> _preloadNeighbors() async {
    for (final ch in [_prev, _next]) {
      if (_disposed) return;
      if (ch == null || ch.isLoaded || _inflight.contains(ch.uuid)) continue;
      await _load(ch);
      // 预载完成后把过渡页换掉（过渡页 → 实际页），需要重画。
      _notify();
    }
  }

  Future<void> _load(ReaderChapter ch) async {
    if (_inflight.contains(ch.uuid) || ch.isLoaded) return;
    _inflight.add(ch.uuid);
    ch
      ..state = ChapterState.loading
      ..error = null;
    if (identical(ch, _curr)) _notify();
    try {
      final c = await MangaApi.instance.chapter(pathWord, ch.uuid);
      if (_disposed) return;
      // 原地补齐：视图里已经拿到的引用仍然有效。
      ch.fill(c.chapter, c.images);
      ch.locked = c.isLock;
    } catch (e) {
      if (_disposed) return;
      ch
        ..state = ChapterState.error
        ..error = e.toString();
    } finally {
      _inflight.remove(ch.uuid);
      if (!_disposed) _notify();
    }
  }

  /// 缓存里只留当前 ±1，其余释放页，避免长集数读下来内存堆积。
  void _evictFar(ReaderChapter curr) {
    final keep = <String>{curr.uuid};
    if (curr.chapter.prev != null) keep.add(curr.chapter.prev!);
    if (curr.chapter.next != null) keep.add(curr.chapter.next!);
    _cache.removeWhere((uuid, ch) {
      if (keep.contains(uuid)) return false;
      ch
        ..pages = null
        ..state = ChapterState.wait;
      return false;
    });
  }

  /// 错误页上的重试：清掉当前话的状态重新载入。
  Future<void> retry() async {
    final curr = _curr;
    if (curr == null) return;
    curr
      ..state = ChapterState.wait
      ..error = null
      ..pages = null;
    _notify();
    await _load(curr);
    if (_disposed) return;
    _rebuildWindow();
    _notify();
  }

  /// 重试某一话（跨话过渡页上的「重试」按钮用）。
  Future<void> retryChapter(ReaderChapter ch) async {
    ch
      ..state = ChapterState.wait
      ..error = null
      ..pages = null;
    _notify();
    await _load(ch);
  }
}
