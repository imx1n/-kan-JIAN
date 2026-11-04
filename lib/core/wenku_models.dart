import 'dart:convert';

import 'package:fast_gbk/fast_gbk.dart';

import 'api.dart' show ApiException;

/// Wenku8 的模型。站点是 GBK 编码的 HTML，没有 JSON 接口，所以这里的模型只对
/// 「解析后的 HTML」负责，不直接接触网络。

/// 搜索 / 书目列表里的一本书。
class WenkuBook {
  const WenkuBook({required this.aid, required this.name, this.author = '', this.cover = '', this.delisted = false});

  final int aid;
  final String name;
  final String author;
  final String cover;

  /// 源站标了「因版权问题，该书已经下架」：目录可能还在，正文多半读不到。
  final bool delisted;

  /// 封面可以直接按 aid 拼出来，不需要请求书目页。
  static String coverOf(int aid) => 'https://img.wenku8.com/image/${aid ~/ 1000}/$aid/${aid}s.jpg';
}

/// 目录里的一卷。
class WenkuVolume {
  WenkuVolume({required this.vid, required this.name, required this.chapters});

  final int vid;
  final String name;
  final List<WenkuChapter> chapters;
}

/// 目录里的一章。[cid] 是正文页的文件名，[url] 里的 class 来自书目页。
class WenkuChapter {
  const WenkuChapter({required this.cid, required this.name, required this.volume, this.index = 0});

  final int cid;
  final String name;

  /// 所属卷的序号（从 0 开始）。
  final int volume;

  /// 在整本目录里的序号（从 0 开始），用于定位和「下一章」。
  final int index;
}

/// 一本书的完整目录。
class WenkuCatalog {
  const WenkuCatalog({required this.aid, required this.cls, required this.volumes, required this.chapters});

  final int aid;
  final int cls;
  final List<WenkuVolume> volumes;
  final List<WenkuChapter> chapters;
}

/// 正文：段落、插图，以及上一章 / 下一章。
class WenkuContent {
  const WenkuContent({
    required this.paragraphs,
    required this.images,
    this.previous,
    this.next,
  });

  final List<String> paragraphs;

  /// 正文里的插图地址（已过滤为站点自己的图床）。
  final List<String> images;
  final int? previous;
  final int? next;
}

/// 书架条目。`entryId` 是书架行自己的 id，移除时用它而不是 [aid]。
class WenkuShelfItem {
  const WenkuShelfItem({
    required this.entryId,
    required this.aid,
    required this.name,
    this.author = '',
    this.latest = '',
    this.bookmark = '',
    this.updated = '',
  });

  final int entryId;
  final int aid;
  final String name;
  final String author;

  /// 最新章节。
  final String latest;

  /// 书签（上次读到的章节），没有读过的为空。
  final String bookmark;
  final String updated;
}

/* ─────────── 解析 ─────────── */

/// 把响应字节解成字符串。
///
/// 源站是 GBK；但站点偶尔也会回 UTF-8（快照、部分跳转页）。GBK 编码的中文几乎不可能
/// 同时是合法的 UTF-8，所以先试严格 UTF-8，成功且含非 ASCII 就按 UTF-8 处理，
/// 否则按 GBK（无法解码的字节替换掉，不让一两个坏字节毁掉整页）。
String decodeGbk(List<int> bytes) {
  try {
    final s = utf8.decode(bytes);
    if (s.codeUnits.any((c) => c > 0x7F)) return s;
  } on FormatException {
    // 不是合法 UTF-8，按 GBK 处理。
  }
  return gbk.decode(bytes, allowMalformed: true);
}

