import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../core/wenku.dart';
import '../core/wenku_models.dart';
import '../ui/format.dart' show formatPopular;
import '../ui/icons.dart';
import '../ui/widgets.dart' show CoverImage, Pager, coverHeightFor, onScrollEnd;
import 'ios_app.dart';
import 'ios_discover.dart' show IosNetworkError;
import 'ios_theme.dart';
import 'ios_wenku.dart' show WenkuShelfButton;

/// 搜索：漫画接口始终按「全部」搜（作品名和作者一起）。接口自带的按类型搜索是模糊匹配、并不可靠，
/// 所以「作品名 / 作者」页签在已载入的结果里按字段筛选，不足一屏时自动再载入下一页。
class IosSearchPage extends StatefulWidget {
  const IosSearchPage({super.key});

  @override
  State<IosSearchPage> createState() => _IosSearchPageState();
}

class _IosSearchPageState extends State<IosSearchPage> {
  final _input = TextEditingController();
  final _prefs = ReaderPrefs.instance;
  String _query = '';

  /// 0 全部、1 作品名、2 作者、3 轻小说（Wenku8，切过去才搜，避免每次都多发请求、撞上源站的搜索间隔）。
  int _scope = 0;

  List<WenkuBook> _novels = const [];
  bool _novelLoading = false;
  String? _novelError;
  bool _novelByAuthor = false;

  /// 上一次轻小说搜索的「方式|关键词」，相同就不重复请求。
  String? _novelKey;
  late final _pager = Pager<ComicBrief>((offset) => MangaApi.instance.search(_query, offset: offset));

  @override
  void dispose() {
    _input.dispose();
    _pager.dispose();
    super.dispose();
  }

  void _submit(String q) {
    q = q.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    _input.text = q;
    _prefs.addSearch(q);
    setState(() => _query = q);
    _pager.refresh();
    if (_scope == 3) _searchNovels();
  }

  void _flipNovelMode() {
    setState(() => _novelByAuthor = !_novelByAuthor);
    _searchNovels();
  }

