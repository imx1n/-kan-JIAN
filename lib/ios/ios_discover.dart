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
import '../ui/widgets.dart' show CoverCaption, CoverImage, Pager, coverHeightFor, kCoverAspect, onScrollEnd;
import 'ios_app.dart';
import 'ios_mine.dart' show iosEditProxy;
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
            SliverToBoxAdapter(
              child: _SearchField(onTap: (rect) => openSearch(context, origin: rect)),
            ),
            SliverToBoxAdapter(
              // 上留白由 [TextChips] 自己出（它上下同值），这里不再套 padding——
              // 外面再写一份就会变成「发现页松、书架页紧」。
              child: TextChips(items: [('全部题材', null, false), for (final t in AppConfig.themes) (t.$1, null, false)], selected: _theme, onSelect: _selectTheme),
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
        child: IosSection(
          '今日更新',
          // 上留白由 [TextChips] 自己出，这里不再补。
          //
          // 真机量：胶囊上沿到搜索框底 7.6dp，胶囊下沿到标题墨迹原本 23.6dp——
          // 三倍。多出来的是胶囊自己的 [TextChips.below] 8 之外又补了一层区块
          // 上留白。归零之后下段只剩胶囊那 8，加上标题行框自身在 21×1.2 里的
          // 上半 leading（约 7），墨迹落在 15 上下——和上面的 7.6 同一个量级，
          // 不再往下塌一大截。
          top: 0,
          action: '更多',
          onAction: () => Navigator.of(context).push(appRoute((_) => const IosLatestPage())),
        ),
      ),
      // 横排卡片的高度按内容算，不写死 206。
      //
      // 写死的时候，一行的书名比两行的矮 18dp，卡片框却还是 206——底下多出来
      // 的空白直接叠进「人气排行」的上留白，于是它和「今日更新」前面永远差一截。
      // 内容占多少就占多少，区块间距才只由一个值决定。
      SliverToBoxAdapter(child: SizedBox(height: _railExtent(context), child: _latestRow())),
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
          // 上留白归胶囊：这一行同样紧跟在题材胶囊下面，和「今日更新」一样
          // 不能再补 [Space.beforeSection]——胶囊已经出了 8，再叠 16 就是
          // 胶囊下沿到标题 30+，而上沿到搜索框只有 7.6。
          padding: const EdgeInsets.fromLTRB(Space.page, 0, Space.page, Space.afterSection),
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
              mainAxisExtent: (MediaQuery.sizeOf(context).width - Space.page * 2 - (Space.x3 + 2) * 2) / 3 * kCoverAspect + CoverCaption.extent(MediaQuery.textScalerOf(context)),
            ),
            itemCount: pager.items.isEmpty && pager.loading ? 6 : pager.items.length,
            itemBuilder: (context, i) => pager.items.isEmpty ? const _GridPlaceholder() : _GridTile(comic: pager.items[i]),
          ),
        ),
      SliverToBoxAdapter(child: _Footer(pager: pager)),
    ];
  }

  /// 横排卡片一格的高度：封面 + 书名两行 + 作者一行，全按真实行高算。
  /// 和书架、发现网格一样把书名固定成两行高，一行书名不会让下面那行往上飘。
  static const _railWidth = 104.0;
  static const _railGapCover = 7.0;
  static const _railNameSize = 14.0;
  static const _railNameLine = 1.3;
  static const _railGapMeta = 2.0;
  static const _railMetaSize = 12.0;
  static const _railMetaLine = 1.45;

  static double _railExtent(BuildContext context) {
    final s = MediaQuery.textScalerOf(context);
    return coverHeightFor(_railWidth) +
        _railGapCover +
        s.scale(_railNameSize) * _railNameLine * 2 +
        _railGapMeta +
        s.scale(_railMetaSize) * _railMetaLine;
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
              width: _railWidth,
              child: list == null
                  ? Builder(builder: (context) {
                      // 骨架的高度要按**缩放后**的字号算，否则系统字号放大时
                      // 数据一回来整排文字块会突然长高，卡片弹一下。尺寸仍然
                      // 取真卡片的常量，只是和 [_railExtent] 用同一套折算。
                      final s = MediaQuery.textScalerOf(context);
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Redacted(width: _railWidth, height: coverHeightFor(_railWidth)),
                        const SizedBox(height: _railGapCover),
                        Redacted(width: 84, height: s.scale(_railNameSize)),
                        const SizedBox(height: _railGapMeta),
                        Redacted(width: 56, height: s.scale(_railMetaSize)),
                      ]);
                    })
                  : Pressable(
                      onTap: () => iosOpenDetail(context, list[i]),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        CoverImage(url: list[i].cover, title: list[i].name, width: _railWidth, height: coverHeightFor(_railWidth), radius: 6),
                        const SizedBox(height: _railGapCover),
                        // 书名固定两行高、贴底对齐：一行书名和两行书名的作者行
                        // 落在同一条基线上，也不会把卡片撑高。
                        SizedBox(
                          height: MediaQuery.textScalerOf(context).scale(_railNameSize) * _railNameLine * 2,
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(list[i].name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: _railNameSize, height: _railNameLine, fontWeight: FontWeight.w600, color: IosColors.ink)),
                          ),
                        ),
                        const SizedBox(height: _railGapMeta),
                        // 作者行同样钉死高度，理由和上面书名一样，但这里更隐蔽：
                        // 行高写 1.45 × 12 = 17.4，可 CJK 回退字体的 ascent+descent
                        // 更大，RenderParagraph 会把行框抬到 19.0——比算出来的多 1.6，
                        // 于是整列超出 [_railExtent] 报「overflowed by 1.6 pixels」。
                        // 盒子高度直接定义行框，多出来的部分被裁掉而不是往下挤。
                        SizedBox(
                          height: MediaQuery.textScalerOf(context).scale(_railMetaSize) * _railMetaLine,
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Text(list[i].authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: _railMetaSize, height: _railMetaLine, color: IosColors.muted)),
                          ),
                        ),
                      ]),
                    ),
            ),
          );
        },
      );
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});

  /// 回调带上搜索框自身的屏幕矩形：搜索页从这块区域缩放展开。
  final ValueChanged<Rect?> onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.page),
        child: Builder(
          // Builder 拿到的是搜索框自己的 context，rectOf 才能量到它的位置。
          builder: (inner) => Pressable(
            onTap: () => onTap(rectOf(inner)),
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
          // 规格和书架网格共用 [CoverCaption]：同一个三列网格，两页不能一个
          // 8/15/13、一个 7/14/12，也不能一边固定两行、一边只给一行。
          const SizedBox(height: CoverCaption.gapAfterCover),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(CoverCaption.nameSize) * CoverCaption.nameLine * CoverCaption.nameLines,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                comic.name,
                maxLines: CoverCaption.nameLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: CoverCaption.nameSize, height: CoverCaption.nameLine, fontWeight: FontWeight.w600, color: IosColors.ink),
              ),
            ),
          ),
          const SizedBox(height: CoverCaption.gapNameMeta),
          // 作者行钉死高度：13 × 1.45 = 18.85，而 CJK 回退字体的行框是 19.0，
          // 多出的 0.15 只能由格子吸收，于是格子报「overflowed by 0.15 pixels」。
          // 和上面书名、横排卡片一样，盒子定义行框，多的部分裁掉而不是往下挤。
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(CoverCaption.metaSize) * CoverCaption.metaLine,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(comic.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: CoverCaption.metaSize, height: CoverCaption.metaLine, color: IosColors.muted)),
            ),
          ),
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
              AnimatedRotation(turns: _open ? .5 : 0, duration: Motion.of(context, 180), curve: Motion.ease, child: AppIcon('down', size: 13, color: IosColors.muted, stroke: 2)),
            ]),
          ),
        ),
        AnimatedSize(
          duration: Motion.of(context, 200),
          curve: Motion.ease,
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
                        mainAxisExtent: (MediaQuery.sizeOf(context).width - Space.page * 2 - (Space.x3 + 2) * 2) / 3 * kCoverAspect + CoverCaption.extent(MediaQuery.textScalerOf(context)),
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
