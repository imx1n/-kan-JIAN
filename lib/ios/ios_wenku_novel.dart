import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart' show ApiException;
import '../core/store.dart';
import '../core/wenku.dart';
import '../core/wenku_models.dart';
import '../ui/icons.dart';
import '../ui/motion.dart';
import '../ui/novel_body.dart';
import '../ui/novel_pages.dart';
import 'ios_catalog.dart';
import 'ios_novel.dart' show novelBodyStyle, novelPaperColors, showNovelAppearance;
import 'ios_theme.dart';
import 'ios_wenku.dart' show WenkuShelfButton, openWenkuLogin;

/// 真实轻小说阅读页：目录、正文都来自源站，排版沿用「阅读设置」里的纸张、字号、行距。
///
/// 未登录也能看目录；正文需要登录，没登录时给出去登录的入口。
class IosWenkuNovelPage extends StatefulWidget {
  const IosWenkuNovelPage({super.key, required this.aid, this.name = ''});

  final int aid;
  final String name;

  @override
  State<IosWenkuNovelPage> createState() => _IosWenkuNovelPageState();
}

class _IosWenkuNovelPageState extends State<IosWenkuNovelPage> {
  final _svc = WenkuService.instance;
  final _store = LibraryStore.instance;
  final _prefs = ReaderPrefs.instance;
  final _bodyKey = GlobalKey<NovelBodyState>();

  WenkuCatalog? _catalog;
  String _title = '';
  String _author = '';
  int _index = 0;
  WenkuContent? _content;
  bool _loading = true;
  bool _chrome = true;
  double _progress = 0;
  int _page = 1;
  int _pages = 1;
  String? _error;
  bool _needLogin = false;

