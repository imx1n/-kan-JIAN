import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart' show ApiException;
import 'wenku_models.dart';

/// 绕过 Cloudflare 验证失败：站点要求人在浏览器里过验证，凭 Cookie 过不去。
class WenkuBlocked extends ApiException {
  const WenkuBlocked() : super('源站要求浏览器验证，请在网页里登录一次');
}

/// 隐藏 WebView 加载页面失败（断网、DNS 等）。
class WenkuWebError extends ApiException {
  const WenkuWebError(String message) : super('网页加载失败：$message');
}

/// 用浏览器内核取页面的通道，由 `wenku_web.dart` 实现、`main` 注册。
/// 测试里不注册，Cloudflare 拦截时直接报 [WenkuBlocked]。
abstract class WenkuWeb {
  Future<String> get(Uri url, {String? referer});
  Future<String> post(Uri url, String formBody, {String? referer});
  Future<Map<String, String>> cookies();
}

/// 没有登录，或者登录已经失效。
class WenkuNeedLogin extends ApiException {
  const WenkuNeedLogin() : super('请先登录轻小说账号');
}

/// Wenku8 客户端：官方站直连，GBK 编码，靠登录 Cookie 过鉴权。
///
/// - 只保存 Cookie 和账号名，**不保存密码**。
/// - 站点前面有 Cloudflare：能过就直接发请求；过不去时由界面改用网页登录，
///   这里只负责接收网页登录拿到的 Cookie。
/// - 不做任何自动验证破解。
class WenkuService extends ChangeNotifier {
  WenkuService._();

  static final instance = WenkuService._();

  /// Dart 的 HTTP 客户端被 Cloudflare 拦下后改走这里（系统 WebView 正常加载页面）。
  static WenkuWeb? web;

  /// 本次运行里 dio 已经被拦过，后面的请求直接走 WebView，省一次必然失败的往返。
  bool _viaWeb = false;

  static const base = 'https://www.wenku8.net';
  static const _kCookies = 'wenku.cookies';
  static const _kUser = 'wenku.user';

  /// 和网页登录保持一致的浏览器标识；换 UA 会让 Cloudflare 的放行失效。
  static const userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  late SharedPreferences _prefs;

  final _cookies = <String, String>{};
  String _user = '';
  bool busy = false;

