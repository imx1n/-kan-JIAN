import 'package:flutter/material.dart';

import '../core/models.dart';
import '../pages/common.dart';
import 'theme.dart';
import 'widgets.dart';

/// 排行行：名次（前三锈红）、封面、书名、作者、人气、名次变化。
class RankRow extends StatelessWidget {
  const RankRow({super.key, required this.item, required this.onTap});

  final RankItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = item;
    final top = r.sort <= 3;
    final Widget delta = r.isNew
        ? const Pill('新', background: Palette.accentSoft, color: Palette.accent, bold: true)
        : Text(
            r.rise > 0 ? '▲${r.rise}' : (r.rise < 0 ? '▼${-r.rise}' : '—'),
            style: TextStyle(fontSize: 12, color: r.rise > 0 ? Palette.accent : (r.rise < 0 ? Palette.sageInk : Palette.ink4), fontFeatures: const [FontFeature.tabularFigures()]),
          );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          SizedBox(
            width: 26,
            child: Text('${r.sort}',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: kSerif, fontSize: top ? 20 : 17, fontWeight: FontWeight.w600, color: top ? Palette.accent : Palette.ink3)),
          ),
          const SizedBox(width: 12),
          CoverImage(url: r.comic.cover, title: r.comic.name, width: 48, height: 64, radius: 3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.comic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 3),
              Text(r.comic.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.ink3)),
              const SizedBox(height: 3),
              Text('人气 ${formatPopular(r.comic.popular)}', style: const TextStyle(fontSize: 12, color: Palette.ink2)),
            ]),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 40, child: Align(alignment: Alignment.centerRight, child: delta)),
        ]),
      ),
    );
  }
}

/// 搜索结果：命中的关键词标锈红，有明显不同的别名时显示「又名」。
class ResultRow extends StatelessWidget {
  const ResultRow({super.key, required this.comic, required this.query, required this.onTap});

  final ComicBrief comic;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final alias = comic.distinctAlias;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CoverImage(url: comic.cover, title: comic.name, width: 60, height: 80, radius: 3),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(highlight(comic.name, query), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w500)),
              if (alias != null) ...[
                const SizedBox(height: 3),
                Text('又名 $alias', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.ink3)),
              ],
              const SizedBox(height: 6),
              Row(children: [
                Flexible(child: Text(comic.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Palette.ink2))),
                const SizedBox(width: 10),
                Text('人气 ${formatPopular(comic.popular)}', style: const TextStyle(fontSize: 12, color: Palette.ink2)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// 把 [text] 中所有 [query] 标成锈红加粗。
TextSpan highlight(String text, String query) {
  if (query.isEmpty || !text.contains(query)) return TextSpan(text: text);
  final parts = text.split(query);
  return TextSpan(children: [
    for (var i = 0; i < parts.length; i++) ...[
      TextSpan(text: parts[i]),
      if (i < parts.length - 1) TextSpan(text: query, style: const TextStyle(color: Palette.accent, fontWeight: FontWeight.w600)),
    ],
  ]);
}

/// 横滑小封面（今日更新、离线可读）。
class MiniTile extends StatelessWidget {
  const MiniTile({super.key, required this.comic, required this.onTap, this.subtitle});

  final ComicBrief comic;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 96,
        child: InkWell(
          onTap: onTap,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CoverImage(url: comic.cover, title: comic.name, width: 96, height: 128, radius: 3),
            const SizedBox(height: 7),
            Text(comic.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.4, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(subtitle ?? comic.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Palette.ink3)),
          ]),
        ),
      );
}

class ComicGridTile extends StatelessWidget {
  const ComicGridTile({super.key, required this.comic, required this.onTap});

  final ComicBrief comic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => DecoratedBox(
                decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x1A203028), blurRadius: 6, offset: Offset(0, 2))]),
                child: CoverImage(url: comic.cover, title: comic.name, width: c.maxWidth, height: c.maxHeight, radius: 3),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(comic.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 2),
          Text(comic.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Palette.ink3)),
        ]),
      );
}

/// 列表行的骨架，形状与 [RankRow] 一致。
class RowSkeleton extends StatelessWidget {
  const RowSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          Skeleton(width: 26, height: 18),
          SizedBox(width: 12),
          Skeleton(width: 48, height: 64, radius: 3),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FractionallySizedBox(widthFactor: .7, child: Skeleton(height: 15)),
              SizedBox(height: 8),
              FractionallySizedBox(widthFactor: .4, child: Skeleton(height: 12)),
              SizedBox(height: 6),
              FractionallySizedBox(widthFactor: .3, child: Skeleton(height: 12)),
            ]),
          ),
        ]),
      );
}

/// Pager 驱动的列表底部：首屏为骨架/错误面板，之后为加载中/重试/到底。
class PagerFooter extends StatelessWidget {
  const PagerFooter({super.key, required this.pager, this.emptyText = '没有找到作品', this.skeletonRows = 4});

  final Pager<Object?> pager;
  final String emptyText;
  final int skeletonRows;

  @override
  Widget build(BuildContext context) {
    final first = pager.items.isEmpty;
    if (pager.error != null) {
      return first
          ? ApiErrorPanel(message: pager.error!, onRetry: pager.loadMore)
          : SizedBox(height: 72, child: Center(child: TextButton(onPressed: pager.loadMore, child: Text('加载失败，点按重试（${pager.error}）', maxLines: 1, overflow: TextOverflow.ellipsis))));
    }
    if (pager.loading) {
      return first ? Column(children: [for (var i = 0; i < skeletonRows; i++) const RowSkeleton()]) : const SizedBox(height: 72, child: LoadingView());
    }
    if (!pager.hasMore) {
      return SizedBox(
        height: 72,
        child: Center(child: Text(first ? emptyText : '— 已经到底了 —', style: const TextStyle(fontSize: 12, color: Palette.ink3))),
      );
    }
    return const SizedBox(height: 72);
  }
}
