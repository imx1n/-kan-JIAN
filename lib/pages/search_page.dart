import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../ui/comic_tiles.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'navigation.dart';

/// 搜索：作品名和作者一起搜（接口的 q_type 分类结果是模糊匹配，不可靠，所以不分页签）。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
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

  void _clear() {
    _input.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(children: [
                ToolButton(icon: 'back', tooltip: '返回', size: 48, onTap: () => Navigator.pop(context)),
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(color: Palette.tonal, borderRadius: BorderRadius.circular(22)),
                    child: Row(children: [
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _input,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _submit,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 15),
                          decoration: const InputDecoration(
                            hintText: '作品名、作者',
                            hintStyle: TextStyle(color: Palette.ink3),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_input.text.isNotEmpty) ToolButton(icon: 'close', tooltip: '清空', size: 40, iconSize: 18, color: Palette.ink2, onTap: _clear),
                      const SizedBox(width: 4),
                    ]),
                  ),
                ),
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
              padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text('输入作品名或作者名开始搜索。繁体、简体都可以。', style: TextStyle(fontSize: 14, height: 1.7, color: Palette.ink2)),
            );
          }
          return ListView(padding: const EdgeInsets.only(top: 8), children: [
            SectionHeader(
              title: '最近搜索',
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
              trailing: TextButton(
                onPressed: _prefs.clearSearchHistory,
                style: TextButton.styleFrom(foregroundColor: Palette.ink2),
                child: const Text('清除', style: TextStyle(fontSize: 12)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in history)
                  ActionChip(
                    label: Text(q),
                    onPressed: () => _submit(q),
                    avatar: const AppIcon('history', size: 16, color: Palette.ink3),
                    backgroundColor: Palette.bg,
                    side: const BorderSide(color: Palette.line),
                    shape: const StadiumBorder(),
                    labelStyle: const TextStyle(fontSize: 13, color: Palette.ink),
                  ),
              ]),
            ),
          ]);
        },
      );

  Widget _results() => ListenableBuilder(
        listenable: _pager,
        builder: (context, _) => NotificationListener<ScrollNotification>(
          onNotification: (n) => onScrollEnd(n, _pager.loadMore),
          child: ListView.builder(
            itemCount: _pager.items.length + 2,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
                  child: Text(
                    _pager.total > 0 ? '共 ${_pager.total} 部 · 作品名和作者一起搜' : '“$_query”',
                    style: const TextStyle(fontSize: 12, color: Palette.ink3),
                  ),
                );
              }
              if (i == _pager.items.length + 1) return PagerFooter(pager: _pager, emptyText: '没有找到“$_query”相关的作品');
              final c = _pager.items[i - 1];
              return ResultRow(comic: c, query: _query, onTap: () => openDetail(context, c));
            },
          ),
        ),
      );
}
