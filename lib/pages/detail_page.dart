import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'chapter_pager.dart';
import 'common.dart';
import 'navigation.dart';

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.comic});

  /// 列表里已有的字段，详情加载前先用它渲染。
  final ComicBrief comic;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  final _store = LibraryStore.instance;
  late final _browser = ChapterBrowser(widget.comic.pathWord);
  final _currentKey = GlobalKey();
  ComicDetail? _detail;
  String? _error;
  bool _briefOpen = false;

  /// 章节加载完后滚动到在读那一条。
  bool _pendingLocate = false;

  String get _pw => widget.comic.pathWord;
  ComicBrief get _comic => _detail?.comic ?? widget.comic;

  @override
  void initState() {
    super.initState();
    _store.addListener(_refresh);
    _browser.addListener(_onBrowser);
    _load();
  }

  @override
  void dispose() {
    _store.removeListener(_refresh);
    _browser.removeListener(_onBrowser);
    _browser.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onBrowser() {
    _refresh();
    if (_pendingLocate && !_browser.loading && _browser.items != null) {
      _pendingLocate = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _currentKey.currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .35, duration: const Duration(milliseconds: 250));
      });
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final d = await MangaApi.instance.detail(_pw);
      if (!mounted) return;
      // 打开详情就算看过了：清掉书架上的“有更新”。
      _store.applyRemote(d, seen: true);
      final e = _store.entry(_pw);
      final locate = e?.chapterIndex;
      _pendingLocate = locate != null;
      setState(() => _detail = d);
      _browser.setGroups(d.groups, preferGroup: e?.group, locateIndex: locate);
    } catch (err) {
      if (mounted) setState(() => _error = err.toString());
    }
  }

  void _toggleFollow() {
    final d = _detail;
    if (d == null) return;
    final old = _store.entry(_pw);
    if (old != null) {
      _store.remove(_pw);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('已取消追更'),
          action: SnackBarAction(label: '撤销', textColor: Palette.accentSoft, onPressed: () => _store.put(old)),
        ));
    } else {
      _store.follow(d);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已加入书架，有新话会提醒'), duration: Duration(seconds: 2)));
    }
  }

  void _locate() {
    final e = _store.entry(_pw);
    if (e?.chapterIndex == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('还没有开始读这部作品'), duration: Duration(seconds: 2)));
      return;
    }
    _pendingLocate = true;
    _browser.locate(e!.chapterIndex!, inGroup: e.group);
  }

  Future<void> _resume() async {
    final e = _store.entry(_pw);
    if (e?.chapterUuid != null) {
      return openReader(context, comic: _comic, group: e!.group ?? _browser.group, chapterUuid: e.chapterUuid!, initialPage: e.page);
    }
    try {
      final page = await MangaApi.instance.chapters(_pw, _browser.group, limit: 1);
      final first = page.list.firstOrNull;
      if (first != null && mounted) openReader(context, comic: _comic, group: _browser.group, chapterUuid: first.uuid);
    } catch (err) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _store.entry(_pw);
    final d = _detail;
    final locked = d?.isLock ?? false;
    return Scaffold(
      body: Column(children: [
        SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(children: [
              const SizedBox(width: 4),
              ToolButton(icon: 'back', tooltip: '返回', size: 48, onTap: () => Navigator.pop(context)),
              const Spacer(),
              ToolButton(icon: 'refresh', tooltip: '刷新', size: 48, onTap: _detail == null ? null : _load),
              const SizedBox(width: 4),
            ]),
          ),
        ),
        Expanded(
          child: d == null
              ? ListView(children: [
                  _header(null),
                  if (_error != null) ApiErrorPanel(message: _error!, onRetry: _load) else const SizedBox(height: 200, child: LoadingView()),
                ])
              : CustomScrollView(slivers: [
                  SliverToBoxAdapter(child: _header(d)),
                  SliverToBoxAdapter(child: _meta(d)),
                  SliverToBoxAdapter(child: _brief(d)),
                  SliverToBoxAdapter(child: Container(height: 8, margin: const EdgeInsets.only(top: 14), color: Palette.tonal)),
                  SliverToBoxAdapter(child: _chapterHeader(d)),
                  if (locked)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
                        child: Row(children: [
                          AppIcon('lock', size: 16, color: Palette.accent),
                          SizedBox(width: 8),
                          Expanded(child: Text('源站把这部作品标记为付费或会员内容，阅读器不提供绕过。', style: TextStyle(fontSize: 12, color: Palette.accent))),
                        ]),
                      ),
                    ),
                  _chapterList(entry, locked),
                  SliverToBoxAdapter(child: ChapterListStatus(browser: _browser)),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ]),
        ),
        _actionBar(entry, locked),
      ]),
    );
  }

  Widget _header(ComicDetail? d) {
    final status = d?.status ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 20, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Book3D(
          rotateY: -11 * 3.14159 / 180,
          rotateZ: -2 * 3.14159 / 180,
          elevation: .55,
          child: CoverImage(url: _comic.cover, title: _comic.name, width: 108, height: 152),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_comic.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kSerif, fontSize: 24, height: 1.3, fontWeight: FontWeight.w600)),
            if (d != null && d.aliases.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('又名 ${d.aliases.join(' · ')}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, height: 1.5, color: Palette.ink3)),
            ],
            const SizedBox(height: 10),
            Text(_comic.authorText, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Palette.ink2)),
            if (d != null) ...[
              const SizedBox(height: 10),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
                if (status.isNotEmpty)
                  Pill(status,
                      background: d.finished ? Palette.tonal2 : Palette.accentSoft, color: d.finished ? Palette.sageInk : Palette.accent, bold: true),
                if (d.lastChapter.isNotEmpty)
                  Text('更新至 ${d.lastChapter} · ${formatDay(d.comic.updated)}', style: const TextStyle(fontSize: 12, color: Palette.ink2)),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _meta(ComicDetail d) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: formatPopular(d.comic.popular), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Palette.ink)),
            const TextSpan(text: ' 人气  ', style: TextStyle(fontSize: 12, color: Palette.ink2)),
          ])),
          for (final t in d.themes) Pill(t),
          if (d.region.isNotEmpty) Pill(d.region),
        ]),
      );

  Widget _brief(ComicDetail d) {
    if (d.brief.isEmpty) return const SizedBox(height: 4);
    const style = TextStyle(fontSize: 14, height: 1.75, color: Palette.ink2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: LayoutBuilder(builder: (context, c) {
        // 只有三行放不下时才给「展开」。
        final tp = TextPainter(text: TextSpan(text: d.brief, style: style), maxLines: 3, textDirection: TextDirection.ltr)..layout(maxWidth: c.maxWidth);
        final overflow = tp.didExceedMaxLines;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.brief, maxLines: _briefOpen ? null : 3, overflow: _briefOpen ? null : TextOverflow.ellipsis, style: style),
          if (overflow)
            TextButton(
              onPressed: () => setState(() => _briefOpen = !_briefOpen),
              style: TextButton.styleFrom(foregroundColor: Palette.ink2, padding: EdgeInsets.zero, minimumSize: const Size(48, 36)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_briefOpen ? '收起' : '展开', style: const TextStyle(fontSize: 12)),
                AnimatedRotation(turns: _briefOpen ? .5 : 0, duration: const Duration(milliseconds: 160), child: const AppIcon('down', size: 14, color: Palette.ink2)),
              ]),
            ),
        ]);
      }),
    );
  }

  Widget _chapterHeader(ComicDetail d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
          child: Row(children: [
            const Text('章节', style: TextStyle(fontFamily: kSerif, fontSize: 19, height: 1.4, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text('共 ${d.chapterCount} 条', style: const TextStyle(fontSize: 12, color: Palette.ink3)),
            const Spacer(),
            ToolButton(icon: 'locate', tooltip: '定位到在读', size: 48, iconSize: 20, color: Palette.ink2, onTap: _locate),
            ToolButton(
              icon: 'sort',
              tooltip: _browser.descending ? '改为正序' : '改为倒序',
              size: 48,
              iconSize: 20,
              color: _browser.descending ? Palette.accent : Palette.ink2,
              onTap: _browser.toggleOrder,
            ),
          ]),
        ),
        if (d.groups.length > 1)
          UnderlineTabs(
            labels: [for (final g in d.groups) (g.name, g.count)],
            selected: d.groups.indexWhere((g) => g.pathWord == _browser.group).clamp(0, d.groups.length - 1),
            onSelect: (i) => _browser.selectGroup(d.groups[i].pathWord),
          ),
        RangeChips(browser: _browser),
      ]);

  Widget _chapterList(ShelfEntry? entry, bool locked) {
    final items = _browser.items ?? const <Chapter>[];
    final range = _browser.currentRange;
    if (_browser.loading || range == null) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, i) {
        final ch = items[i];
        final isCurrent = entry?.chapterUuid == ch.uuid;
        return ChapterTile(
          key: isCurrent ? _currentKey : null,
          chapter: ch,
          number: ch.index + 1,
          read: _store.isRead(_pw, ch.uuid),
          current: isCurrent ? entry : null,
          locked: locked,
          onTap: () {
            if (locked) return;
            openReader(context, comic: _comic, group: _browser.group, chapterUuid: ch.uuid, initialPage: isCurrent ? entry!.page : 0);
          },
        );
      },
    );
  }

  Widget _actionBar(ShelfEntry? entry, bool locked) {
    final started = entry?.chapterUuid != null;
    final following = entry != null;
    final d = _detail;
    final ready = d != null && !locked;
    return DecoratedBox(
      decoration: const BoxDecoration(color: Palette.bar, border: Border(top: BorderSide(color: Palette.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(
                  started ? (entry!.pageCount > 0 ? '读到 · 第 ${entry.page + 1} / ${entry.pageCount} 页' : '读到') : (locked ? '暂不可读' : '尚未开始'),
                  style: const TextStyle(fontSize: 12, color: Palette.ink3),
                ),
                const SizedBox(height: 2),
                Text(
                  started ? entry!.chapterName ?? '' : (d?.lastChapter.isNotEmpty ?? false ? '最新 ${d!.lastChapter}' : _comic.name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: following ? '取消追更' : '追更',
              child: Material(
                color: following ? Palette.tonal2 : Palette.tonal,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: d == null ? null : _toggleFollow,
                  child: SizedBox.square(
                    dimension: 48,
                    child: Center(child: AppIcon(following ? 'bookmarkFilled' : 'bookmark', size: 20, color: following ? Palette.sageInk : Palette.ink2)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: ready ? _resume : null,
              style: FilledButton.styleFrom(backgroundColor: Palette.ink, minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 22)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(started ? '继续阅读' : '开始阅读', style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                AppIcon('arrow', size: 18, color: ready ? Palette.onInk : Palette.ink4),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
