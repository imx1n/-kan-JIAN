import 'package:flutter/material.dart';

/// 轻小说分页引擎。
///
/// 按可用宽高把一章正文切成若干页：段落在页边界处切开，续页不重复段首缩进。
/// 排版与设计稿一致——段间留白、不缩进、两端对齐，所以测量和渲染用的是同一份
/// 纯文本（首行缩进那种 `WidgetSpan` 没法参与 [TextPainter] 的行度量，见
/// 2026-11-05 的测量实验）。
///
/// 插图按出现顺序占据一个整页高度的槽位，不跨页切断。

/// 一页的内容。
class NovelPage {
  const NovelPage(this.blocks);

  final List<NovelBlock> blocks;

  bool get isEmpty => blocks.isEmpty;
}

/// 页内的一段内容：正文片段或插图。
sealed class NovelBlock {
  const NovelBlock();
}

class NovelTextBlock extends NovelBlock {
  const NovelTextBlock(this.text, {required this.paragraphStart, required this.paragraphEnd});

  final String text;

  /// 这一段是不是某一段落的开头（只有段落开头的片段需要和上一段留空）。
  final bool paragraphStart;

  /// 这一段是不是某一段落的结尾（后面要不要留段间距）。
  final bool paragraphEnd;
}

class NovelImageBlock extends NovelBlock {
  const NovelImageBlock(this.url);

  final String url;
}

/// 章末卡片（下一章、加入书架）：占一个固定高度，避免分页算完之后被裁掉。
class NovelEndBlock extends NovelBlock {
  const NovelEndBlock({this.height = 132});

  final double height;
}

/// 插图占位高度：宽度 × 这个比例。真实高度要等图片解码，分页不能等，
/// 所以统一按竖版插图的常见比例留位，图片用 contain 居中放在里面。
const kNovelImageRatio = 1.3;

/// 把 [blocks]（[String] 段落或 [NovelImageBlock]）切成页。
///
/// [style] 必须和渲染时完全一致（含 fontSize / height / letterSpacing），
/// [width] 是正文可用宽度（已扣掉左右内边距），[height] 是可用高度。
List<NovelPage> paginateNovel(
  List<Object> blocks, {
  required TextStyle style,
  required double width,
  required double height,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  if (width <= 0 || height <= 0) return const [];

  final pages = <NovelPage>[];
  var current = <NovelBlock>[];
  var left = height;

  void flush() {
    if (current.isEmpty) return;
    pages.add(NovelPage(current));
    current = <NovelBlock>[];
    left = height;
  }

  // 段间距：与设计稿的 1.2em 接近，按字号算，随字号缩放。
  final gap = (style.fontSize ?? 18) * .9;

  for (final block in blocks) {
    if (block is NovelEndBlock) {
      // 章末卡片：放不下就单独起一页，保证按钮不被裁掉。
      if (current.isNotEmpty && left < block.height) flush();
      current.add(block);
      left -= block.height;
      if (left <= 0) flush();
      continue;
    }
    if (block is NovelImageBlock) {
      final need = width * kNovelImageRatio;
      // 一页放不下整张图就翻页；单页比图还矮时也只能放在本页并裁掉溢出。
      if (current.isNotEmpty && left < need + (current.isEmpty ? 0 : gap)) {
        flush();
      }
      if (current.isNotEmpty) {
        left -= gap;
      }
      current.add(block);
      left -= need;
      if (left <= 0) flush();
      continue;
    }
    if (block is! String || block.trim().isEmpty) continue;

    var rest = block;
    var first = true;
    while (rest.isNotEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: rest, style: style),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.justify,
        textScaler: textScaler,
      )..layout(maxWidth: width);

      final cut = _cut(tp, rest, left);
      tp.dispose();

      if (cut.head.isEmpty) {
        // 这一页连一行都放不下：换页重来。
        flush();
        continue;
      }
      final ends = cut.tail.isEmpty;
      current.add(NovelTextBlock(cut.head, paragraphStart: first, paragraphEnd: ends));
      left -= cut.used;
      rest = cut.tail;
      first = false;
      if (!ends) {
        flush();
      } else if (left > 0) {
        left -= gap;
        if (left <= 0) flush();
      }
    }
  }
  flush();
  return pages;
}

typedef _Cut = ({String head, String tail, double used});

/// 从 [text] 里切出能塞进 [available] 高度的部分。
_Cut _cut(TextPainter tp, String text, double available) {
  final lines = tp.computeLineMetrics();
  if (lines.isEmpty) return (head: '', tail: text, used: 0);
  if (available <= 0) return (head: '', tail: text, used: 0);

  var used = 0.0;
  var last = -1;
  for (var i = 0; i < lines.length; i++) {
    final h = lines[i].height;
    if (used + h > available + .01) break;
    used += h;
    last = i;
  }
  if (last == lines.length - 1) return (head: text, tail: '', used: used);
  if (last < 0) return (head: '', tail: text, used: 0);

  // [used] 正好是下一行的顶边，取这一行行首的字符下标。
  final pos = tp.getPositionForOffset(Offset(0, used + .5)).offset.clamp(0, text.length);
  if (pos <= 0 || pos >= text.length) return (head: text, tail: '', used: used);
  return (head: text.substring(0, pos), tail: text.substring(pos), used: used);
}

/// 把一章正文和插图整理成分页输入：解析时用 `[插图]` 占位，这里按顺序换成图片。
List<Object> novelBlocksOf(List<String> paragraphs, List<String> images) {
  final out = <Object>[];
  var i = 0;
  for (final p in paragraphs) {
    if (p == kNovelImagePlaceholder && i < images.length) {
      out.add(NovelImageBlock(images[i++]));
    } else if (p != kNovelImagePlaceholder) {
      out.add(p);
    }
  }
  return out;
}

/// 解析器给插图留的占位段落。
const kNovelImagePlaceholder = '[插图]';
