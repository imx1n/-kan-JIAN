import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pastemangax/core/wenku.dart';
import 'package:pastemangax/core/wenku_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 站点结构照真实页面写；正文和书名都是自己编的，不用源站内容。
const _catalogHtml = '''
<table class="css" border="0" cellpadding="3" cellspacing="1">
<tr>
  <td class="vcss" colspan="4" vid="163301">第一卷 教程样本</td>
</tr>
<tr>
  <td class="ccss"><a href="163302.htm">序章 开端</a></td>
  <td class="ccss"><a href="163303.htm">第一章 第一节</a></td>
</tr>
<tr>
  <td class="vcss" colspan="4" vid="165776">第二卷 续编</td>
</tr>
<tr>
  <td class="ccss"><a href="170001.htm">第二章 第二节</a></td>
</tr>
</table>
''';

const _contentHtml = '''
<html><body>
<h1>序章　开端</h1>
<div id="content">
本文来自 轻小说文库(http://www.wenku8.com)<br />
<br />
　　第一段正文，用来验证段落切分。<br />
<br />
　　第二段正文。<br />
<img src="https://pic.wenku8.cn/pictures/1/2/3.jpg" /><br />
　　第三段正文。<br />
<img src="https://evil.example.com/track.gif" />
</div>
<a href="160000.htm">上一章</a>
<a href="163303.htm">下一章</a>
</body></html>
''';

const _searchHtml = '''
<table>
<tr><td class="odd"><a href="/book/471.htm">样本长篇（上）</a></td></tr>
<tr><td class="odd"><a href="/book/1990.htm">样本外传</a></td></tr>
<tr><td class="odd"><a href="/book/471.htm">重复条目</a></td></tr>
</table>
''';

const _shelfHtml = '''
<table class="css">
<tr><td>标题</td><td>作者</td></tr>
<tr>
  <td><input type="checkbox" name="checkid[]" value="13346167"></td>
  <td><a href="/book/3933.htm">样本小说</a></td>
  <td>样本作者</td>
  <td>插图</td>
  <td></td>
  <td>26-11-02</td>
  <td><a href="javascript:bookcase.php?classid=0&delid=13346167">移除</a></td>
</tr>
<tr>
  <td><input type="checkbox" name="checkid[]" value="13346168"></td>
  <td><a href="/book/4455.htm">样本小说二</a></td>
  <td>另一个作者</td>
  <td>第三章</td>
  <td>第二章</td>
  <td>26-10-30</td>
  <td><a href="javascript:bookcase.php?classid=0&delid=13346168">移除</a></td>
</tr>
</table>
<a href="/logout.php">退出</a>
''';

List<int> _utf8Bytes(String s) => utf8.encode(s);
List<int> _gbkBytes(String s) => gbk.encode(s);

/// 假网络层：按路径返回预设页面，响应体用 GBK 编码（和真实站点一致）。
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions o) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add(o);
    return respond(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _html(String text, {int status = 200, Map<String, List<String>>? headers, bool gbkEncoded = true}) =>
    ResponseBody.fromBytes(
      gbkEncoded ? _gbkBytes(text) : _utf8Bytes(text),
      status,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=gbk'],
        ...?headers,
      },
    );

/// 登录成功后源站会种下的两个 Cookie。
const _loginCookies = {
  'set-cookie': [
    'PHPSESSID=0000sample0000; path=/',
    'jieqiUserInfo=jieqiUserId%3D1; expires=Thu, 01-Jan-2037 00:00:00 GMT; path=/',
  ],
};

