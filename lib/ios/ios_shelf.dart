import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/shelf_sync.dart';
import '../core/store.dart';
import '../ui/format.dart' show formatDay;
import '../ui/icons.dart';
import '../ui/widgets.dart' show CoverImage;
import 'ios_app.dart';
import 'ios_search.dart';
import 'ios_theme.dart';
import 'ios_wenku.dart';

class IosShelfPage extends StatefulWidget {
  const IosShelfPage({super.key});

  @override
  State<IosShelfPage> createState() => _IosShelfPageState();
}

enum _Filter { all, updated, ongoing, finished, novel }

class _IosShelfPageState extends State<IosShelfPage> {
  final _store = LibraryStore.instance;
  final _sync = ShelfSync.instance;
  final _prefs = ReaderPrefs.instance;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _prefs.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync.refresh());
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    _prefs.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<ShelfEntry> get _sorted {
    final list = _store.entries;
    if (_prefs.shelfSort == 1) {
      list.sort((a, b) {
        final c = b.latestUpdated.compareTo(a.latestUpdated);
        return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
      });
    }
    return list;
  }

  bool _match(ShelfEntry e) => switch (_filter) {
        _Filter.all => true,
        _Filter.updated => e.hasUpdate,
        _Filter.ongoing => e.kind == ShelfKind.manga && !e.finished,
        _Filter.finished => e.kind == ShelfKind.manga && e.finished,
        _Filter.novel => e.kind == ShelfKind.novel,
      };

  Future<void> _menu() async {
    final i = await showIosChoices(context, title: '书架', options: const ['检查追更', '按最近阅读排序', '按更新时间排序'], selected: _prefs.shelfSort + 1);
    if (i == 0) _sync.refresh(force: true);
    if (i == 1) _prefs.shelfSort = 0;
    if (i == 2) _prefs.shelfSort = 1;
  }

  Future<void> _entryMenu(ShelfEntry e) async {
    final options = [e.started ? '继续阅读' : '开始阅读', if (e.kind == ShelfKind.manga) '查看详情', '移出书架'];
    final i = await showIosChoices(context, title: e.name, options: options, destructiveIndex: options.length - 1);
    if (!mounted || i == null) return;
    if (i == 0) iosContinue(context, e);
    if (options[i] == '查看详情') iosOpenDetail(context, briefOfEntry(e));
    if (i == options.length - 1) _store.unfollow(e.id);
  }

  @override
  Widget build(BuildContext context) {
    final all = _sorted;
    final visible = [for (final e in all) if (_match(e)) e];
    final updates = [for (final e in all) if (e.hasUpdate) e];
    final resume = visible.where((e) => e.started).firstOrNull;
    final top = MediaQuery.paddingOf(context).top;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: top)),
        CupertinoSliverRefreshControl(onRefresh: () => _sync.refresh(force: true)),
        SliverToBoxAdapter(child: LargeTitle('书架', trailing: [GlassButton(icon: 'ellipsis', label: '书架选项', onTap: _menu)])),
        if (all.isEmpty)
          const SliverToBoxAdapter(child: _FirstRun())
        else ...[
          SliverToBoxAdapter(
            child: TextChips(
              items: [('全部', all.length, false), ('有更新', updates.length, updates.isNotEmpty), ('连载中', null, false), ('已完结', null, false), ('轻小说', null, false)],
              selected: _filter.index,
              onSelect: (i) => setState(() => _filter = _Filter.values[i]),
            ),
          ),
          if (resume != null) SliverToBoxAdapter(child: _Resume(entry: resume)),
          if (_filter == _Filter.all && updates.isNotEmpty) ...[
            SliverToBoxAdapter(child: IosSection('有更新', count: '${updates.length}', action: '全部', onAction: () => setState(() => _filter = _Filter.updated))),
            SliverList.builder(itemCount: updates.length.clamp(0, 3), itemBuilder: (context, i) => _UpdateRow(entry: updates[i], last: i == updates.length.clamp(0, 3) - 1)),
          ],
          SliverToBoxAdapter(
            child: IosSection(
              '我的藏书',
              count: '${visible.length}',
              action: _prefs.shelfSort == 0 ? '最近阅读' : '更新时间',
              actionIcon: 'down',
              onAction: () async {
                final i = await showIosChoices(context, title: '排序', options: const ['最近阅读', '更新时间'], selected: _prefs.shelfSort);
                if (i != null) _prefs.shelfSort = i;
              },
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(child: _FilterEmpty(novel: _filter == _Filter.novel, updated: _filter == _Filter.updated))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                  mainAxisExtent: (MediaQuery.sizeOf(context).width - 40 - 28) / 3 * 4 / 3 + 8 + 42 + 18,
                ),
                itemCount: visible.length,
                itemBuilder: (context, i) => _Tile(entry: visible[i], onLongPress: () => _entryMenu(visible[i])),
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 130)),
      ],
    );
  }
}

class _Resume extends StatelessWidget {
  const _Resume({required this.entry});