  Future<void> _searchNovels({bool force = false}) async {
    final key = '$_novelByAuthor|$_query';
    if (_query.isEmpty || (!force && key == _novelKey)) return;
    _novelKey = key;
    setState(() {
      _novelLoading = true;
      _novelError = null;
    });
    try {
      final r = await WenkuService.instance.search(_query, byAuthor: _novelByAuthor);
      if (!mounted || key != _novelKey) return;
      setState(() {
        _novels = r;
        _novelLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || key != _novelKey) return;
      setState(() {
        _novelError = e.message;
        _novelLoading = false;
        _novelKey = null;
      });
    }
  }

  bool _match(ComicBrief c) {
    final q = _query.toLowerCase();
    return switch (_scope) {
      1 => c.name.toLowerCase().contains(q) || c.alias.toLowerCase().contains(q),
      2 => c.authorText.toLowerCase().contains(q),
      _ => true,
    };
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: IosColors.bg,
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              child: Row(children: [
                Expanded(
                  // 轻玻璃胶囊：浅灰实底 + 细亮边，在近白背景上也看得清。
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: IosColors.isDark ? IosColors.dFaint : const Color(0xFFEFEFF3),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: IosColors.isDark ? const Color(0x1FFFFFFF) : const Color(0xB3FFFFFF), width: .8),
                      boxShadow: const [BoxShadow(color: Color(0x0F1A1A28), blurRadius: 10, offset: Offset(0, 3))],
                    ),
                    child: SizedBox(
                      height: 48,
                      child: CupertinoSearchTextField(
                        controller: _input,
                        autofocus: true,
                        placeholder: '作品名、作者',
                        style: TextStyle(fontSize: 17, color: IosColors.ink),
                        placeholderStyle: TextStyle(fontSize: 17, color: IosColors.muted),
                        backgroundColor: Colors.transparent,
                        itemColor: IosColors.muted,
                        borderRadius: BorderRadius.circular(24),
                        padding: const EdgeInsets.fromLTRB(6, 12, 12, 12),
                        prefixInsets: const EdgeInsetsDirectional.only(start: 14),
                        onSubmitted: _submit,
                        onSuffixTap: () {
                          _input.clear();
                          setState(() => _query = '');
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(height: 44, child: TextAction(label: '取消', color: IosColors.ink, onTap: () => Navigator.pop(context))),
              ]),
            ),
            if (_query.isNotEmpty)
              UnderlineTabs(
                options: const ['全部', '作品名', '作者', '轻小说'],
                selected: _scope,
                onChanged: (i) {
                  setState(() => _scope = i);
                  if (i == 3) _searchNovels();
                },
              ),
            Expanded(child: _query.isEmpty ? _history() : (_scope == 3 ? _novelResults() : _results())),
          ]),
        ),
      );

  Widget _history() => ListenableBuilder(
        listenable: _prefs,
        builder: (context, _) {
          final history = _prefs.searchHistory;
          if (history.isEmpty) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Text('输入作品名或作者名，繁体、简体都可以。', style: TextStyle(fontSize: 15, height: 1.6, color: IosColors.muted)),
            );
          }
          return ListView(children: [
            IosSection('最近搜索', action: '清除', actionIcon: 'close', onAction: _prefs.clearSearchHistory),
            for (final q in history)
              Pressable(
                onTap: () => _submit(q),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: Row(children: [
                    AppIcon('history', size: 18, color: IosColors.muted),
                    const SizedBox(width: 12),
                    Expanded(child: Text(q, style: TextStyle(fontSize: 17, color: IosColors.ink))),
                  ]),
                ),
              ),
          ]);
        },
      );

  Widget _results() => ListenableBuilder(
        listenable: _pager,
        builder: (context, _) {
          if (_pager.items.isEmpty && _pager.error != null) return ListView(children: [IosNetworkError(message: _pager.error!, onRetry: _pager.refresh)]);
          if (_pager.items.isEmpty && _pager.loading) return const Center(child: CupertinoActivityIndicator());
          final items = [for (final c in _pager.items) if (_match(c)) c];
          // 筛选后不足一屏、接口还有下一页时继续载入，否则滚动不到底、不会触发分页。
          if (_scope != 0 && items.length < 12 && _pager.hasMore && !_pager.loading && _pager.error == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _pager.loadMore());
          }
          if (items.isEmpty && !_pager.loading) {
            return Center(
              child: Unavailable(icon: 'search', title: '没有找到相关作品', message: _scope == 0 ? '换个关键词试试，比如作品的另一个译名。' : '可以切到「全部」看看。'),
            );
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (n) => onScrollEnd(n, _pager.loadMore),
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 40),
              itemCount: items.length + 2,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Row(children: [
                      Text(
                        _scope == 0 ? '${_pager.total} 条结果' : '已载入的 ${_pager.items.length} 条中有 ${items.length} 条',
                        style: TextStyle(fontSize: 13, color: IosColors.muted),
                      ),
                      const Spacer(),
                      Text('相关度排序', style: TextStyle(fontSize: 13, color: IosColors.muted)),
                    ]),
                  );
                }
                if (i == items.length + 1) {
                  if (_pager.loading) return const Padding(padding: EdgeInsets.all(20), child: CupertinoActivityIndicator());
                  return const SizedBox(height: 20);
                }
                return _ResultRow(comic: items[i - 1], query: _query);
              },
            ),
          );
        },
      );
}