  bool get loggedIn => _loaded && _cookies.containsKey('jieqiUserInfo') && _cookies.containsKey('PHPSESSID');
  String get username => _user;

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    followRedirects: true,
    // 403 也要拿到响应体，用来判断是不是 Cloudflare 的验证页。
    validateStatus: (_) => true,
    responseType: ResponseType.bytes,
  ));

  /// 测试时替换网络层。
  @visibleForTesting
  set adapter(HttpClientAdapter a) => _dio.httpClientAdapter = a;

  /// 最近一次请求的地址，测试和「连接详情」用。
  Uri? lastRequestUri;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    _cookies.clear();
    final raw = _prefs.getString(_kCookies);
    if (raw != null && raw.isNotEmpty) {
      (jsonDecode(raw) as Map).forEach((k, v) => _cookies['$k'] = '$v');
    }
    _user = _prefs.getString(_kUser) ?? '';
    _loaded = true;
  }

  /// 是否已经读过本地存储。没读过时 [loggedIn] 一律为 false，写入也跳过，
  /// 避免在 `main` 里忘记初始化时把状态写成「已登录」却读不回来。
  bool _loaded = false;

  Future<void> _save() async {
    if (!_loaded) {
      notifyListeners();
      return;
    }
    await _prefs.setString(_kCookies, jsonEncode(_cookies));
    await _prefs.setString(_kUser, _user);
    notifyListeners();
  }

  /* ─────────── 请求 ─────────── */

  /// [rawQuery] 用于已经自己做过百分号编码的参数（例如 GBK 关键词），
  /// 不能再交给 `queryParameters`，否则会被按 UTF-8 再编码一遍。
  Future<String> _get(String path, {String? referer, Map<String, String>? query, String? rawQuery}) async {
    final baseUri = Uri.parse('$base$path');
    final uri = rawQuery != null ? Uri.parse('$base$path?$rawQuery') : baseUri.replace(queryParameters: query);
    lastRequestUri = uri;
    final w = web;
    if (_viaWeb && w != null) return w.get(uri, referer: referer);
    try {
      final res = await _dio.getUri<List<int>>(
        uri,
        options: Options(headers: {
          'User-Agent': userAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Referer': ?referer,
          if (_cookies.isNotEmpty) 'Cookie': _cookieHeader,
        }),
      );
      _absorbCookies(res);
      return _body(res);
    } on WenkuBlocked {
      if (w == null) rethrow;
      _viaWeb = true;
      return w.get(uri, referer: referer);
    } on DioException catch (e) {
      throw ApiException(_describe(e));
    }
  }

  Future<String> _post(String path, Map<String, String> data, {String? referer}) async {
    final uri = Uri.parse('$base$path');
    lastRequestUri = uri;
    final res = await _dio.postUri<List<int>>(
      uri,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'User-Agent': userAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Referer': ?referer,
          if (_cookies.isNotEmpty) 'Cookie': _cookieHeader,
        },
      ),
    );
    _absorbCookies(res);
    return _body(res);
  }

  String get _cookieHeader => _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// 收集响应里种下的 Cookie，覆盖同名旧值。
  void _absorbCookies(Response<List<int>> res) {
    final raw = res.headers.map['set-cookie'];
    if (raw == null) return;
    for (final line in raw) {
      final pair = line.split(';').first;
      final i = pair.indexOf('=');
      if (i <= 0) continue;
      final k = pair.substring(0, i).trim();
      final v = pair.substring(i + 1).trim();
      if (k.isEmpty || v.isEmpty) continue;
      _cookies[k] = v;
    }
  }

  /// GBK 解码，并把 Cloudflare 的验证页转成 [WenkuBlocked]。
  String _body(Response<List<int>> res) {
    final bytes = res.data ?? const <int>[];
    final text = decodeGbk(bytes);
    final status = res.statusCode ?? 0;
    final mitigated = res.headers.value('cf-mitigated') ?? '';
    if (mitigated.contains('challenge') || (status == 403 && text.contains('Just a moment'))) {
      throw const WenkuBlocked();
    }
    if (status == 403 || status >= 500) {
      throw ApiException('源站返回 HTTP $status');
    }
    return text;
  }

  /* ─────────── 登录 ─────────── */

  /// 直接用账号密码登录。Cloudflare 放行时可用；被拦截时抛 [WenkuBlocked]，
  /// 界面应改用网页登录再调 [importCookies]。
  Future<void> login(String user, String password) async {
    if (busy) return;
    busy = true;
    notifyListeners();
    final form = {
      'username': user,
      'password': password,
      'usecookie': '315360000',
      'action': 'login',
      'submit': '登录',
    };
    try {
      String html;
      try {
        await _get('/login.php');
        html = _viaWeb ? await _webLogin(form) : await _post('/login.php?do=submit', form, referer: '$base/login.php');
      } on WenkuBlocked {
        if (web == null) rethrow;
        _viaWeb = true;
        html = await _webLogin(form);
      }
      if (_viaWeb) {
        // WebView 里登录成功会种下 jieqiUserInfo；读回来只是为了记住「已登录」。
        final got = await web!.cookies();
        if (!got.containsKey('jieqiUserInfo')) throw ApiException(_loginError(html));
        for (final e in got.entries) {
          if (e.key == 'PHPSESSID' || e.key.startsWith('jieqi')) _cookies[e.key] = e.value;
        }
      } else if (!looksLoggedIn(html)) {
        // 登录失败时页面会原样带着表单和提示；成功则跳转，链接里出现「退出」。
        throw ApiException(_loginError(html));
      }
      _user = user;
      await _save();
    } on DioException catch (e) {
      throw ApiException(_describe(e));
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// 用 WebView 提交登录表单。表单值按 GBK 编码（站点是 GBK）。
  Future<String> _webLogin(Map<String, String> form) => web!.post(
        Uri.parse('$base/login.php?do=submit'),
        form.entries.map((e) => '${e.key}=${encodeGbkQuery(e.value)}').join('&'),
        referer: '$base/login.php',
      );

  /// 从登录失败页里取源站的提示（jieqi 的错误页把原因放在「错误原因」之后）。
  static String _loginError(String html) {
    final m = RegExp(r'id="errormessage"[^>]*>(.*?)</', dotAll: true).firstMatch(html) ??
        RegExp(r'错误原因[：:]\s*(?:<[^>]*>)*([^<]{2,60})', dotAll: true).firstMatch(html);
    final text = m == null ? '' : _strip(m.group(1)!);
    return text.isEmpty ? '账号或密码不正确' : text;
  }

  /// 接收网页登录拿到的 Cookie（只认本站的键）。
  Future<bool> importCookies(Map<String, String> cookies) async {
    var got = false;
    for (final e in cookies.entries) {
      if (e.key == 'PHPSESSID' || e.key.startsWith('jieqi')) {
        _cookies[e.key] = e.value;
        got = true;
      }
    }
    if (!got) throw const ApiException('网页里没有拿到登录凭证，请确认已经登录成功');
    // 验证一次：拿不到书架就说明 Cookie 不算数。
    final html = await _get('/modules/article/bookcase.php');
    if (!looksLoggedIn(html)) {
      _cookies.clear();
      await _save();
      throw const ApiException('这份网页登录没有生效，请重新登录');
    }
    await _save();
    return true;
  }

  /// 截图和测试用：直接注入一份 Cookie，不发请求。
  @visibleForTesting
  void importCookiesForTest(Map<String, String> cookies) {
    _cookies
      ..clear()
      ..addAll(cookies);
    _user = 'sample';
  }

  /// 退出：只清本地 Cookie。
  Future<void> logout() async {
    _cookies.clear();
    _user = '';
    await _save();
  }

  /// 检查登录是否还有效（会发一次请求）。
  Future<bool> verify() async {
    if (!loggedIn) return false;
    try {
      return looksLoggedIn(await _get('/modules/article/bookcase.php'));
    } on ApiException {
      rethrow;
    }
  }

  /* ─────────── 内容 ─────────── */

  /// 搜索。[byAuthor] 为 true 时按作者名搜。
  Future<List<WenkuBook>> search(String keyword, {bool byAuthor = false}) async {
    final q = keyword.trim();
    if (q.isEmpty) return const [];
    // 关键词必须 GBK + URL 编码，而且要作为原始查询串发出去，避免被再编码一次。
    final html = await _get(
      '/modules/article/search.php',
      rawQuery: 'searchtype=${byAuthor ? 'author' : 'articlename'}&searchkey=${encodeGbkQuery(q)}',
    );
    // 源站限制两次搜索的间隔，太快会回错误页。
    final err = parseSiteError(html);
    if (err != null) throw ApiException(err);
    return parseSearch(html);
  }

  /// 书目页 + 目录页，一次拿到 class 和全部章节。
  Future<({WenkuBook book, WenkuCatalog catalog})> catalog(int aid) async {
    final book = await _get('/book/$aid.htm');
    final cls = parseClass(book, aid);
    final index = await _get('/novel/$cls/$aid/index.htm');
    final title = RegExp(r'<title>(.*?)</title>', dotAll: true).firstMatch(book);
    final author = RegExp(r'作\s*者[：:\s]*(?:<[^>]*>)*([^<\r\n]{1,40})').firstMatch(book);
    return (
      book: WenkuBook(
        aid: aid,
        name: _strip(title?.group(1) ?? '').replaceAll(RegExp(r'[\-_|].*$'), '').trim(),
        author: _strip(author?.group(1) ?? ''),
        cover: WenkuBook.coverOf(aid),
      ),
      catalog: parseCatalog(index, aid: aid, cls: cls),
    );
  }

  /// 正文。需要登录，未登录时源站直接 403。
  Future<WenkuContent> content({required int aid, required int cls, required int cid}) async {
    if (!loggedIn) throw const WenkuNeedLogin();
    final html = await _get(
      '/novel/$cls/$aid/$cid.htm',
      referer: '$base/novel/$cls/$aid/index.htm',
    );
    return parseContent(html);
  }

  /* ─────────── 书架 ─────────── */

  Future<List<WenkuShelfItem>> shelf() async {
    if (!loggedIn) throw const WenkuNeedLogin();
    final html = await _get('/modules/article/bookcase.php');
    if (!looksLoggedIn(html)) throw const WenkuNeedLogin();
    return parseShelf(html);
  }

  /// 加入源站书架，并回读书架确认。返回书架里的那一行（移出时要用它的条目 id）。
  Future<WenkuShelfItem> addBook(int aid) async {
    if (!loggedIn) throw const WenkuNeedLogin();
    final html = await _get('/modules/article/addbookcase.php', query: {'bid': '$aid'}, referer: '$base/book/$aid.htm');
    final err = parseSiteError(html);
    // 「已经在书架里」也算成功，以回读结果为准。
    final item = (await shelf()).where((i) => i.aid == aid).firstOrNull;
    if (item != null) return item;
    throw ApiException(err ?? '源站没有加进书架，请稍后再试');
  }

  /// 移出源站书架：先在书架里找到这本书的条目 id，删完再回读确认。本来就不在书架上也算成功。
  Future<void> removeBook(int aid) async {
    if (!loggedIn) throw const WenkuNeedLogin();
    final item = (await shelf()).where((i) => i.aid == aid).firstOrNull;
    if (item == null) return;
    await _get('/modules/article/bookcase.php', query: {'delid': '${item.entryId}'}, referer: '$base/modules/article/bookcase.php');
    if ((await shelf()).any((i) => i.aid == aid)) throw const ApiException('源站没有移出书架，请稍后再试');
  }

  static String _strip(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&nbsp;', ' ').trim();

  static String _describe(Object? e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return '连接超时，请检查网络或代理设置';
        case DioExceptionType.connectionError:
          return '无法连接轻小说源站，请检查网络或代理设置';
        case DioExceptionType.badResponse:
          return '源站响应异常（HTTP ${e.response?.statusCode}）';
        default:
          return '网络请求失败：${e.message ?? e.type.name}';
      }
    }
    return '网络请求失败';
  }
}