  @override
  void initState() {
    super.initState();
    _title = widget.name;
    _load();
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(pageChrome);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await _svc.catalog(widget.aid);
      _title = r.book.name.isEmpty ? _title : r.book.name;
      _author = r.book.author;
      // 恢复上次读到的章节；本地记的是章节名和序号，按序号定位最准。
      final e = _store.entry(wenkuIdOf(widget.aid));
      final saved = e?.chapterIndex;
      _index = (saved != null && saved >= 0 && saved < r.catalog.chapters.length) ? saved : 0;
      setState(() {
        _catalog = r.catalog;
        _loading = false;
      });
      await _loadChapter(_index, restore: true);
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _loadChapter(int index, {bool restore = false}) async {
    final c = _catalog;
    if (c == null || index < 0 || index >= c.chapters.length) return;
    final ch = c.chapters[index];
    setState(() {
      _index = index;
      _loading = true;
      _error = null;
      _needLogin = false;
    });
    try {
      final content = await _svc.content(aid: c.aid, cls: c.cls, cid: ch.cid);
      if (!mounted) return;
      final e = _store.entry(wenkuIdOf(c.aid));
      setState(() {
        _content = content;
        _loading = false;
        _page = 1;
        _pages = 1;
        // 只有「恢复上次阅读」才跳到上次的位置，手动翻章从头开始。
        _progress = restore && e != null && e.chapterIndex == index ? e.progress : 0;
      });
      _saveProgress(restore: restore);
    } on WenkuNeedLogin catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _needLogin = true;
        _error = e.message;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// 记下本章读到哪一页。[restore] 只是用来区分「恢复上次位置」和普通保存，
  /// 两者都要存当前百分比——之前这里写成 `restore ? _progress : 0`，
  /// 结果每翻一页都把进度清成 0，退出后再打开永远从第一页开始。
  void _saveProgress({bool restore = false}) {
    final c = _catalog;
    if (c == null || _content == null) return;
    final ch = c.chapters[_index];
    _store.recordPosition(
      id: wenkuIdOf(c.aid),
      create: () => ShelfEntry(
        id: wenkuIdOf(c.aid),
        kind: ShelfKind.novel,
        name: _title,
        cover: WenkuBook.coverOf(c.aid),
        author: _author,
        // 只读不进书架：和漫画一样，点「加入书架」才算收藏。
        followed: false,
        updatedAt: 0,
      ),
      chapterUuid: '${ch.cid}',
      chapterName: ch.name,
      chapterIndex: _index,
      group: '${c.cls}',
      progress: _progress,
    );
  }

  /// 本章书签：按书号存进偏好，关掉页面再打开还在。
  String get _bookmarkKey => 'wenku-${widget.aid}';
  bool get _marked => _prefs.isBookmarked(_bookmarkKey, _index);

  void _toggleBookmark() {
    final on = _prefs.toggleBookmark(_bookmarkKey, _index);
    setState(() {});
    HapticFeedback.selectionClick();
    showIosToast(context, on ? '已为本章添加书签' : '已取消本章书签', dark: novelPaperColors(_prefs.theme).dark);
  }

  /// 分卷目录页；选中章节后跳过去。
  Future<void> _toc() async {
    final c = _catalog;
    if (c == null) return;
    final sections = <NovelTocSection>[
      for (final v in c.volumes)
        if (v.chapters.isNotEmpty)
          NovelTocSection(name: v.name, entries: [for (final ch in v.chapters) NovelTocEntry(index: ch.index, name: ch.name)]),
      // 目录里没有卷标记时，源站返回的章节会被归到第 0 卷，这里兜住。
      if (c.volumes.isEmpty)
        NovelTocSection(name: '全部章节', entries: [for (final ch in c.chapters) NovelTocEntry(index: ch.index, name: ch.name)]),
    ];
    final i = await showIosCatalog(
      context,
      sections: sections,
      currentIndex: _index,
      title: _title,
      bookmarkKey: _bookmarkKey,
    );
    if (i != null && i != _index) _goChapter(i);
  }

  void _goChapter(int index) {
    _progress = 0;
    _page = 1;
    _pages = 1;
    _loadChapter(index);
  }

  /// 章节小标题：`第一卷 · 第 3 章`；没有分卷时退化为全书序号。
  String _chapterLabel(WenkuCatalog c, WenkuChapter ch) {
    if (ch.volume < c.volumes.length) {
      final v = c.volumes[ch.volume];
      final n = v.chapters.indexOf(ch) + 1;
      return '${v.name} · 第 $n 章';
    }
    return '第 ${_index + 1} 章 / 共 ${c.chapters.length} 章';
  }

  Future<void> _login() async {
    final ok = await openWenkuLogin(context);
    if (ok == true && mounted) await _loadChapter(_index);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _prefs,
    builder: (context, _) {
      final colors = novelPaperColors(_prefs.theme);
      SystemChrome.setSystemUIOverlayStyle(colors.dark ? kDarkChrome : kLightChrome);
      final top = MediaQuery.paddingOf(context).top;
      final bottom = MediaQuery.paddingOf(context).bottom;
      final c = _catalog;
      final total = c?.chapters.length ?? 0;
      return PopScope(
        onPopInvokedWithResult: (_, _) => _saveProgress(),
        child: Scaffold(
          backgroundColor: colors.bg,
          body: Stack(
            children: [
              Positioned.fill(child: _body(colors, top, bottom)),
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(color: Colors.black.withValues(alpha: (1 - _prefs.brightness) * .7)),
                ),
              ),
              // 顶栏下面垫一层纸色渐隐，书名和按钮不直接压在正文上。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: top + 76,
                child: ChromeReveal(
                  visible: _chrome,
                  dy: -8,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          stops: const [0, .72, 1],
                          colors: [colors.bg, colors.bg.withValues(alpha: .92), colors.bg.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: top + 4,
                left: 16,
                right: 16,
                child: ChromeReveal(
                  visible: _chrome,
                  dy: -8,
                  child: Row(
                    children: [
                      GlassButton(icon: 'chevronLeft', label: '返回', dark: colors.dark, onTap: () => Navigator.maybePop(context)),
                      Expanded(
                        child: Text(
                          _title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.ink),
                        ),
                      ),
                      GlassButton(
                        icon: _marked ? 'bookmarkFilled' : 'bookmark',
                        label: _marked ? '取消书签' : '添加书签',
                        dark: colors.dark,
                        color: _marked ? IosColors.accent : null,
                        onTap: total == 0 ? null : _toggleBookmark,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: (bottom > 0 ? bottom - 4 : 16),
                child: ChromeReveal(
                  visible: _chrome,
                  dy: 8,
                  child: Glass(
                    dark: colors.dark,
                    radius: 30,
                    child: SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: _barButton('bookmark', '目录', colors, total == 0 ? null : _toc)),
                          NovelPageLabel(page: _page, pages: _pages, color: colors.ink),
                          Expanded(child: _barButton('settings', '阅读设置', colors, () => showNovelAppearance(context))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _body(({Color bg, Color ink, Color muted, bool dark}) colors, double top, double bottom) {
    final c = _catalog;
    if (_loading && _content == null) {
      return Center(child: CupertinoActivityIndicator(color: colors.muted));
    }
    if (_needLogin) {
      return Padding(
        padding: EdgeInsets.fromLTRB(28, top + 80, 28, bottom + 100),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon('lock', size: 34, color: colors.muted, stroke: 1.5),
            const SizedBox(height: 14),
            Text(
              '正文需要登录后才能阅读',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              '源站对未登录的访客不提供正文。登录后可以正常阅读，书架也会一起同步。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: colors.muted),
            ),
            const SizedBox(height: 20),
            Pressable(
              onTap: _login,
              child: Container(
                height: 46,
                padding: const EdgeInsets.symmetric(horizontal: 28),
                decoration: BoxDecoration(color: IosColors.accent, borderRadius: BorderRadius.circular(23)),
                child: Center(
                  child: Text(
                    '登录轻小说账号',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: IosColors.onAccent),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (_error != null && _content == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(28, top + 80, 28, bottom + 100),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '这一章没加载出来',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: colors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.5, color: colors.muted),
            ),
            const SizedBox(height: 18),
            TextAction(label: '重试', color: colors.ink, onTap: () => _loadChapter(_index)),
          ],
        ),
      );
    }
    final content = _content;
    final style = novelBodyStyle(_prefs);
    final ch = c == null ? null : c.chapters[_index];
    final blocks = <Object>[
      if (content != null) ...novelBlocksOf(content.paragraphs, content.images),
      if (content != null && c != null) const NovelEndBlock(),
    ];
    return NovelBody(
      key: _bodyKey,
      contentId: c == null ? '' : '${c.aid}:${c.chapters[_index].cid}',
      blocks: blocks,
      style: style,
      ink: colors.ink,
      muted: colors.muted,
      paged: _prefs.novelPaged,
      // 顶栏和底栏是浮层，正文按「工具条收起」的内边距排版，翻页时字不会跳。
      padding: EdgeInsets.fromLTRB(28, top + 70, 28, bottom + 96),
      initialProgress: _progress,
      onProgress: (p, n, v) {
        if (p == _page && n == _pages) return;
        setState(() {
          _page = p;
          _pages = n;
          _progress = v;
        });
        // 每翻一页就记位置，退出时不用再补救一次。
        _saveProgress();
      },
      onTapCenter: () => setState(() => _chrome = !_chrome),
      // 最后一页再往后点就进下一章，第一页往前点回上一章。
      onTapRight: () {
        if (c == null || _index >= c.chapters.length - 1) return false;
        if (_page < _pages) return false;
        _goChapter(_index + 1);
        return true;
      },
      onTapLeft: () {
        if (_index <= 0 || _page > 1) return false;
        _goChapter(_index - 1);
        return true;
      },
      header: ch == null
          ? null
          : NovelChapterHeader(
              // 源站按卷重新编号，用「卷名 · 本章在卷内的序号」比「第 14 章」更不容易和正文标题打架。
              label: _chapterLabel(c!, ch),
              title: ch.name,
              ink: colors.ink,
              muted: colors.muted,
            ),
      endCard: content == null || c == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (content.previous != null && _index > 0) TextAction(label: '上一章', color: colors.ink, onTap: () => _goChapter(_index - 1)),
                    const Spacer(),
                    if (content.next != null && _index < c.chapters.length - 1) TextAction(label: '下一章', color: colors.ink, onTap: () => _goChapter(_index + 1)),
                  ],
                ),
                const SizedBox(height: 16),
                WenkuShelfButton(aid: c.aid, name: _title, author: _author),
                if (_index >= c.chapters.length - 1) ...[
                  const SizedBox(height: 10),
                  Text('— 全文完 —', style: TextStyle(fontSize: 13, color: colors.muted)),
                ],
              ],
            ),
      imageBuilder: (url, width) => _NovelImage(url: url, width: width, height: width * kNovelImageRatio),
    );
  }

  Widget _barButton(String icon, String label, ({Color bg, Color ink, Color muted, bool dark}) colors, VoidCallback? onTap) => Pressable(
    onTap: onTap,
    child: SizedBox(
      height: 60,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AppIcon(icon, size: 18, color: colors.ink, stroke: 1.7),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 15, color: colors.ink)),
        ],
      ),
    ),
  );
}

/// 正文插图：高度由分页器预留的槽位决定，图片按比例居中放进去，不改变分页。
/// 图床会拦 Dart 默认的 UA（实测 403），所以带上和网页一致的浏览器 UA；看过的插图走图片缓存。
class _NovelImage extends StatelessWidget {
  const _NovelImage({required this.url, required this.width, required this.height});

  final String url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: SizedBox(
      width: width,
      height: height,
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: const {'User-Agent': WenkuService.userAgent, 'Referer': '${WenkuService.base}/'},
        fit: BoxFit.contain,
        memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
        placeholder: (_, _) => const Center(child: CupertinoActivityIndicator()),
        errorWidget: (_, _, _) => Center(
          child: Text('插图没能加载', style: TextStyle(fontSize: 13, color: IosColors.muted)),
        ),
      ),
    ),
  );
}
