import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/format.dart' show formatPopular;
import '../ui/icons.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart' show Dock, Space;
import '../ui/widgets.dart' show CoverImage, Pager, coverHeightFor, kCoverAspect, onScrollEnd;
import 'ios_app.dart';
import 'ios_mine.dart' show iosEditProxy;
import 'ios_search.dart';
import 'ios_theme.dart';

class IosDiscoverPage extends StatefulWidget {
  const IosDiscoverPage({super.key});

  @override
  State<IosDiscoverPage> createState() => _IosDiscoverPageState();
}

class _IosDiscoverPageState extends State<IosDiscoverPage> {
  static const _periods = [('day', '日榜'), ('week', '周榜'), ('month', '月榜'), ('total', '总榜')];

  /// 0 为全部题材。
  int _theme = 0;
  int _period = 0;
  int _order = 0;
  late Future<PageResult<ComicBrief>> _latest = MangaApi.instance.comics(limit: 12);
  late final _ranks = Pager<RankItem>((offset) => MangaApi.instance.ranks(dateType: _periods[_period].$1, offset: offset))..loadMore();
  Pager<ComicBrief>? _themePager;

  @override
  void dispose() {
    _ranks.dispose();
    _themePager?.dispose();
    super.dispose();
  }

  void _selectTheme(int i) {
    _themePager?.dispose();
    _themePager = null;
    if (i > 0) {
      final pw = AppConfig.themes[i - 1].$2;
      _themePager = Pager<ComicBrief>((offset) => MangaApi.instance.comics(theme: pw, ordering: _order == 0 ? '-popular' : '-datetime_updated', offset: offset))..loadMore();
    }
    setState(() => _theme = i);
  }