/// 搜索关键词必须按 GBK 编码再 URL 编码，用 UTF-8 会得到 0 条结果。
///
/// 注意不能借用 `Uri.encodeComponent`：它按 UTF-8 编码字符，GBK 字节会被再转一次
/// （「刀」的 B5 B6 会变成 %C2%B5%C2%B6）。这里直接对字节做百分号编码。
String encodeGbkQuery(String q) {
  final out = StringBuffer();
  for (final b in gbk.encode(q)) {
    final ascii = (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A);
    if (ascii) {
      out.writeCharCode(b);
    } else {
      out.write('%${b.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '').trim();

String _unescape(String s) => s
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'");

/// 搜索结果页。三种情况：结果列表；没有结果；只有一条结果时源站直接跳到那本书的书目页。
List<WenkuBook> parseSearch(String html) {
  if (html.contains('没有搜索到') || html.contains('没有找到')) return const [];
  final out = <WenkuBook>[];
  final seen = <int>{};
  // 列表里每本书的书名链接包在 <b> 里，链接可能是绝对地址；作者在其后的「作者:xxx/分类:」。
  final titles = RegExp(r'<b>\s*<a[^>]*href="[^"]*/book/(\d+)\.htm"[^>]*>(.*?)</a>', dotAll: true).allMatches(html).toList();
  for (var k = 0; k < titles.length; k++) {
    final m = titles[k];
    final aid = int.tryParse(m.group(1)!);
    final name = _unescape(_stripTags(m.group(2)!));
    if (aid == null || name.isEmpty || !seen.add(aid)) continue;
    final end = k + 1 < titles.length ? titles[k + 1].start : (m.end + 1500).clamp(0, html.length);
    final seg = html.substring(m.end, end);
    final author = RegExp(r'作者[:：]\s*([^/<\r\n]+)').firstMatch(seg)?.group(1)?.trim() ?? '';
    out.add(WenkuBook(aid: aid, name: name, author: _unescape(author), cover: WenkuBook.coverOf(aid), delisted: seg.contains('已经下架')));
  }
  if (out.isEmpty) {
    final single = parseBookPage(html);
    if (single != null) out.add(single);
  }
  return out;
}

/// 书目页（`/book/{aid}.htm`）：书名、作者。认不出时返回 null。
WenkuBook? parseBookPage(String html) {
  final m = RegExp(r'/novel/\d+/(\d+)/index\.htm').firstMatch(html);
  final aid = int.tryParse(m?.group(1) ?? '');
  if (aid == null) return null;
  final title = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(html)?.group(1) ?? '';
  final name = _unescape(_stripTags(title)).replaceAll(RegExp(r'\s*[-_|].*$'), '').trim();
  final author = RegExp(r'作\s*者[：:]\s*(?:<[^>]*>)*([^<\r\n/]{1,40})').firstMatch(html)?.group(1)?.trim() ?? '';
  if (name.isEmpty) return null;
  return WenkuBook(aid: aid, name: name, author: _unescape(author), cover: WenkuBook.coverOf(aid));
}

/// jieqi 的错误页（「出现错误」+「错误原因」）。不是错误页返回 null。
String? parseSiteError(String html) {
  if (!html.contains('出现错误') && !html.contains('错误原因')) return null;
  final m = RegExp(r'错误原因[：:]\s*(?:<[^>]*>)*\s*([^<]{2,80})', dotAll: true).firstMatch(html);
  final text = _unescape(m?.group(1) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return text.isEmpty ? '源站返回了错误' : text;
}

/// 从书目页取 `class`，目录和正文的地址都要用。
int parseClass(String html, int aid) {
  final m = RegExp('/novel/(\\d+)/$aid/index\\.htm').firstMatch(html);
  if (m != null) return int.parse(m.group(1)!);
  throw const ApiException('书目页里没有目录入口，可能被源站拦截');
}

/// 目录页：卷用 `vcss` 的行，章用 `ccss` 的行，章按出现顺序归到最近的卷。
WenkuCatalog parseCatalog(String html, {required int aid, required int cls}) {
  final volumes = <WenkuVolume>[];
  final all = <WenkuChapter>[];
  final re = RegExp(
    r'<td class="(v|c)css"[^>]*?(?:vid="(\d+)")?[^>]*>(.*?)</td>',
    dotAll: true,
  );
  for (final m in re.allMatches(html)) {
    final kind = m.group(1)!;
    final body = m.group(3)!;
    if (kind == 'v') {
      volumes.add(WenkuVolume(vid: int.tryParse(m.group(2) ?? '') ?? 0, name: _unescape(_stripTags(body)), chapters: []));
      continue;
    }
    final link = RegExp(r'<a href="(\d+)\.htm">(.*?)</a>', dotAll: true).firstMatch(body);
    if (link == null) continue;
    final cid = int.tryParse(link.group(1)!);
    if (cid == null) continue;
    final ch = WenkuChapter(
      cid: cid,
      name: _unescape(_stripTags(link.group(2)!)),
      volume: volumes.isEmpty ? 0 : volumes.length - 1,
      index: all.length,
    );
    all.add(ch);
    if (volumes.isNotEmpty) volumes.last.chapters.add(ch);
  }
  return WenkuCatalog(aid: aid, cls: cls, volumes: volumes, chapters: all);
}

/// 正文页：`<div id="content">` 里的内容，段落由 `<br>` 分隔。
WenkuContent parseContent(String html) {
  // 插图各自包在 <div class="divimage"> 里，先拆掉这层，否则正文会在第一张图的 </div> 处被截断；
  // 站点水印在 <ul id="contentdp"> 里，一并去掉。
  final flat = html
      .replaceAllMapped(RegExp(r'<div class="divimage"[^>]*>(.*?)</div>', dotAll: true), (m) => m.group(1)!)
      .replaceAll(RegExp(r'<ul id="contentdp"[^>]*>.*?</ul>', dotAll: true), '');
  final m = RegExp(r'id="content"[^>]*>(.*?)</div>', dotAll: true).firstMatch(flat);
  if (m == null) throw const ApiException('没有拿到正文，可能需要登录或站点要求验证');
  var body = m.group(1)!;

  final images = <String>[];
  // 外链插图整段去掉（不留占位），站点自己图床的换成 [插图] 占位，交给阅读器插入。
  body = body.replaceAllMapped(RegExp(r'<img[^>]+src="([^"]+)"[^>]*>'), (m) {
    final src = m.group(1)!;
    // 正文插图带 class="imagecontent"；其余只认站点图床。
    if (!m.group(0)!.contains('imagecontent') && !_allowedImage(src)) return '';
    images.add(src);
    return '\n[插图]\n';
  });
  // 没有 src 的 img 也清掉。
  body = body.replaceAll(RegExp(r'<img[^>]*>'), '');

  final text = _unescape(
    body
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), ''),
  );
  final paragraphs = [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty && !line.trim().startsWith('本文来自')) line.trim(),
  ];

  int? nav(String label) {
    final m = RegExp('<a href="(\\d+)\\.htm"[^>]*>$label</a>').firstMatch(html);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  return WenkuContent(
    paragraphs: paragraphs,
    images: images,
    previous: nav('上一章') ?? nav('上一页'),
    next: nav('下一章') ?? nav('下一页'),
  );
}

/// 只放行站点自己的图床，正文里偶尔会混进外链。
bool _allowedImage(String url) {
  final host = Uri.tryParse(url)?.host ?? '';
  // pic.777743.xyz 是 2026-11 实测的插图图床（交付文档里没有）。
  return const {'img.wenku8.com', 'pic.wenku8.cn', 'pic.wenku8.com', 'pic.777743.xyz'}.contains(host);
}

/// 书架表格。空单元格必须保留，否则列位会错行。
List<WenkuShelfItem> parseShelf(String html) {
  final out = <WenkuShelfItem>[];
  for (final row in RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true).allMatches(html)) {
    final rowHtml = row.group(1)!;
    // 勾选框的属性顺序不固定（浏览器序列化后也可能变），只认「checkid」和 value。
    final box = RegExp(r'<input[^>]*checkid[^>]*>').firstMatch(rowHtml)?.group(0);
    final entryId = int.tryParse(RegExp(r'value="?(\d+)').firstMatch(box ?? '')?.group(1) ?? '');
    if (entryId == null) continue;
    final cells = [
      for (final c in RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true).allMatches(rowHtml))
        _unescape(_stripTags(c.group(1)!).replaceAll('&nbsp;', ' ')).replaceAll(RegExp(r'\s+'), ' ').trim(),
    ];
    // 书名链接可能是 /book/{aid}.htm，也可能是 readbookcase.php?aid={aid}&bid={条目}。
    final aid = int.tryParse(RegExp(r'/book/(\d+)\.htm|[?&]aid=(\d+)').firstMatch(rowHtml)?.let((m) => m.group(1) ?? m.group(2)) ?? '');
    if (aid == null) continue;
    String cell(int i) => i < cells.length ? cells[i] : '';
    out.add(WenkuShelfItem(
      entryId: entryId,
      aid: aid,
      name: cell(1),
      author: cell(2),
      latest: cell(3),
      bookmark: cell(4),
      updated: cell(5),
    ));
  }
  return out;
}

/// 判断是否已经登录：书架页含「退出」链接即可。被 Cloudflare 挡住时不算登录。
bool looksLoggedIn(String html) => html.contains('退出') || html.contains('logout');

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
