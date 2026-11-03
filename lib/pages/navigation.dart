import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/store.dart';
import 'detail_page.dart';
import 'manga_reader_page.dart';
import 'novel_reader_page.dart';

ComicBrief briefOf(ShelfEntry e) => ComicBrief(name: e.name, pathWord: e.id, cover: e.cover, authors: [e.author]);

Future<void> openDetail(BuildContext context, ComicBrief comic) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(comic: comic)));

Future<void> openReader(
  BuildContext context, {
  required ComicBrief comic,
  required String group,
  required String chapterUuid,
  int initialPage = 0,
}) =>
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MangaReaderPage(comic: comic, group: group, chapterUuid: chapterUuid, initialPage: initialPage),
    ));

/// 书架上的「继续阅读」：小说进阅读器，漫画有进度进阅读器，否则进详情。
Future<void> continueEntry(BuildContext context, ShelfEntry e) {
  if (e.kind == ShelfKind.novel) {
    return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NovelReaderPage()));
  }
  if (e.chapterUuid == null) return openDetail(context, briefOf(e));
  return openReader(
    context,
    comic: briefOf(e),
    group: e.group ?? 'default',
    chapterUuid: e.chapterUuid!,
    initialPage: e.page,
  );
}