void main() {
  group('编码', () {
    test('GBK 字节能解回中文', () {
      expect(decodeGbk(_gbkBytes('刀剑神域')), '刀剑神域');
    });

    test('UTF-8 字节也能认出来（部分页面会回 UTF-8）', () {
      expect(decodeGbk(_utf8Bytes('刀剑神域')), '刀剑神域');
    });

    test('搜索关键词按 GBK 编码后再 URL 编码', () {
      // 「刀」的 GBK 是 B5 B6。
      expect(encodeGbkQuery('刀'), '%B5%B6');
    });
  });

  group('目录解析', () {
    final c = parseCatalog(_catalogHtml, aid: 3933, cls: 3);

    test('卷和章都取到', () {
      expect(c.volumes.length, 2);
      expect(c.volumes.first.name, '第一卷 教程样本');
      expect(c.chapters.length, 3);
      expect(c.chapters.first.cid, 163302);
      expect(c.chapters.first.name, '序章 开端');
    });

    test('章归到最近的卷，序号连续', () {
      expect(c.chapters.map((e) => e.volume).toList(), [0, 0, 1]);
      expect(c.chapters.map((e) => e.index).toList(), [0, 1, 2]);
      expect(c.volumes[1].chapters.single.cid, 170001);
    });
  });

  group('正文解析', () {
    final content = parseContent(_contentHtml);

    test('去掉水印和空行，保留段落', () {
      expect(content.paragraphs.first, '第一段正文，用来验证段落切分。');
      expect(content.paragraphs.length, 4); // 三段正文 + 插图占位
      expect(content.paragraphs.join(), isNot(contains('本文来自')));
      expect(content.paragraphs.join(), isNot(contains('&nbsp;')));
    });

    test('只保留站点图床的插图', () {
      expect(content.images, ['https://pic.wenku8.cn/pictures/1/2/3.jpg']);
    });

    test('上一章 / 下一章', () {
      expect(content.previous, 160000);
      expect(content.next, 163303);
    });

    test('插图章节：每张图包在 divimage 里，全部取到，水印去掉', () {
      final c = parseContent('<div id="content" style="font-size: 16px;"> <ul id="contentdp">本文来自 轻小说文库</ul> '
          '<div class="divimage"><a href="https://pic.777743.xyz/1/1/1/1.jpg"><img src="https://pic.777743.xyz/1/1/1/1.jpg" border="0" class="imagecontent"></a></div>'
          '<div class="divimage"><a href="https://pic.777743.xyz/1/1/1/2.jpg"><img src="https://pic.777743.xyz/1/1/1/2.jpg" border="0" class="imagecontent"></a></div>'
          '</div><img src="https://ads.example.com/a.gif">');
      expect(c.images, ['https://pic.777743.xyz/1/1/1/1.jpg', 'https://pic.777743.xyz/1/1/1/2.jpg']);
      expect(c.paragraphs, ['[插图]', '[插图]']);
    });

    test('没有正文时报错，而不是返回空', () {
      expect(() => parseContent('<html><body>Just a moment</body></html>'), throwsA(isA<Exception>()));
    });
  });

  group('搜索与书架解析', () {
    test('搜索结果去重，封面按 aid 拼', () {
      final r = parseSearch(_searchHtml);
      expect(r.map((e) => e.aid).toList(), [471, 1990]);
      expect(r.first.name, '样本长篇（上）');
      expect(r.first.cover, 'https://img.wenku8.com/image/0/471/471s.jpg');
      expect(WenkuBook.coverOf(3933), 'https://img.wenku8.com/image/3/3933/3933s.jpg');
    });

    test('书架行按列位解析，空书签不导致错行', () {
      final items = parseShelf(_shelfHtml);
      expect(items.length, 2);
      expect(items.first.entryId, 13346167);
      expect(items.first.aid, 3933);
      expect(items.first.name, '样本小说');
      expect(items.first.author, '样本作者');
      expect(items.first.latest, '插图');
      expect(items.first.bookmark, '');
      expect(items.first.updated, '26-11-02');
      expect(items.last.bookmark, '第二章');
    });

    test('书目页取目录入口的 class', () {
      expect(parseClass('<a href="/novel/3/3933/index.htm">小说目录</a>', 3933), 3);
      expect(() => parseClass('<html></html>', 1), throwsA(isA<Exception>()));
    });
  });

  group('网络层', () {
    late WenkuService api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      api = WenkuService.instance;
      await api.load();
      await api.logout();
    });

    test('搜索把关键词按 GBK 提交', () async {
      api.adapter = _FakeAdapter((o) => _html(_searchHtml));
      final r = await api.search('刀');
      expect(r.length, 2);
      expect(api.lastRequestUri!.path, '/modules/article/search.php');
      expect(api.lastRequestUri!.query, contains('searchtype=articlename'));
      expect(api.lastRequestUri!.query, contains('%B5%B6'));
    });

    test('Cloudflare 验证页转成「需要网页验证」', () async {
      api.adapter = _FakeAdapter((o) => _html('<html><title>Just a moment...</title></html>', status: 403, headers: {'cf-mitigated': ['challenge']}));
      expect(() => api.search('刀'), throwsA(isA<WenkuBlocked>()));
    });

    test('未登录读正文直接报需要登录，不发请求', () async {
      final fake = _FakeAdapter((o) => _html(''));
      api.adapter = fake;
      await expectLater(api.content(aid: 1, cls: 0, cid: 2), throwsA(isA<WenkuNeedLogin>()));
      expect(fake.requests, isEmpty);
    });

    test('用账号密码登录成功后保存 Cookie', () async {
      api.adapter = _FakeAdapter((o) {
        if (o.uri.path.contains('bookcase')) return _html(_shelfHtml);
        // 登录提交后的页面带「退出」链接才算成功。
        return _html('<html><a href="/logout.php">退出</a></html>', headers: _loginCookies);
      });
      await api.login('someone', 'secret');
      expect(api.loggedIn, isTrue);
      expect(api.username, 'someone');
    });

    test('登录失败时把源站提示原样带出来', () async {
      api.adapter = _FakeAdapter((o) => _html('<html><div id="errormessage">密码不正确</div><form></form></html>'));
      expect(() => api.login('someone', 'bad'), throwsA(predicate((e) => e is Exception && '$e'.contains('密码不正确'))));
      expect(api.loggedIn, isFalse);
    });

    test('加入书架带上 bid', () async {
      api.adapter = _FakeAdapter((o) {
        if (o.uri.path.contains('bookcase') && !o.uri.path.contains('add')) return _html(_shelfHtml);
        return _html('<html><a href="/logout.php">退出</a></html>', headers: _loginCookies);
      });
      await api.login('someone', 'secret');
      await api.addToShelf(3933);
      expect(api.lastRequestUri!.path, '/modules/article/addbookcase.php');
      expect(api.lastRequestUri!.queryParameters['bid'], '3933');
    });

    test('移出书架用书架条目 id，不是 aid', () async {
      api.adapter = _FakeAdapter((o) {
        if (o.uri.path.contains('bookcase') && o.uri.queryParameters.containsKey('delid')) return _html(_shelfHtml);
        if (o.uri.path.contains('bookcase')) return _html(_shelfHtml);
        return _html('<html><a href="/logout.php">退出</a></html>', headers: _loginCookies);
      });
      await api.login('someone', 'secret');
      await api.removeFromShelf(13346167);
      expect(api.lastRequestUri!.queryParameters['delid'], '13346167');
    });
  });
}