extension on _IosSearchPageState {
  Widget _novelResults() {
    if (_novelLoading) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CupertinoActivityIndicator(),
          const SizedBox(height: 12),
          Text('正在搜索轻小说…', style: TextStyle(fontSize: 13, color: IosColors.muted)),
        ]),
      );
    }
    final mode = _novelByAuthor ? '作者' : '作品名';
    if (_novelError != null) {
      return Center(
        child: Unavailable(icon: 'search', title: '轻小说没有搜出来', message: _novelError!, actions: [TextAction(label: '重试', onTap: () => _searchNovels(force: true))]),
      );
    }
    final toggle = TextAction(
      label: _novelByAuthor ? '改按作品名搜' : '改按作者搜',
      onTap: _flipNovelMode,
    );
    if (_novels.isEmpty) {
      return Center(
        child: Unavailable(icon: 'book', title: '没有找到相关轻小说', message: '按$mode搜「$_query」没有结果。源站只收录轻小说，书名多为简体。', actions: [toggle]),
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 40),
      itemCount: _novels.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
            child: Row(children: [
              Text('${_novels.length} 本轻小说 · 按$mode · 来自 Wenku8', style: TextStyle(fontSize: 13, color: IosColors.muted)),
              const Spacer(),
              toggle,
            ]),
          );
        }
        return _NovelRow(book: _novels[i - 1], query: _query);
      },
    );
  }
}

/// 轻小说搜索结果：点行进阅读页，行尾可以直接加入 / 移出源站书架。
class _NovelRow extends StatelessWidget {
  const _NovelRow({required this.book, required this.query});

  final WenkuBook book;
  final String query;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: () => iosOpenWenkuNovel(context, aid: book.aid, name: book.name),
        child: Padding(
          padding: const EdgeInsets.only(left: 20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 10), child: CoverImage(url: book.cover, title: book.name, width: 64, height: coverHeightFor(64), radius: 5)),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 106),
                padding: const EdgeInsets.fromLTRB(0, 12, 16, 14),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: IosColors.line, width: .5))),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text.rich(_highlight(book.name, query), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w600, color: IosColors.ink)),
                      const SizedBox(height: 4),
                      Text([if (book.author.isNotEmpty) book.author, '轻小说', if (book.delisted) '源站已下架'].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: IosColors.muted)),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  WenkuShelfButton(aid: book.aid, name: book.name, author: book.author, compact: true),
                ]),
              ),
            ),
          ]),
        ),
      );
}

TextSpan _highlight(String text, String query) {
  if (query.isEmpty || !text.contains(query)) return TextSpan(text: text);
  final parts = text.split(query);
  return TextSpan(children: [
    for (var i = 0; i < parts.length; i++) ...[
      TextSpan(text: parts[i]),
      if (i < parts.length - 1) TextSpan(text: query, style: TextStyle(color: IosColors.accent)),
    ],
  ]);
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.comic, required this.query});

  final ComicBrief comic;
  final String query;

  @override
  Widget build(BuildContext context) {
    final alias = comic.distinctAlias;
    return Pressable(
      onTap: () => iosOpenDetail(context, comic),
      child: Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 10), child: CoverImage(url: comic.cover, title: comic.name, width: 64, height: coverHeightFor(64), radius: 5)),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 12, 16, 14),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: IosColors.line, width: .5))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(_highlight(comic.name), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w600, color: IosColors.ink)),
                    if (alias != null) ...[
                      const SizedBox(height: 3),
                      Text('又名 $alias', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: IosColors.muted)),
                    ],
                    const SizedBox(height: 4),
                    Text(comic.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: IosColors.muted)),
                    const SizedBox(height: 2),
                    Text('人气 ${formatPopular(comic.popular)}', style: TextStyle(fontSize: 13, color: IosColors.muted)),
                  ]),
                ),
                AppIcon('right', size: 14, color: IosColors.muted, stroke: 2),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  TextSpan _highlight(String text) {
    if (query.isEmpty || !text.contains(query)) return TextSpan(text: text);
    final parts = text.split(query);
    return TextSpan(children: [
      for (var i = 0; i < parts.length; i++) ...[
        TextSpan(text: parts[i]),
        if (i < parts.length - 1) TextSpan(text: query, style: TextStyle(color: IosColors.accent)),
      ],
    ]);
  }
}
