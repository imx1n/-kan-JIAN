import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/shelf_sync.dart';
import '../core/store.dart';
import '../core/wenku.dart';
import '../ui/format.dart' show formatDay;
import '../ui/icons.dart';
import '../ui/motion.dart';
import '../ui/tokens.dart' show Dock, Space;
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
    // 已登录轻小说账号时，源站的轻小说会一起移出源站书架，菜单里写明。
    final syncRemove = wenkuAidOf(e.id) != null && WenkuService.instance.loggedIn;
    final options = [e.started ? '继续阅读' : '开始阅读', if (e.kind == ShelfKind.manga) '查看详情', syncRemove ? '移出书架（源站同步移出）' : '移出书架'];
    final i = await showIosChoices(context, title: e.name, options: options, destructiveIndex: options.length - 1);
    if (!mounted || i == null) return;
    if (i == 0) iosContinue(context, e);
    if (options[i] == '查看详情') iosOpenDetail(context, briefOfEntry(e));
    if (i == options.length - 1) {
      // 已登录时，源站的轻小说一起移出源站书架；否则只移出本机书架。
      final aid = wenkuAidOf(e.id);
      if (aid != null && WenkuService.instance.loggedIn) {
        await wenkuSetOnShelf(context, aid: aid, name: e.name, author: e.author, add: false);
      } else {
        _store.unfollow(e.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _sorted;
    final visible = [for (final e in all) if (_match(e)) e];
    final updates = [for (final e in all) if (e.hasUpdate) e];
    final resume = visible.where((e) => e.started).firstOrNull;
    // 「最近在读」已经在上面用大卡片展示过，藏书网格里就不再出现第二遍。
    // 同一本书两个尺寸、两种封面呈现方式并排摆着，视觉上非常撕裂。
    final gridItems = [for (final e in visible) if (!identical(e, resume)) e];
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
              count: '${gridItems.length}',
              action: _prefs.shelfSort == 0 ? '最近阅读' : '更新时间',
              actionIcon: 'down',
              onAction: () async {
                final i = await showIosChoices(context, title: '排序', options: const ['最近阅读', '更新时间'], selected: _prefs.shelfSort);
                if (i != null) _prefs.shelfSort = i;
              },
            ),
          ),
          // 只有一本、而且正好是「最近在读」时，网格是空的——这时不显示空态文案，
          // 上方那张续读卡片已经是完整的入口。
          if (gridItems.isEmpty && visible.isEmpty)
            SliverToBoxAdapter(child: _FilterEmpty(novel: _filter == _Filter.novel, updated: _filter == _Filter.updated))
          else if (gridItems.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.page),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: Space.x3 + 2,
                  mainAxisSpacing: Space.x4 + 2,
                  // 高度 = 封面 + 文字块。文字块由 _Tile 自己算（行高写死），
                  // 这里不能再手抄一份魔术数——两边只要差 1px 就会报溢出。
                  mainAxisExtent:
                      (MediaQuery.sizeOf(context).width - Space.page * 2 - (Space.x3 + 2) * 2) / 3 * 4 / 3 + _Tile.spaceBelowCover(MediaQuery.textScalerOf(context)),
                ),
                itemCount: gridItems.length,
                itemBuilder: (context, i) => _Tile(entry: gridItems[i], onLongPress: () => _entryMenu(gridItems[i])),
              ),
            ),
        ],
        SliverToBoxAdapter(child: SizedBox(height: Dock.clearance(context))),
      ],
    );
  }
}

/// 最近在读：一条轻量续读入口，不抢藏书的层级。
///
/// 封面按藏书系列的语法收小到 74×103，进度条挪回封面下沿，
/// 「继续阅读」从悬浮胶囊改成行内文字——整块高度比原来少约 70。
class _Resume extends StatelessWidget {
  const _Resume({required this.entry});

  final ShelfEntry entry;

