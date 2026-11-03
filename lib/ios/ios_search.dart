import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/icons.dart';
import '../ui/theme.dart' show formatPopular;
import '../ui/widgets.dart' show CoverImage, Pager, onScrollEnd;
import 'ios_app.dart';
import 'ios_discover.dart' show IosNetworkError;
import 'ios_theme.dart';

/// 搜索：作品名和作者一起搜。接口按类型筛选的结果是模糊匹配、并不可靠，所以不提供「作品名 / 作者」切换。
class IosSearchPage extends StatefulWidget {
  const IosSearchPage({super.key});

  @override
  State<IosSearchPage> createState() => _IosSearchPageState();
}

class _IosSearchPageState extends State<IosSearchPage> {
  final _input = TextEditingController();
  final _prefs = ReaderPrefs.instance;
  String _query = '';
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
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
              child: Row(children: [
                Expanded(
                  child: CupertinoSearchTextField(
                    controller: _input,
                    autofocus: true,
                    placeholder: '作品名、作者',
                    style: const TextStyle(fontSize: 17, color: IosColors.ink),
                    backgroundColor: IosColors.faint,
                    borderRadius: BorderRadius.circular(12),
                    onSubmitted: _submit,
                    onSuffixTap: () {
                      _input.clear();
                      setState(() => _query = '');
                    },
                  ),
                ),
                TextAction(label: '取消', onTap: () => Navigator.pop(context)),
              ]),
            ),
            Expanded(child: _query.isEmpty ? _history() : _results()),
          ]),
        ),
      );

  Widget _history() => ListenableBuilder(
        listenable: _prefs,
        builder: (context, _) {
          final history = _prefs.searchHistory;
          if (history.isEmpty) {
            return const Padding(
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
                    const AppIcon('history', size: 18, color: IosColors.muted),
                    const SizedBox(width: 12),
                    Expanded(child: Text(q, style: const TextStyle(fontSize: 17, color: IosColors.ink))),
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
          if (_pager.items.isEmpty) {
            return Center(
              child: Unavailable(icon: 'search', title: '没有找到相关作品', message: '换个关键词试试，比如作品的另一个译名。'),
            );
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (n) => onScrollEnd(n, _pager.loadMore),
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 40),
              itemCount: _pager.items.length + 2,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                    child: Text('${_pager.total} 条结果', style: const TextStyle(fontSize: 13, color: IosColors.muted)),
                  );
                }
                if (i == _pager.items.length + 1) {
                  if (_pager.loading) return const Padding(padding: EdgeInsets.all(20), child: CupertinoActivityIndicator());
                  return const SizedBox(height: 20);
                }
                return _ResultRow(comic: _pager.items[i - 1], query: _query);
              },
            ),
          );
        },
      );
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
          Padding(padding: const EdgeInsets.only(top: 10), child: CoverImage(url: comic.cover, title: comic.name, width: 64, height: 86, radius: 5)),
          const SizedBox(width: 14),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(0, 12, 16, 14),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: IosColors.line, width: .5))),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text.rich(_highlight(comic.name), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, height: 1.35, fontWeight: FontWeight.w600, color: IosColors.ink)),
                    if (alias != null) ...[
                      const SizedBox(height: 3),
                      Text('又名 $alias', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: IosColors.muted)),
                    ],
                    const SizedBox(height: 4),
                    Text(comic.authorText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: IosColors.muted)),
                    const SizedBox(height: 2),
                    Text('人气 ${formatPopular(comic.popular)}', style: const TextStyle(fontSize: 13, color: IosColors.muted)),
                  ]),
                ),
                const AppIcon('right', size: 14, color: IosColors.muted, stroke: 2),
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
        if (i < parts.length - 1) TextSpan(text: query, style: const TextStyle(color: IosColors.accent)),
      ],
    ]);
  }
}
