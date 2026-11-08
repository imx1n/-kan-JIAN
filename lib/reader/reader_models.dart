import '../core/models.dart';

/// 一话的载入状态，照搬 Mihon 的 `ReaderChapter.State`（Apache-2.0）。
enum ChapterState { wait, loading, loaded, error }

/// 阅读器里的一话：原站 [Chapter] 加上它载入出来的页。
///
/// 和 [Chapter] 分开是因为同一话在阅读器里还有额外状态：是否正在载入、载入失败的
/// 原因、已载入的页列表。这些不属于数据模型本身。
///
/// [chapter] 可变：进阅读器时只有 uuid，先从上一话拿到占位，载入后原地补齐
/// （名字、序号、前后话），对象本身不换——视图里已经拿到的引用仍然有效。
class ReaderChapter {
  ReaderChapter(this.chapter);

  Chapter chapter;

  ChapterState state = ChapterState.wait;
  List<ReaderPage>? pages;
  String? error;

  /// 源站标记为付费 / 会员内容：不请求图片，直接给锁定页。
  bool locked = false;

  /// 进入这一话时要求停在第几页（0 基）。跨话接续时由上一话的位置推出来。
  int requestedPage = 0;

  String get uuid => chapter.uuid;
  String get name => chapter.name;
  bool get isLoaded => state == ChapterState.loaded;

  /// 载入完成后把内容补进这个对象（而不是新建一个），页对象里的 chapter 引用才不需要重接。
  void fill(Chapter loaded, List<String> images) {
    chapter = loaded;
    pages = [for (var i = 0; i < images.length; i++) ReaderPage(chapter: this, index: i, url: images[i])];
    state = ChapterState.loaded;
    error = null;
  }
}

/// 阅读器里的一页。[index] 是话内下标，[number] 是从 1 开始的页码。
class ReaderPage {
  const ReaderPage({required this.chapter, required this.index, required this.url});

  final ReaderChapter chapter;
  final int index;
  final String url;

  int get number => index + 1;
}

/// 跨话之间的分隔页。翻到它时既可能正在载入下一话，也可能是全书最后一页。
sealed class ChapterTransition {
  const ChapterTransition({required this.from, required this.to});

  /// 当前这一话。
  final ReaderChapter from;

  /// 要去的那一话；null 表示没有下一话（结尾）或没有上一话（开头）。
  final ReaderChapter? to;
}

/// 上一话末尾的过渡页。
class PrevTransition extends ChapterTransition {
  const PrevTransition({required super.from, required super.to});
}

/// 下一话开头的过渡页。
class NextTransition extends ChapterTransition {
  const NextTransition({required super.from, required super.to});
}

/// 当前、上一话、下一话三者的组合。阅读器每次重建都基于它，照搬 Mihon 的
/// `viewerItems`（Apache-2.0）。
class ViewerChapters {
  const ViewerChapters({required this.curr, this.prev, this.next});

  final ReaderChapter curr;
  final ReaderChapter? prev;
  final ReaderChapter? next;

  /// 阅读器的条目列表，顺序即阅读顺序：
  /// 上一话的页 → 上一话过渡页 → 当前话的页 → 下一话过渡页 → 下一话的页。
  ///
  /// 相邻话载入完成后过渡页就不再插入，两话的页直接接在一起——这就是
  /// 「翻到最后一页继续滑，直接进入下一话」的由来。反向阅读由视图反转顺序。
  List<Object> get items {
    final list = <Object>[];
    final p = prev;
    if (p?.pages != null) list.addAll(p!.pages!);
    if (p != null && !p.isLoaded) list.add(PrevTransition(from: curr, to: p));
    if (curr.pages != null) list.addAll(curr.pages!);
    // 即使没有下一话也放一张：它是「已经是最新一话」的收尾卡。
    if (next == null || !next!.isLoaded) list.add(NextTransition(from: curr, to: next));
    if (next?.pages != null) list.addAll(next!.pages!);
    return list;
  }

  /// [items] 里 [item] 的位置；不在列表里返回 -1。
  int indexOf(Object item) => items.indexOf(item);
}