  static const _coverW = 74.0;
  static const _coverH = _coverW * 417 / 299;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final where = e.kind == ShelfKind.manga && e.pageCount > 0 ? '${e.chapterName} · ${e.page + 1} / ${e.pageCount} 页' : (e.chapterName ?? '');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Pressable(
          onTap: () => e.kind == ShelfKind.manga ? iosOpenDetail(context, briefOfEntry(e)) : iosContinue(context, e),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [BoxShadow(color: Color(0x14202124), blurRadius: 9, offset: Offset(0, 3))],
            ),
            child: SizedBox(
              width: _coverW,
              height: _coverH,
              child: Stack(children: [
                CoverImage(url: e.cover, title: e.name, width: _coverW, height: _coverH, radius: 6),
                // 内描边：浅色封面不至于和页面底色糊在一起。
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: const Color(0x08222222), width: 1))),
                  ),
                ),
                // 进度贴封面下沿：和藏书封面的语法一致，不再单拉一条长进度条。
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 6,
                  height: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Stack(children: [
                      const Positioned.fill(child: ColoredBox(color: Color(0xB3F7F7FA))),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: e.progress.clamp(0.0, 1.0),
                        child: ColoredBox(color: IosColors.accent),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('最近在读', style: TextStyle(fontSize: 12, height: 18 / 12, color: IosColors.muted)),
            const SizedBox(height: 3),
            Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 19, height: 27 / 19, fontWeight: FontWeight.w600, letterSpacing: .1, color: IosColors.ink)),
            const SizedBox(height: 3),
            Text(where, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 20 / 13, color: IosColors.muted, fontFeatures: const [FontFeature.tabularFigures()])),
            Pressable(
              onTap: () => iosContinue(context, e),
              child: Container(
                constraints: const BoxConstraints(minHeight: 32),
                margin: const EdgeInsets.only(top: 4),
                alignment: Alignment.centerLeft,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('继续阅读', style: TextStyle(fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w600, color: IosColors.accent)),
                  const SizedBox(width: 7),
                  AppIcon('arrow', size: 16, color: IosColors.accent, stroke: 1.7),
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

  // 封面以下那三行动作的高度必须可算。行高一律写死，不能交给字体度量——
  // 各家 ROM 的默认字体 ascent+descent 不一样，差出来的零点几像素
  // 会被 SliverGrid 报成「BOTTOM OVERFLOWED BY 1.00 PIXELS」。
  static const _gapAfterCover = 8.0;
  static const _nameSize = 15.0;
  static const _nameLines = 2;
  static const _nameLine = 1.3;
  static const _gapNameMeta = 2.0;
  static const _metaSize = 13.0;
  static const _metaLine = 1.45;

  /// 封面下方（封面底边到格子底边）需要的高度，网格的 `mainAxisExtent` 直接用它。
  static double spaceBelowCover(TextScaler scaler) =>
      _gapAfterCover +
      scaler.scale(_nameSize) * _nameLine * _nameLines +
      _gapNameMeta +
      scaler.scale(_metaSize) * _metaLine;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final meta = e.kind == ShelfKind.novel ? '轻小说 · ${e.started ? e.chapterName : '未开始'}' : e.placeLabel;
    return Pressable(
      onTap: () => e.kind == ShelfKind.manga ? iosOpenDetail(context, briefOfEntry(e)) : iosContinue(context, e),
      onLongPress: onLongPress,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 封面吃掉「格子高度 − 文字块」，而不是自己按 3:4 定高。
        // 原来用 AspectRatio 让封面按宽度算高，网格的 mainAxisExtent 又另算一份，
        // 两边差零点几像素就报溢出；这样封面永远是那个余量，结构上不可能溢出，
        // 比例也只差千分之几。
        Expanded(
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
        SizedBox(height: _gapAfterCover),
        Text(e.name, maxLines: _nameLines, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: _nameSize, height: _nameLine, color: IosColors.ink)),
        const SizedBox(height: _gapNameMeta),
        Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: _metaSize, height: _metaLine, color: IosColors.muted)),
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
            TextAction(label: '登录轻小说账号，同步源站书架', onTap: () => Navigator.of(context).push(appRoute<void>((_) => const IosWenkuPage()))),
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
            TextAction(label: '搜索作品', onTap: () => Navigator.of(context).push(appRoute((_) => const IosSearchPage()))),
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
