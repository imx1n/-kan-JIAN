import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastemangax/core/account.dart';
import 'package:pastemangax/core/api.dart';
import 'package:pastemangax/core/models.dart';
import 'package:pastemangax/core/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假网络层：记录请求，按路径返回预设响应。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final (int, Object) Function(RequestOptions o, String body) respond;
  final requests = <(RequestOptions, String)>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final raw = body == null ? '' : utf8.decode(await body.expand((b) => b).toList());
    requests.add((o, raw));
    final (status, json) = respond(o, raw);
    return ResponseBody.fromString(jsonEncode(json), status, headers: {
      Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _comic(String pw, String name) => {'path_word': pw, 'name': name, 'cover': '', 'author': [{'name': '作者'}], 'popular': 1};

Map<String, Object?> _page(List<Object?> list) => {'code': 200, 'message': 'ok', 'results': {'list': list, 'total': list.length, 'limit': 50, 'offset': 0}};

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initStores();
    await AccountService.instance.load();
  });

  test('源站条目两种结构都能解析：作品在 comic 里 / 平铺', () {
    final a = RemoteComic.fromJson({'comic': _comic('a', 'A'), 'last_browse': {'last_browse_id': 'u1', 'last_browse_name': '第1话'}});
    expect(a.comic.pathWord, 'a');
    expect(a.chapterId, 'u1');
    expect(a.chapterName, '第1话');
    final b = RemoteComic.fromJson({..._comic('b', 'B'), 'last_chapter_id': 'u2', 'last_chapter_name': '第2话'});
    expect(b.comic.name, 'B');
    expect(b.chapterId, 'u2');
    final c = RemoteComic.fromJson({'comic': _comic('c', 'C'), 'last_browse': null});
    expect(c.chapterId, isNull);
  });

  test('登录：网页端协议，密码编码为 base64(密码-随机数)，只保存凭证', () async {
    final fake = _FakeAdapter((o, body) {
      if (o.path.endsWith('/api/kb/web/login')) {
        return (200, {'code': 200, 'message': '请求成功', 'results': {'token': 't0k', 'username': 'reader', 'nickname': '读者'}});
      }
      return (200, _page(const []));
    });
    MangaApi.instance.adapter = fake;
    await AccountService.instance.login('reader', 'secret');

    final (o, body) = fake.requests.first;
    expect(o.uri.toString(), startsWith('https://copy4000.com/api/kb/web/login'));
    // 网页端登录不能带安卓 App 那套请求头。
    expect(o.headers['X-Requested-With'], isNull);
    expect(o.headers['platform'], '2');
    final form = Uri.splitQueryString(body);
    expect(form['salt'], matches(RegExp(r'^\d{6}$')));
    expect(utf8.decode(base64.decode(form['password']!)), 'secret-${form['salt']}');
    expect(form['platform'], '2');
    expect(form['source'], 'freeSite');

    final account = AccountService.instance;
    expect(account.loggedIn, isTrue);
    expect(account.displayName, '读者');
    // 后续会员接口带凭证。
    expect(fake.requests.skip(1).every((r) => r.$1.headers['authorization'] == 'Token t0k'), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => prefs.get(k).toString().contains('secret')), isEmpty);
  });

  test('登录失败（风控 210）：原样提示，不保存任何东西', () async {
    MangaApi.instance.adapter = _FakeAdapter((o, body) => (200, {'code': 210, 'message': '請等待 1 小時自動解除', 'results': null}));
    await expectLater(AccountService.instance.login('reader', 'secret'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('1 小時'))));
    expect(AccountService.instance.loggedIn, isFalse);
  });

  test('登录：主域名连不上时换备用域名', () async {
    final fake = _FakeAdapter((o, body) {
      if (o.uri.host == 'copy4000.com') throw Exception('connection refused');
      if (o.path.endsWith('/api/kb/web/login')) return (200, {'code': 200, 'results': {'token': 't2', 'username': 'u'}});
      return (200, _page(const []));
    });
    MangaApi.instance.adapter = fake;
    await AccountService.instance.login('u', 'p');
    expect(AccountService.instance.loggedIn, isTrue);
    expect(fake.requests.any((r) => r.$1.uri.host == 'copy3000.com'), isTrue);
  });

  test('多设备：源站是另一话时，已上报的本机位置跟过去，未上报的保留，同一话保留页码', () async {
    final store = LibraryStore.instance;
    ShelfEntry mk(String id) => ShelfEntry(id: id, kind: ShelfKind.manga, name: id, cover: '', author: '', followed: false);
    store.recordPosition(id: 'x', create: () => mk('x'), chapterUuid: 'x3', chapterName: '第3话', page: 4, pageCount: 20, progress: .2);
    store.markReported('x', 'x3');
    store.recordPosition(id: 'y', create: () => mk('y'), chapterUuid: 'y3', chapterName: '第3话', page: 4, pageCount: 20, progress: .2);
    store.recordPosition(id: 'z', create: () => mk('z'), chapterUuid: 'z5', chapterName: '第5话', page: 7, pageCount: 20, progress: .4);
    final r = store.mergeRemoteHistory([
      (comic: ComicBrief.fromJson(_comic('x', 'X')), chapterId: 'x5', chapterName: '第5话'),
      (comic: ComicBrief.fromJson(_comic('y', 'Y')), chapterId: 'y5', chapterName: '第5话'),
      (comic: ComicBrief.fromJson(_comic('z', 'Z')), chapterId: 'z5', chapterName: '第5话'),
    ]);
    expect(r.updated, 1);
    expect(r.filled, 0);
    expect(store.entry('x')!.chapterUuid, 'x5');
    expect(store.entry('x')!.page, 0);
    expect(store.entry('x')!.reportedChapter, 'x5');
    expect(store.entry('y')!.chapterUuid, 'y3');
    expect(store.entry('y')!.page, 4);
    expect(store.entry('z')!.page, 7);
    expect(store.entry('z')!.reportedChapter, 'z5');
  });

  test('升级迁移：升级前的阅读位置视为已和源站对齐', () async {
    SharedPreferences.setMockInitialValues({
      'shelf.v1': jsonEncode([
        {'id': 'o', 'kind': 'manga', 'name': 'O', 'chapterUuid': 'o2', 'chapterName': '第2话'},
      ]),
    });
    await initStores();
    expect(LibraryStore.instance.entry('o')!.reportedChapter, 'o2');
  });

  test('阅读上报：带凭证请求章节，成功后记为已上报，同一话只报一次', () async {
    final fake = _FakeAdapter((o, body) {
      if (o.path.endsWith('/api/kb/web/login')) return (200, {'code': 200, 'results': {'token': 't0k', 'username': 'u'}});
      if (o.path.contains('/chapter/')) return (200, {'code': 200, 'results': {'chapter': <String, Object?>{}}});
      return (200, _page(const []));
    });
    MangaApi.instance.adapter = fake;
    await AccountService.instance.login('u', 'p');
    final store = LibraryStore.instance;
    store.recordPosition(id: 'k', create: () => ShelfEntry(id: 'k', kind: ShelfKind.manga, name: 'K', cover: '', author: '', followed: false), chapterUuid: 'k1', chapterName: '第1话', progress: .1);
    await AccountService.instance.reportRead('k', 'k1');
    await AccountService.instance.reportRead('k', 'k1');
    final reports = fake.requests.where((r) => r.$1.path.contains('/comic/k/chapter/k1')).toList();
    expect(reports, hasLength(1));
    expect(reports.first.$1.headers['authorization'], 'Token t0k');
    expect(store.entry('k')!.reportedChapter, 'k1');
  });

  test('详情页：浏览历史第一页里有这部作品，接上另一台设备的进度', () async {
    var history = <Object?>[];
    MangaApi.instance.adapter = _FakeAdapter((o, body) {
      if (o.path.endsWith('/api/kb/web/login')) return (200, {'code': 200, 'results': {'token': 't', 'username': 'u'}});
      if (o.path.contains('/member/browse/comics')) return (200, _page(history));
      return (200, _page(const []));
    });
    await AccountService.instance.login('u', 'p');
    final store = LibraryStore.instance;
    store.recordPosition(id: 'd', create: () => ShelfEntry(id: 'd', kind: ShelfKind.manga, name: 'D', cover: '', author: '', followed: false), chapterUuid: 'd2', chapterName: '第2话', page: 3, pageCount: 10, progress: .4);
    store.markReported('d', 'd2');
    // 拷贝实测的结构：最后看的那一话平铺在条目上（comic 里的 last_chapter_id 是作品最新一话）。
    history = [
      {'comic': {..._comic('d', 'D'), 'last_chapter_id': 'latest', 'last_chapter_name': '第99话'}, 'last_chapter_id': 'd9', 'last_chapter_name': '第9话'},
    ];
    expect(await AccountService.instance.refreshComic('d'), isTrue);
    expect(store.entry('d')!.chapterUuid, 'd9');
    expect(store.entry('d')!.chapterName, '第9话');
  });

  test('同步：书架加入追更，历史只补本机没有的阅读位置', () async {
    final store = LibraryStore.instance;
    // 本机已经读过 b（有页码），不应被源站历史覆盖。
    store.recordPosition(
      id: 'b',
      create: () => ShelfEntry(id: 'b', kind: ShelfKind.manga, name: 'B', cover: '', author: '', followed: false),
      chapterUuid: 'local',
      chapterName: '第9话',
      page: 5,
      pageCount: 20,
      progress: .3,
    );
    MangaApi.instance.adapter = _FakeAdapter((o, body) {
      if (o.path.endsWith('/api/kb/web/login')) return (200, {'code': 200, 'results': {'token': 't', 'username': 'u'}});
      if (o.path.contains('/member/collect/comics')) {
        return (200, _page([{'comic': _comic('a', 'A')}, {'comic': _comic('b', 'B')}]));
      }
      if (o.path.contains('/member/browse/comics')) {
        return (200, _page([
          {'comic': _comic('a', 'A'), 'last_browse': {'last_browse_id': 'ra', 'last_browse_name': '第3话'}},
          {'comic': _comic('b', 'B'), 'last_browse': {'last_browse_id': 'rb', 'last_browse_name': '第1话'}},
          {'comic': _comic('c', 'C'), 'last_browse': {'last_browse_id': 'rc', 'last_browse_name': '第7话'}},
        ]));
      }
      return (404, {});
    });
    await AccountService.instance.login('u', 'p');

    final r = AccountService.instance.lastReport!;
    expect(r.shelfTotal, 2);
    expect(r.shelfAdded, 2);
    expect(r.historyFilled, 2);
    expect(store.isFollowed('a'), isTrue);
    expect(store.isFollowed('b'), isTrue);
    expect(store.entry('a')!.chapterName, '第3话');
    expect(store.entry('b')!.chapterUuid, 'local');
    expect(store.entry('b')!.page, 5);
    // 只在源站历史里的作品：记位置，不追更。
    expect(store.isFollowed('c'), isFalse);
    expect(store.entry('c')!.chapterName, '第7话');
  });

  test('凭证失效（401）：清掉凭证，书架不动', () async {
    MangaApi.instance.adapter = _FakeAdapter((o, body) {
      if (o.path.endsWith('/api/kb/web/login')) return (200, {'code': 200, 'results': {'token': 'old', 'username': 'u'}});
      if (o.path.contains('/member/collect/comics') && LibraryStore.instance.entries.isEmpty) return (200, _page([{'comic': _comic('a', 'A')}]));
      return (401, {'detail': 'Invalid token.'});
    });
    await AccountService.instance.login('u', 'p');
    expect(AccountService.instance.loggedIn, isFalse);
    expect(AccountService.instance.error, '登录已失效，请重新登录');
  });
}
