// 数据模型：字段名与接口原始响应保持一致（见 test/fixtures）。

String _str(Object? v) => v == null ? '' : v.toString();
int _int(Object? v) => v is int ? v : int.tryParse(_str(v)) ?? 0;
bool _bool(Object? v) => v == true;

/// `status` / `region` 等字段可能是数字，也可能是 `{value, display}`。
String _display(Object? v) => v is Map ? _str(v['display']) : _str(v);

List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

class PageResult<T> {
  const PageResult({
    required this.list,
    required this.total,
    required this.offset,
  });

  final List<T> list;
  final int total;
  final int offset;

  bool get hasMore => offset + list.length < total;

  static PageResult<T> parse<T>(
    Map<String, dynamic> r,
    T Function(Map<String, dynamic>) item,
  ) =>
      PageResult(
        list: _maps(r['list']).map(item).toList(),
        total: _int(r['total']),
        offset: _int(r['offset']),
      );
}

class ComicBrief {
  const ComicBrief({
    required this.name,
    required this.pathWord,
    required this.cover,
    this.authors = const [],
    this.popular = 0,
    this.updated = '',
    this.alias = '',
  });

  final String name;
  final String pathWord;
  final String cover;
  final List<String> authors;
  final int popular;
  final String updated;

  /// 搜索结果才有：逗号分隔的别名。
  final String alias;

  String get authorText => authors.isEmpty ? '佚名' : authors.join(' / ');

  /// 和书名明显不同的别名（含英文，或长度差超过 2），用于搜索结果的“又名”。
  String? get distinctAlias {
    for (final a in alias.split(RegExp('[,，]')).map((s) => s.trim())) {
      if (a.isEmpty || a == name) continue;
      if (RegExp('[A-Za-z]').hasMatch(a) || (a.length - name.length).abs() > 2) return a;
    }
    return null;
  }

  factory ComicBrief.fromJson(Map<String, dynamic> j) => ComicBrief(
        name: _str(j['name']),
        pathWord: _str(j['path_word']),
        cover: _str(j['cover']),
        authors: _maps(j['author']).map((a) => _str(a['name'])).toList(),
        popular: _int(j['popular']),
        updated: _str(j['datetime_updated']),
        alias: _str(j['alias']),
      );
}

class RankItem {
  const RankItem({required this.sort, required this.rise, required this.isNew, required this.comic});

  final int sort;

  /// 正数上升，负数下降，0 持平。
  final int rise;

  /// 上一期不在榜（`sort_last == 0`）。
  final bool isNew;
  final ComicBrief comic;

  factory RankItem.fromJson(Map<String, dynamic> j) {
    final sort = _int(j['sort']);
    final last = _int(j['sort_last']);
    return RankItem(
      sort: sort,
      rise: last == 0 ? 0 : last - sort,
      isNew: last == 0,
      comic: ComicBrief.fromJson(Map<String, dynamic>.from(j['comic'] as Map)),
    );
  }
}

class ComicGroup {
  const ComicGroup({required this.pathWord, required this.name, required this.count});

  final String pathWord;
  final String name;
  final int count;
}

class ComicDetail {
  const ComicDetail({
    required this.comic,
    required this.alias,
    required this.brief,
    required this.status,
    required this.region,
    required this.themes,
    required this.lastChapter,
    required this.groups,
    required this.isLock,
    required this.isVip,
  });

  final ComicBrief comic;
  final String alias;
  final String brief;
  final String status;
  final String region;
  final List<String> themes;
  final String lastChapter;
  final List<ComicGroup> groups;
  final bool isLock;
  final bool isVip;

  /// 所有分组的章节总数；追更用它判断有没有新话。
  int get chapterCount => groups.fold(0, (n, g) => n + g.count);

  bool get finished => status.contains('完結') || status.contains('完结');

  /// 别名里去掉和书名相同的项，最多取两个。
  List<String> get aliases => alias
      .split(RegExp('[,，]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && s != comic.name)
      .take(2)
      .toList();

  factory ComicDetail.fromJson(Map<String, dynamic> r) {
    final c = Map<String, dynamic>.from(r['comic'] as Map);
    // groups 是字典而不是数组：{"default": {...}, "tankobon": {...}}
    final rawGroups = r['groups'];
    final groups = <ComicGroup>[
      if (rawGroups is Map)
        for (final e in rawGroups.entries)
          if (e.value is Map)
            ComicGroup(
              pathWord: _str((e.value as Map)['path_word']).isEmpty
                  ? _str(e.key)
                  : _str((e.value as Map)['path_word']),
              name: _str((e.value as Map)['name']),
              count: _int((e.value as Map)['count']),
            ),
    ];
    final last = c['last_chapter'];
    return ComicDetail(
      comic: ComicBrief.fromJson(c),
      alias: _str(c['alias']),
      brief: _str(c['brief']),
      status: _display(c['status']),
      region: _display(c['region']),
      themes: _maps(c['theme']).map((t) => _str(t['name'])).toList(),
      lastChapter: last is Map ? _str(last['name']) : '',
      groups: groups,
      isLock: _bool(r['is_lock']),
      isVip: _bool(r['is_vip']),
    );
  }
}

/// 章节名里没有“话/話/卷”的条目（贺图、番外、特典）标「特别篇」，含“通知/公告”的标「公告」。名称本身不改。
String chapterTag(String name) {
  if (RegExp('通知|公告').hasMatch(name)) return '公告';
  if (!RegExp('[话話卷回]').hasMatch(name)) return '特别篇';
  return '';
}

/// 把 [total] 条章节按每 [size] 条分段，返回 (起始 offset, 条数)。
List<(int, int)> chapterRanges(int total, {int size = 100}) => [
      for (var start = 0; start < total; start += size) (start, total - start < size ? total - start : size),
    ];

class Chapter {
  const Chapter({
    required this.uuid,
    required this.name,
    required this.index,
    required this.size,
    required this.groupPathWord,
    this.prev,
    this.next,
    this.created = '',
  });

  final String uuid;
  final String name;
  final int index;

  /// 该话页数。
  final int size;
  final String groupPathWord;
  final String? prev;
  final String? next;
  final String created;

  factory Chapter.fromJson(Map<String, dynamic> j) {
    String? id(Object? v) => _str(v).isEmpty ? null : _str(v);
    return Chapter(
      uuid: _str(j['uuid']),
      name: _str(j['name']),
      index: _int(j['index']),
      size: _int(j['size']),
      groupPathWord: _str(j['group_path_word']),
      prev: id(j['prev']),
      next: id(j['next']),
      created: _str(j['datetime_created']),
    );
  }
}

class ChapterContent {
  const ChapterContent({
    required this.chapter,
    required this.images,
    required this.isLock,
  });

  final Chapter chapter;

  /// 顺序即阅读顺序。
  final List<String> images;
  final bool isLock;

  factory ChapterContent.fromJson(Map<String, dynamic> r) {
    final ch = Map<String, dynamic>.from(r['chapter'] as Map);
    return ChapterContent(
      chapter: Chapter.fromJson(ch),
      images: _maps(ch['contents']).map((c) => _str(c['url'])).where((u) => u.isNotEmpty).toList(),
      isLock: _bool(r['is_lock']),
    );
  }
}