  Future<void> _refresh() async {
    setState(() => _latest = MangaApi.instance.comics(limit: 12));
    await (_themePager ?? _ranks).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final pager = _themePager;
    return ListenableBuilder(
      listenable: Listenable.merge([_ranks, ?pager]),
      builder: (context, _) => NotificationListener<ScrollNotification>(
        onNotification: (n) => onScrollEnd(n, (pager ?? _ranks).loadMore),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).top)),
            CupertinoSliverRefreshControl(onRefresh: _refresh),
            const SliverToBoxAdapter(child: LargeTitle('发现')),
            SliverToBoxAdapter(child: _SearchField(onTap: () => Navigator.of(context).push(appRoute((_) => const IosSearchPage())))),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: Space.x2),
                child: TextChips(items: [('全部题材', null, false), for (final t in AppConfig.themes) (t.$1, null, false)], selected: _theme, onSelect: _selectTheme),
              ),
            ),
            if (pager != null) ..._themeSlivers(pager) else ..._overviewSlivers(),
            SliverToBoxAdapter(child: SizedBox(height: Dock.clearance(context))),
          ],
        ),
      ),
    );
  }

  List<Widget> _overviewSlivers() {
    final firstLoad = _ranks.items.isEmpty;
    if (firstLoad && _ranks.error != null) {
      return [SliverToBoxAdapter(child: IosNetworkError(message: _ranks.error!, onRetry: _refresh))];
    }
    return [
      SliverToBoxAdapter(
        child: IosSection('今日更新', action: '更多', onAction: () => Navigator.of(context).push(appRoute((_) => const IosLatestPage()))),
      ),
      SliverToBoxAdapter(child: SizedBox(height: 206, child: _latestRow())),
      const SliverToBoxAdapter(child: IosSection('人气排行', note: '按人气增长')),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.x2),
          child: IosSegmented(
            options: [for (final p in _periods) p.$2],
            selected: _period,
            onChanged: (v) {
              setState(() => _period = v);
              _ranks.refresh();
            },
          ),
        ),
      ),
      if (firstLoad && _ranks.loading)
        SliverList.builder(itemCount: 4, itemBuilder: (_, _) => const _RowPlaceholder())
      else
        SliverList.builder(
          itemCount: _ranks.items.length,
          itemBuilder: (context, i) => _RankRow(item: _ranks.items[i], last: i == _ranks.items.length - 1),
        ),
      SliverToBoxAdapter(child: _Footer(pager: _ranks)),
    ];
  }

  List<Widget> _themeSlivers(Pager<ComicBrief> pager) {
    final name = AppConfig.themes[_theme - 1].$1;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.page, Space.x5, Space.page, Space.x3),
          child: Row(children: [
            Text(name, style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: IosColors.ink)),
            const SizedBox(width: 8),
            if (pager.total > 0) Text('${pager.total} 部', style: TextStyle(fontSize: 15, color: IosColors.muted)),
            const Spacer(),
            SizedBox(
              width: 140,
              child: IosSegmented(
                options: const ['热门', '最新'],
                selected: _order,
                onChanged: (v) {
                  _order = v;
                  _selectTheme(_theme);
                },
              ),
            ),
          ]),
        ),
      ),
      if (pager.items.isEmpty && pager.error != null)
        SliverToBoxAdapter(child: IosNetworkError(message: pager.error!, onRetry: pager.refresh))
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Space.page),
          sliver: SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: Space.x3 + 2,
              mainAxisSpacing: Space.x4 + 2,
              mainAxisExtent: (MediaQuery.sizeOf(context).width - Space.page * 2 - (Space.x3 + 2) * 2) / 3 * kCoverAspect + Space.x2 + 40,
            ),
            itemCount: pager.items.isEmpty && pager.loading ? 6 : pager.items.length,
            itemBuilder: (context, i) => pager.items.isEmpty ? const _GridPlaceholder() : _GridTile(comic: pager.items[i]),
          ),
        ),
      SliverToBoxAdapter(child: _Footer(pager: pager)),
    ];
  }

  Widget _latestRow() => FutureBuilder<PageResult<ComicBrief>>(
        future: _latest,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: TextAction(label: '今日更新加载失败，点按重试', onTap: () => setState(() => _latest = MangaApi.instance.comics(limit: 12))));
          }
          final list = snap.data?.list;
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.page),
            itemCount: list?.length ?? 4,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => SizedBox(
              width: 104,
              child: list == null
                  ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Redacted(width: 104, height: coverHeightFor(104)),
                      const SizedBox(height: 8),
                      const Redacted(width: 84, height: 15),
                      const SizedBox(height: 6),
                      const Redacted(width: 56, height: 13),
                    ])
                  : Pressable(
                      onTap: () => iosOpenDetail(context, list[i]),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CoverImage(url: list[i].cover, title: list[i].name, width: 104, height: coverHeightFor(104), radius: 6),
                        const SizedBox(height: 7),
                        Text(list[i].name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, color: IosColors.ink)),
                        const SizedBox(height: 2),
                        Text(list[i].authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: IosColors.muted)),
                      ]),
                    ),
            ),
          );
        },
      );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        child: Pressable(
          onTap: onTap,
          semanticLabel: '搜索作品、作者',
          child: Container(
            height: 44,
            decoration: BoxDecoration(color: IosColors.faint, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              SizedBox(width: 12),
              AppIcon('search', size: 18, color: IosColors.muted, stroke: 1.9),
              SizedBox(width: 8),
              Text('搜索作品、作者', style: TextStyle(fontSize: 17, color: IosColors.muted)),
            ]),
          ),
        ),
      );
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.item, required this.last});

  final RankItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final r = item;
    final top = r.sort <= 3;
    final Widget delta = r.isNew
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: IosColors.accentSoft, borderRadius: BorderRadius.circular(6)),
            child: Text('新', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: IosColors.accent)),
          )
        : Text(
            r.rise > 0 ? '▲${r.rise}' : (r.rise < 0 ? '▼${-r.rise}' : '—'),
            style: TextStyle(fontSize: 13, color: r.rise > 0 ? IosColors.accent : IosColors.muted),
          );
    return Pressable(
      onTap: () => iosOpenDetail(context, r.comic),
      child: Padding(
        padding: const EdgeInsets.only(left: Space.page),
        child: Row(children: [
          SizedBox(
            width: 24,
            child: Text('${r.sort}', textAlign: TextAlign.center, style: TextStyle(fontSize: top ? 20 : 17, fontWeight: FontWeight.w600, color: top ? IosColors.accent : IosColors.muted)),
          ),
          const SizedBox(width: 12),
          CoverImage(url: r.comic.cover, title: r.comic.name, width: 46, height: coverHeightFor(46), radius: 4),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, Space.x3, Space.page, Space.x3),
              decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: IosColors.line, width: .5))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.comic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: IosColors.ink)),
                    const SizedBox(height: 3),
                    Text(r.comic.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: IosColors.muted)),
                    const SizedBox(height: 2),
                    Text('人气 ${formatPopular(r.comic.popular)}', style: TextStyle(fontSize: 13, color: IosColors.muted)),
                  ]),
                ),
                const SizedBox(width: 8),
                delta,
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.comic});

  final ComicBrief comic;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => iosOpenDetail(context, comic),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1 / kCoverAspect,
            child: LayoutBuilder(builder: (context, c) => CoverImage(url: comic.cover, title: comic.name, width: c.maxWidth, height: c.maxHeight, radius: 6)),
          ),
          const SizedBox(height: 7),
          Text(comic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: IosColors.ink)),
          const SizedBox(height: 2),
          Text(comic.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: IosColors.muted)),
        ]),
      );
}

class _GridPlaceholder extends StatelessWidget {
  const _GridPlaceholder();

  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(aspectRatio: 1 / kCoverAspect, child: Redacted(height: double.infinity)),
        SizedBox(height: 8),
        Redacted(width: 80, height: 14),
      ]);
}