  final ShelfEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final where = e.kind == ShelfKind.manga && e.pageCount > 0 ? '${e.chapterName}  第 ${e.page + 1} / ${e.pageCount} 页' : e.chapterName ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Pressable(
          onTap: () => e.kind == ShelfKind.manga ? iosOpenDetail(context, briefOfEntry(e)) : iosContinue(context, e),
          child: DecoratedBox(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Color(0x2E1A1A28), blurRadius: 12, offset: Offset(0, 5))]),
            child: CoverImage(url: e.cover, title: e.name, width: 100, height: 140, radius: 6),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 2),
            Text('最近在读', style: TextStyle(fontSize: 13, color: IosColors.muted)),
            const SizedBox(height: 4),
            Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w700, color: IosColors.ink)),
            const SizedBox(height: 6),
            Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: IosColors.muted)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(value: e.progress.clamp(0, 1), minHeight: 3, color: IosColors.accent, backgroundColor: IosColors.faint),
                ),
              ),
              const SizedBox(width: 10),
              Text('${(e.progress * 100).round()}%', style: TextStyle(fontSize: 13, color: IosColors.muted)),
            ]),
            const SizedBox(height: 12),
            Pressable(
              onTap: () => iosContinue(context, e),
              child: Glass(
                radius: 22,
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('继续阅读', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: IosColors.ink)),
                  SizedBox(width: 10),
                  AppIcon('arrow', size: 18, color: IosColors.accent, stroke: 1.9),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.entry, required this.last});

  final ShelfEntry entry;
  final bool last;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => iosOpenDetail(context, briefOfEntry(entry)),
        child: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Row(children: [
            CoverImage(url: entry.cover, title: entry.name, width: 40, height: 54, radius: 4),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(0, 12, 20, 12),
                decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: IosColors.line, width: .5))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: IosColors.ink)),
                      const SizedBox(height: 3),
                      Text('更新至 ${entry.latestChapter} · ${formatDay(entry.latestUpdated)}',
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: IosColors.muted)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Text('新 ${entry.newCount} 话', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: IosColors.accent)),
                ]),
              ),
            ),
          ]),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.entry, required this.onLongPress});

  final ShelfEntry entry;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final meta = e.kind == ShelfKind.novel ? '轻小说 · ${e.started ? e.chapterName : '未开始'}' : e.placeLabel;
    return Pressable(
      onTap: () => e.kind == ShelfKind.manga ? iosOpenDetail(context, briefOfEntry(e)) : iosContinue(context, e),
      onLongPress: onLongPress,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: LayoutBuilder(
            builder: (context, c) => Stack(children: [
              DecoratedBox(
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), boxShadow: const [BoxShadow(color: Color(0x1F1A1A28), blurRadius: 8, offset: Offset(0, 3))]),
                child: CoverImage(url: e.cover, title: e.name, width: c.maxWidth, height: c.maxHeight, radius: 6),
              ),
              if (e.hasUpdate)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: IosColors.accent, shape: BoxShape.circle, border: Border.all(color: IosColors.surface, width: 2)),
                  ),
                ),
              if (e.started && e.progress > 0 && e.progress < 1)
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(value: e.progress, minHeight: 3, color: IosColors.accent, backgroundColor: const Color(0x99FFFFFF)),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, height: 1.3, color: IosColors.ink)),
        const SizedBox(height: 2),
        Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: IosColors.muted)),
      ]),
    );
  }
}

class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty({required this.novel, required this.updated});

  final bool novel;
  final bool updated;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            updated ? '追更的作品暂时都没有新话，下拉可以重新检查。' : (novel ? '书架上还没有轻小说。' : '没有符合条件的作品。'),
            style: TextStyle(fontSize: 15, height: 1.6, color: IosColors.muted),
          ),
          if (novel) ...[
            TextAction(label: '登录轻小说账号，同步源站书架', onTap: () => Navigator.of(context).push(CupertinoPageRoute<void>(builder: (_) => const IosWenkuPage()))),
            const SizedBox(height: 10),
            TextAction(label: '打开示例《雨停之前》', onTap: () => iosOpenNovel(context)),
          ],
        ]),
      );
}

/// 首次使用：说明作品怎么进书架，给出热门推荐。
class _FirstRun extends StatefulWidget {
  const _FirstRun();

  @override
  State<_FirstRun> createState() => _FirstRunState();
}

class _FirstRunState extends State<_FirstRun> {
  late final _top = MangaApi.instance.ranks(dateType: 'total', limit: 3);

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 40),
        Unavailable(
          icon: 'book',
          title: '好故事，从第一本开始',
          message: '打开作品详情，点一下追更书签。\n新话更新、读到哪页，都帮你记着。',
          actions: [
            AccentButton(label: '去发现', icon: 'arrow', onTap: () => IosShell.tab.value = 1),
            TextAction(label: '搜索作品', onTap: () => Navigator.of(context).push(CupertinoPageRoute(builder: (_) => const IosSearchPage()))),
          ],
        ),
        const IosSection('热门推荐', note: '从这里翻开'),
        FutureBuilder<PageResult<RankItem>>(
          future: _top,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Text('暂时拿不到推荐', style: TextStyle(fontSize: 13, color: IosColors.muted)));
            }
            final items = snap.data?.list;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: items == null || i >= items.length
                        ? const AspectRatio(aspectRatio: 3 / 4, child: Redacted(height: double.infinity))
                        : Pressable(
                            onTap: () => iosOpenDetail(context, items[i].comic),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              AspectRatio(
                                aspectRatio: 3 / 4,
                                child: LayoutBuilder(builder: (context, c) => CoverImage(url: items[i].comic.cover, title: items[i].comic.name, width: c.maxWidth, height: c.maxHeight, radius: 6)),
                              ),
                              const SizedBox(height: 7),
                              Text(items[i].comic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 15, color: IosColors.ink)),
                            ]),
                          ),
                  ),
                ],
              ]),
            );
          },
        ),
      ]);
}
