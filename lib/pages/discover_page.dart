import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../ui/comic_tiles.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'navigation.dart';
import 'search_page.dart';

/// 发现：题材筛选、今日更新、日 / 周 / 月 / 总排行。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  /// 0 为全部题材，其余对应 [AppConfig.themes] 的下标 + 1。
  int _theme = 0;

  @override
  Widget build(BuildContext context) => SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(
            height: 56,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('发现', style: TextStyle(fontFamily: kSerif, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 1, height: 1)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Material(
              color: Palette.tonal,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
                child: const SizedBox(
                  height: 48,
                  child: Row(children: [
                    SizedBox(width: 18),
                    AppIcon('search', size: 20, color: Palette.ink2),
                    SizedBox(width: 10),
                    Text('搜索作品、作者', style: TextStyle(fontSize: 14, color: Palette.ink3)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          FilterChips(
            items: [('全部题材', null, false), for (final t in AppConfig.themes) (t.$1, null, false)],
            selected: _theme,
            onSelect: (i) => setState(() => _theme = i),
          ),
          Expanded(
            child: _theme == 0
                ? const _Overview()
                : _ThemeGrid(key: ValueKey(_theme), name: AppConfig.themes[_theme - 1].$1, pathWord: AppConfig.themes[_theme - 1].$2),
          ),
        ]),
      );
}

class _Overview extends StatefulWidget {
  const _Overview();

  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> with AutomaticKeepAliveClientMixin {
  static const _periods = [('day', '日榜'), ('week', '周榜'), ('month', '月榜'), ('total', '总榜')];
  int _period = 0;
  late Future<PageResult<ComicBrief>> _latest = MangaApi.instance.comics(limit: 12);
  late final _ranks = Pager<RankItem>((offset) => MangaApi.instance.ranks(dateType: _periods[_period].$1, offset: offset))..loadMore();

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _ranks.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _latest = MangaApi.instance.comics(limit: 12));
    await _ranks.refresh();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: _ranks,
      builder: (context, _) => NotificationListener<ScrollNotification>(
        onNotification: (n) => onScrollEnd(n, _ranks.loadMore),
        child: RefreshIndicator(
          color: Palette.ink,
          onRefresh: _refresh,
          child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
            SliverToBoxAdapter(
              child: SectionHeader(
                title: '今日更新',
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                trailing: HeaderAction(
                  label: '更多',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LatestPage())),
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: 196, child: _latestRow())),
            const SliverToBoxAdapter(child: SectionHeader(title: '排行', count: '按人气增长')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Segmented(
                  height: 34,
                  options: [for (final p in _periods) p.$2],
                  selected: _period,
                  background: Palette.tonal,
                  active: Palette.bar,
                  muted: Palette.ink2,
                  onChanged: (v) {
                    setState(() => _period = v);
                    _ranks.refresh();
                  },
                ),
              ),
            ),
            SliverList.builder(
              itemCount: _ranks.items.length,
              itemBuilder: (context, i) => RankRow(item: _ranks.items[i], onTap: () => openDetail(context, _ranks.items[i].comic)),
            ),
            SliverToBoxAdapter(child: PagerFooter(pager: _ranks)),
          ]),
        ),
      ),
    );
  }

  Widget _latestRow() => FutureBuilder<PageResult<ComicBrief>>(
        future: _latest,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(() => _latest = MangaApi.instance.comics(limit: 12)),
                child: const Text('今日更新加载失败，点按重试'),
              ),
            );
          }
          final list = snap.data?.list;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: list?.length ?? 4,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => list == null
                ? const SizedBox(
                    width: 96,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Skeleton(width: 96, height: 128, radius: 3),
                      SizedBox(height: 8),
                      Skeleton(width: 80, height: 13),
                      SizedBox(height: 6),
                      Skeleton(width: 56, height: 11),
                    ]),
                  )
                : MiniTile(comic: list[i], onTap: () => openDetail(context, list[i])),
          );
        },
      );
}

/// 选中题材后：该题材的作品网格，可在热门与最新之间切换。
class _ThemeGrid extends StatefulWidget {
  const _ThemeGrid({super.key, required this.name, required this.pathWord});

  final String name;
  final String pathWord;

  @override
  State<_ThemeGrid> createState() => _ThemeGridState();
}

class _ThemeGridState extends State<_ThemeGrid> {
  int _order = 0;
  late final _pager = Pager<ComicBrief>(
    (offset) => MangaApi.instance.comics(theme: widget.pathWord, ordering: _order == 0 ? '-popular' : '-datetime_updated', offset: offset),
  )..loadMore();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _pager,
        builder: (context, _) => NotificationListener<ScrollNotification>(
          onNotification: (n) => onScrollEnd(n, _pager.loadMore),
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: Row(children: [
                  Text(widget.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  if (_pager.total > 0) Text('共 ${_pager.total} 部', style: const TextStyle(fontSize: 12, color: Palette.ink3)),
                  const Spacer(),
                  SizedBox(
                    width: 132,
                    child: Segmented(
                      height: 30,
                      options: const ['热门', '最新'],
                      selected: _order,
                      background: Palette.tonal,
                      active: Palette.bar,
                      muted: Palette.ink2,
                      onChanged: (v) {
                        setState(() => _order = v);
                        _pager.refresh();
                      },
                    ),
                  ),
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: .52),
                itemCount: _pager.items.length,
                itemBuilder: (context, i) => ComicGridTile(comic: _pager.items[i], onTap: () => openDetail(context, _pager.items[i])),
              ),
            ),
            SliverToBoxAdapter(child: PagerFooter(pager: _pager, emptyText: '这个题材下暂时没有作品')),
          ]),
        ),
      );
}

/// 「今日更新 · 更多」：按更新时间排序的完整网格。
class LatestPage extends StatefulWidget {
  const LatestPage({super.key});

  @override
  State<LatestPage> createState() => _LatestPageState();
}

class _LatestPageState extends State<LatestPage> {
  late final _pager = Pager<ComicBrief>((offset) => MangaApi.instance.comics(offset: offset))..loadMore();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Palette.bg,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(icon: const AppIcon('back'), tooltip: '返回', onPressed: () => Navigator.pop(context)),
          title: const Text('最近更新', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        body: ListenableBuilder(
          listenable: _pager,
          builder: (context, _) => NotificationListener<ScrollNotification>(
            onNotification: (n) => onScrollEnd(n, _pager.loadMore),
            child: RefreshIndicator(
              color: Palette.ink,
              onRefresh: _pager.refresh,
              child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  sliver: SliverGrid.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 18, crossAxisSpacing: 14, childAspectRatio: .52),
                    itemCount: _pager.items.length,
                    itemBuilder: (context, i) => ComicGridTile(comic: _pager.items[i], onTap: () => openDetail(context, _pager.items[i])),
                  ),
                ),
                SliverToBoxAdapter(child: PagerFooter(pager: _pager)),
              ]),
            ),
          ),
        ),
      );
}