class _RowPlaceholder extends StatelessWidget {
  const _RowPlaceholder();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.page, 10, Space.page, 10),
        child: Row(children: [
          const Redacted(width: 22, height: 20),
          const SizedBox(width: 12),
          Redacted(width: 46, height: coverHeightFor(46), radius: 4),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const FractionallySizedBox(widthFactor: .7, child: Redacted(height: 16)),
              const SizedBox(height: 8),
              const FractionallySizedBox(widthFactor: .45, child: Redacted(height: 13)),
            ]),
          ),
        ]),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.pager});

  final Pager<Object?> pager;

  @override
  Widget build(BuildContext context) {
    if (pager.items.isEmpty) return const SizedBox.shrink();
    if (pager.error != null) return Center(child: TextAction(label: '加载失败，点按重试', onTap: pager.loadMore));
    if (pager.loading) return const Padding(padding: EdgeInsets.all(20), child: CupertinoActivityIndicator());
    if (!pager.hasMore) return Padding(padding: EdgeInsets.all(24), child: Center(child: Text('已经到底了', style: TextStyle(fontSize: 13, color: IosColors.muted))));
    return const SizedBox(height: 40);
  }
}

/// 网络异常：「内容不可用」样式 + 可展开的连接详情。
class IosNetworkError extends StatefulWidget {
  const IosNetworkError({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  State<IosNetworkError> createState() => _IosNetworkErrorState();
}

class _IosNetworkErrorState extends State<IosNetworkError> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final diag = MangaApi.instance.lastError.value;
    final proxy = ReaderPrefs.instance.proxy;
    final at = diag?.at;
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(children: [
        Unavailable(
          icon: 'wifiOff',
          iconBackground: IosColors.accentSoft,
          title: '暂时连不上数据源',
          message: '${widget.message}。\n书架和读过的位置都保存在本机。',
          actions: [
            AccentButton(label: '重试', icon: 'refresh', onTap: widget.onRetry),
            TextAction(label: '代理设置', onTap: () => iosEditProxy(context)),
          ],
        ),
        const SizedBox(height: 18),
        Pressable(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('连接详情', style: TextStyle(fontSize: 13, color: IosColors.muted)),
              const SizedBox(width: 4),
              AnimatedRotation(turns: _open ? .5 : 0, duration: const Duration(milliseconds: 180), child: AppIcon('down', size: 13, color: IosColors.muted, stroke: 2)),
            ]),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _open
              ? InsetGroup(children: [
                  IosRow(title: '数据源', value: diag?.host ?? Uri.parse(MangaApi.instance.activeHost).host, chevron: false),
                  IosRow(title: '网络代理', value: proxy.isEmpty ? '跟随系统' : proxy, chevron: false),
                  if (at != null)
                    IosRow(
                      title: '最近一次失败',
                      valueWidget: Text('${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}', style: TextStyle(fontSize: 15, color: IosColors.accent)),
                      chevron: false,
                    ),
                ])
              : const SizedBox(width: double.infinity),
        ),
      ]),
    );
  }
}

/// 「今日更新 · 更多」。
class IosLatestPage extends StatefulWidget {
  const IosLatestPage({super.key});

  @override
  State<IosLatestPage> createState() => _IosLatestPageState();
}

class _IosLatestPageState extends State<IosLatestPage> {
  late final _pager = Pager<ComicBrief>((offset) => MangaApi.instance.comics(offset: offset))..loadMore();

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListenableBuilder(
          listenable: _pager,
          builder: (context, _) => Stack(children: [
            NotificationListener<ScrollNotification>(
              onNotification: (n) => onScrollEnd(n, _pager.loadMore),
              child: CustomScrollView(physics: const BouncingScrollPhysics(), slivers: [
                SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).top + 52)),
                const SliverToBoxAdapter(child: LargeTitle('最近更新')),
                if (_pager.items.isEmpty && _pager.error != null)
                  SliverToBoxAdapter(child: IosNetworkError(message: _pager.error!, onRetry: _pager.refresh))
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.page),
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: Space.x3 + 2,
                        mainAxisSpacing: Space.x4 + 2,
                        mainAxisExtent: (MediaQuery.sizeOf(context).width - Space.page * 2 - (Space.x3 + 2) * 2) / 3 * kCoverAspect + Space.x2 + 40,
                      ),
                      itemCount: _pager.items.isEmpty && _pager.loading ? 9 : _pager.items.length,
                      itemBuilder: (context, i) => _pager.items.isEmpty ? const _GridPlaceholder() : _GridTile(comic: _pager.items[i]),
                    ),
                  ),
                SliverToBoxAdapter(child: _Footer(pager: _pager)),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ]),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 4,
              left: 16,
              child: GlassButton(icon: 'chevronLeft', label: '返回', onTap: () => Navigator.pop(context)),
            ),
          ]),
        ),
      );
}
