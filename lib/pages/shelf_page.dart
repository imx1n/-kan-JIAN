import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/shelf_sync.dart';
import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'home_shell.dart';
import 'navigation.dart';
import 'novel_reader_page.dart';
import 'search_page.dart';

class ShelfPage extends StatefulWidget {
  const ShelfPage({super.key});

  @override
  State<ShelfPage> createState() => _ShelfPageState();
}

enum _Filter { all, updated, ongoing, finished, novel }

class _ShelfPageState extends State<ShelfPage> {
  final _store = LibraryStore.instance;
  final _sync = ShelfSync.instance;
  final _prefs = ReaderPrefs.instance;
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _store.addListener(_changed);
    _sync.addListener(_changed);
    _prefs.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync.refresh());
  }

  @override
  void dispose() {
    _store.removeListener(_changed);
    _sync.removeListener(_changed);
    _prefs.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<ShelfEntry> get _sorted {
    final list = _store.entries;
    if (_prefs.shelfSort == 1) {
      // 按作品更新时间；没有同步过的排在后面，同一天按最近阅读。
      list.sort((a, b) {
        final c = b.latestUpdated.compareTo(a.latestUpdated);
        return c != 0 ? c : b.updatedAt.compareTo(a.updatedAt);
      });
    }
    return list;
  }

  bool _match(ShelfEntry e, _Filter f) => switch (f) {
        _Filter.all => true,
        _Filter.updated => e.hasUpdate,
        _Filter.ongoing => e.kind == ShelfKind.manga && !e.finished,
        _Filter.finished => e.kind == ShelfKind.manga && e.finished,
        _Filter.novel => e.kind == ShelfKind.novel,
      };

  @override
  Widget build(BuildContext context) {
    final all = _sorted;
    final visible = [for (final e in all) if (_match(e, _filter)) e];
    final updates = [for (final e in all) if (e.hasUpdate) e];
    final resume = visible.where((e) => e.started).firstOrNull;
    return SafeArea(
      bottom: false,
      child: Column(children: [
        _appBar(context),
        SizedBox(height: 2, child: _sync.running ? const LinearProgressIndicator(minHeight: 2, color: Palette.sage, backgroundColor: Colors.transparent) : null),
        if (all.isEmpty)
          const Expanded(child: _EmptyShelf())
        else ...[
          FilterChips(
            items: [
              ('全部', all.length, false),
              ('有更新', updates.length, updates.isNotEmpty),
              ('连载中', null, false),
              ('已完结', null, false),
              ('轻小说', null, false),
            ],
            selected: _filter.index,
            onSelect: (i) => setState(() => _filter = _Filter.values[i]),
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          ),
          Expanded(
            child: RefreshIndicator(
              color: Palette.ink,
              onRefresh: () => _sync.refresh(force: true),
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (resume != null) SliverToBoxAdapter(child: _ResumeCard(entry: resume)),
                  if (_filter == _Filter.all && updates.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: SectionHeader(
                        title: '有更新',
                        count: '${updates.length}',
                        trailing: HeaderAction(label: '全部', onTap: () => setState(() => _filter = _Filter.updated)),
                      ),
                    ),
                    SliverList.separated(
                      itemCount: updates.length.clamp(0, 3),
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 20, endIndent: 20, color: Palette.line),
                      itemBuilder: (context, i) => _UpdateRow(entry: updates[i]),
                    ),
                  ],
                  SliverToBoxAdapter(
                    child: SectionHeader(title: '书架', count: '${visible.length}', trailing: _sortMenu()),
                  ),
                  if (visible.isEmpty)
                    SliverToBoxAdapter(child: _FilterEmpty(filter: _filter))
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverGrid.builder(
                        // 高度 = 3:4 封面 + 两行书名 + 一行进度，按屏宽算，避免行间空白。
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 18,
                          mainAxisExtent: (MediaQuery.sizeOf(context).width - 40 - 28) / 3 * 4 / 3 + 8 + 38 + 2 + 18,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, i) => _ShelfTile(entry: visible[i], onMenu: () => _entryMenu(context, visible[i])),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 28)),
                ],
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _appBar(BuildContext context) => SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.only(left: 20, right: 6),
          child: Row(children: [
            const BrandMark(),
            const SizedBox(width: 10),
            const Text('栞间', style: TextStyle(fontFamily: kSerif, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 2, height: 1)),
            const Spacer(),
            ToolButton(
              icon: 'search',
              tooltip: '搜索作品',
              size: 48,
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
            ),
            ToolButton(icon: 'moreV', tooltip: '书架设置', size: 48, onTap: () => _shelfMenu(context)),
          ]),
        ),
      );

  Widget _sortMenu() => PopupMenuButton<int>(
        tooltip: '排序方式',
        initialValue: _prefs.shelfSort,
        onSelected: (v) => _prefs.shelfSort = v,
        color: Palette.bar,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 0, child: Text('最近阅读')),
          PopupMenuItem(value: 1, child: Text('更新时间')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(_prefs.shelfSort == 0 ? '最近阅读' : '更新时间', style: const TextStyle(fontSize: 12, color: Palette.ink2)),
            const SizedBox(width: 2),
            const AppIcon('down', size: 14, color: Palette.ink2),
          ]),
        ),
      );

  void _shelfMenu(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const AppIcon('refresh', size: 22),
              title: const Text('检查追更'),
              subtitle: Text(_sync.lastError == null ? '逐部获取最新章节' : '上次有作品没有同步成功：${_sync.lastError}', maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () {
                Navigator.pop(sheet);
                _sync.refresh(force: true);
              },
            ),
            ListTile(
              leading: const AppIcon('sort', size: 22),
              title: Text(_prefs.shelfSort == 0 ? '改为按更新时间排序' : '改为按最近阅读排序'),
              onTap: () {
                Navigator.pop(sheet);
                _prefs.shelfSort = _prefs.shelfSort == 0 ? 1 : 0;
              },
            ),
          ]),
        ),
      );

  void _entryMenu(BuildContext context, ShelfEntry e) => showModalBottomSheet<void>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const AppIcon('play', size: 20),
              title: Text(e.started ? '继续阅读' : '开始阅读'),
              onTap: () {
                Navigator.pop(sheet);
                continueEntry(context, e);
              },
            ),
            if (e.kind == ShelfKind.manga)
              ListTile(
                leading: const AppIcon('info', size: 22),
                title: const Text('查看详情'),
                onTap: () {
                  Navigator.pop(sheet);
                  openDetail(context, briefOf(e));
                },
              ),
            ListTile(
              leading: const AppIcon('trash', size: 22, color: Palette.accent),
              title: Text('从书架移除《${e.name}》', style: const TextStyle(color: Palette.accent)),
              onTap: () {
                Navigator.pop(sheet);
                _store.remove(e.id);
              },
            ),
          ]),
        ),
      );
}

class _ResumeCard extends StatelessWidget {
  const _ResumeCard({required this.entry});

  final ShelfEntry entry;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final where = e.kind == ShelfKind.manga && e.pageCount > 0 ? '${e.chapterName} · 第 ${e.page + 1} / ${e.pageCount} 页' : e.chapterName ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 16, 16),
      decoration: BoxDecoration(color: Palette.tonal, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => e.kind == ShelfKind.manga ? openDetail(context, briefOf(e)) : continueEntry(context, e),
          child: Book3D(
            rotateY: -11 * 3.14159 / 180,
            rotateZ: -2 * 3.14159 / 180,
            ribbon: true,
            elevation: .5,
            child: CoverImage(url: e.cover, title: e.name, width: 88, height: 124),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          // 高度随内容：书名可能两行，不能固定高度。
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 128),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Text('继续阅读', style: TextStyle(fontSize: 12, color: Palette.ink3)),
              const SizedBox(height: 4),
              Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: kSerif, fontSize: 19, height: 1.35, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Palette.ink2)),
              const SizedBox(height: 14),
              ProgressLine(e.progress),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text('本话 ${(e.progress * 100).round()}%', style: const TextStyle(fontSize: 12, color: Palette.ink3))),
                FilledButton(
                  onPressed: () => continueEntry(context, e),
                  style: FilledButton.styleFrom(backgroundColor: Palette.ink, minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 18)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('继续'),
                    SizedBox(width: 8),
                    AppIcon('arrow', size: 18, color: Palette.onInk),
                  ]),
                ),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.entry});

  final ShelfEntry entry;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => openDetail(context, briefOf(entry)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: SizedBox(
            height: 56,
            child: Row(children: [
              CoverImage(url: entry.cover, title: entry.name, width: 40, height: 54, radius: 3),
              const SizedBox(width: 12),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text('更新至 ${entry.latestChapter} · ${formatDay(entry.latestUpdated)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.ink3)),
                ]),
              ),
              const SizedBox(width: 10),
              NewBadge('新 ${entry.newCount} 话'),
            ]),
          ),
        ),
      );
}

class _ShelfTile extends StatelessWidget {
  const _ShelfTile({required this.entry, required this.onMenu});

  final ShelfEntry entry;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final meta = e.kind == ShelfKind.novel ? '轻小说 · ${e.started ? e.chapterName : '未开始'}' : e.placeLabel;
    return InkWell(
      onTap: () => e.kind == ShelfKind.manga ? openDetail(context, briefOf(e)) : continueEntry(context, e),
      onLongPress: onMenu,
      borderRadius: BorderRadius.circular(4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AspectRatio(
          aspectRatio: 3 / 4,
          child: LayoutBuilder(
            builder: (context, c) => Stack(children: [
              DecoratedBox(
                decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x24203028), blurRadius: 6, offset: Offset(0, 2))]),
                child: CoverImage(url: e.cover, title: e.name, width: c.maxWidth, height: c.maxHeight, radius: 3),
              ),
              if (e.hasUpdate)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(color: Palette.accent, borderRadius: BorderRadius.circular(4)),
                    child: const Center(widthFactor: 1, child: Text('更新', style: TextStyle(fontSize: 11, color: Palette.onInk))),
                  ),
                ),
              if (e.started && e.progress > 0 && e.progress < 1)
                Positioned(left: 6, right: 6, bottom: 6, child: ProgressLine(e.progress, background: const Color(0x8CFFFFFF))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Text(e.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.ink3)),
      ]),
    );
  }
}

class _FilterEmpty extends StatelessWidget {
  const _FilterEmpty({required this.filter});

  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final text = switch (filter) {
      _Filter.updated => '追更的作品暂时都没有新话。下拉可以重新检查。',
      _Filter.novel => '书架上还没有轻小说。',
      _ => '没有符合条件的作品。',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: const TextStyle(fontSize: 14, height: 1.7, color: Palette.ink2)),
        if (filter == _Filter.novel) ...[
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NovelReaderPage())),
            style: OutlinedButton.styleFrom(foregroundColor: Palette.ink, side: const BorderSide(color: Palette.line), minimumSize: const Size(0, 44)),
            child: const Text('打开示例《雨停之前》'),
          ),
        ],
      ]),
    );
  }
}

/// 首次使用：说明作品怎么进书架，并给出总榜前三。
class _EmptyShelf extends StatefulWidget {
  const _EmptyShelf();

  @override
  State<_EmptyShelf> createState() => _EmptyShelfState();
}

class _EmptyShelfState extends State<_EmptyShelf> {
  late final _top = MangaApi.instance.ranks(dateType: 'total', limit: 3);

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(28, 32, 28, 28), children: [
        SizedBox(
          height: 132,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            const _Spine(width: 30, height: 92),
            const SizedBox(width: 10),
            Stack(clipBehavior: Clip.none, children: [
              const _Spine(width: 36, height: 118),
              Positioned(
                right: 6,
                top: -1,
                child: ClipPath(clipper: _RibbonShape(), child: Container(width: 9, height: 26, color: Palette.accent)),
              ),
            ]),
            const SizedBox(width: 14),
            Transform.rotate(angle: .14, alignment: Alignment.bottomLeft, child: const _Spine(width: 30, height: 104)),
          ]),
        ),
        const Divider(height: 1, color: Palette.line),
        const SizedBox(height: 26),
        const Text('书架还空着', style: TextStyle(fontFamily: kSerif, fontSize: 22, height: 1.4, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        const Text('在「发现」里点作品的追更书签，它就会放到这里。有新话时，书架会标出更新，并记住你读到哪一页。',
            style: TextStyle(fontSize: 14, height: 1.75, color: Palette.ink2)),
        const SizedBox(height: 22),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton(
            onPressed: () => HomeShell.tab.value = 1,
            style: FilledButton.styleFrom(backgroundColor: Palette.ink, minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 22)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('去发现'), SizedBox(width: 8), AppIcon('arrow', size: 18, color: Palette.onInk)]),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
            style: FilledButton.styleFrom(backgroundColor: Palette.tonal2, foregroundColor: Palette.sageInk, minimumSize: const Size(0, 48), padding: const EdgeInsets.symmetric(horizontal: 22)),
            child: const Text('搜索作品'),
          ),
        ]),
        const SizedBox(height: 30),
        const Row(children: [
          Text('大家都在追', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          SizedBox(width: 8),
          Text('总榜前三', style: TextStyle(fontSize: 12, color: Palette.ink3)),
        ]),
        const SizedBox(height: 12),
        FutureBuilder<PageResult<RankItem>>(
          future: _top,
          builder: (context, snap) {
            if (snap.hasError) return Text('暂时拿不到排行：${snap.error}', style: const TextStyle(fontSize: 12, color: Palette.ink3));
            final items = snap.data?.list;
            return Row(children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: items == null || i >= items.length
                      ? const AspectRatio(aspectRatio: 3 / 4, child: Skeleton(height: double.infinity, radius: 3))
                      : InkWell(
                          onTap: () => openDetail(context, items[i].comic),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            AspectRatio(
                              aspectRatio: 3 / 4,
                              child: LayoutBuilder(builder: (context, c) => CoverImage(url: items[i].comic.cover, title: items[i].comic.name, width: c.maxWidth, height: c.maxHeight, radius: 3)),
                            ),
                            const SizedBox(height: 7),
                            Text(items[i].comic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          ]),
                        ),
                ),
              ],
            ]);
          },
        ),
      ]);
}

class _Spine extends StatelessWidget {
  const _Spine({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: Palette.line, width: 1.5),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3), bottom: Radius.circular(1)),
        ),
      );
}

class _RibbonShape extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..moveTo(0, 0)
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height)
    ..lineTo(s.width / 2, s.height * .78)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
