import 'dart:convert';
import 'dart:math' show Random;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'models.dart';
import 'routes.dart';
import 'store.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 账号登录已失效（401）：每次登录都会作废旧的登录凭证，在别处登录过就会这样。
class AuthExpired extends ApiException {
  const AuthExpired() : super('登录已失效，请重新登录');
}

/// 书架与浏览历史里的一条：作品，以及源站记录的最后看过的那一话（书架条目可能没有）。
class RemoteComic {
  const RemoteComic({required this.comic, this.chapterId, this.chapterName});

  final ComicBrief comic;
  final String? chapterId;
  final String? chapterName;

  /// 列表项可能把作品放在 `comic` 里，也可能直接就是作品；最后看过的话在 `last_browse` 里或平铺在条目上。
  factory RemoteComic.fromJson(Map<String, dynamic> j) {
    final comic = j['comic'] is Map ? Map<String, dynamic>.from(j['comic'] as Map) : j;
    final browse = j['last_browse'] is Map ? Map<String, dynamic>.from(j['last_browse'] as Map) : j;
    String? str(Object? v) => v is String && v.isNotEmpty ? v : null;
    return RemoteComic(
      comic: ComicBrief.fromJson(comic),
      chapterId: str(browse['last_browse_id']) ?? str(browse['last_chapter_id']),
      chapterName: str(browse['last_browse_name']) ?? str(browse['last_chapter_name']),
    );
  }
}

/// 最近一次失败的请求：哪台主机、什么错误、什么时候。
class ApiDiagnosis {
  const ApiDiagnosis({required this.host, required this.message, required this.at});

  final String host;
  final String message;
  final DateTime at;
}

class MangaApi {
  MangaApi._();

  static final instance = MangaApi._();

  /// 最近一次请求的结果，供「我的」与网络异常页做诊断。
  final lastError = ValueNotifier<ApiDiagnosis?>(null);

  final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    headers: AppConfig.apiHeaders,
  ));

  /// 测试或离线截图时替换网络层，返回本地样例数据。
  @visibleForTesting
  set adapter(HttpClientAdapter a) => _dio.httpClientAdapter = a;

  /// 最近一次成功的主机，供界面显示。
  String get activeHost => RouteSelector.instance.activeHost;

  /// 选路：按 [RouteSelector.candidates] 的顺序尝试。网络失败换下一台（该台冷却
  /// 60 秒）；`results == null` 是请求头/版本被判不合格，换主机也没用，直接报错。
  Future<Map<String, dynamic>> _get(String path, [Map<String, Object?> query = const {}, String? token]) async {
    final params = {...query, 'platform': 3, 'region': 0};
    final options = token == null ? null : Options(headers: {'authorization': 'Token $token'});
    final selector = RouteSelector.instance;
    final hosts = selector.candidates();
    Object? lastFailure;
    var authRejected = false;
    var lastHost = hosts.isEmpty ? selector.activeBase : hosts.first;
    for (final host in hosts) {
      final sw = Stopwatch()..start();
      lastHost = host;
      try {
        final res = await _dio.get<Object>('$host$path', queryParameters: params, options: options);
        final body = res.data is String ? jsonDecode(res.data as String) : res.data;
        if (body is Map && body['results'] is Map) {
          selector.reportSuccess(host, sw.elapsedMilliseconds);
          if (lastError.value != null) lastError.value = null;
          return Map<String, dynamic>.from(body['results'] as Map);
        }
        // 请求头或版本被判不合格：换线路不会变好，不用白试剩下的主机。
        final failure = ApiException(
          body is Map ? '数据源拒绝请求（${body['code']}：${body['message']}）' : '数据源返回了无法识别的内容',
        );
        lastError.value = ApiDiagnosis(host: Uri.parse(host).host, message: failure.message, at: DateTime.now());
        throw failure;
      } on DioException catch (e) {
        // 带凭证的请求被判 401：凭证失效，不是这台主机的网络问题，不冷却它。
        if (token != null && e.response?.statusCode == 401) {
          authRejected = true;
          continue;
        }
        selector.reportFailure(host);
        lastFailure = e;
      } on FormatException {
        selector.reportFailure(host);
        lastFailure = const ApiException('数据源返回了无法识别的内容');
      }
    }
    if (authRejected) throw const AuthExpired();
    final failure = lastFailure is ApiException ? lastFailure : ApiException(_describe(lastFailure));
    lastError.value = ApiDiagnosis(host: Uri.parse(lastHost).host, message: failure.message, at: DateTime.now());
    throw failure;
  }

  /// 启动时按当前模式测一次速；「自动」下这是选出最快线路的唯一依据。
  Future<void> warmUp() async {
    final prefs = ReaderPrefs.instance;
    if (prefs.apiMode == 2 && RouteSelector.normalizeBase(prefs.apiCustom).isNotEmpty) return;
    await RouteSelector.instance.probe(_dio, all: prefs.apiMode == 0);
  }

  static String _describe(Object? e) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return '连接超时，请检查网络或代理设置';
        case DioExceptionType.badResponse:
          return '数据源响应异常（HTTP ${e.response?.statusCode}）';
        case DioExceptionType.connectionError:
          return '无法连接数据源，请检查网络或代理设置';
        default:
          return '网络请求失败：${e.message ?? e.type.name}';
      }
    }
    return '网络请求失败';
  }

  /// [ordering]：`-datetime_updated` 最新，`-popular` 热门。[theme] 为题材 path_word（见 [AppConfig.themes]）。
  Future<PageResult<ComicBrief>> comics({
    String ordering = '-datetime_updated',
    String? theme,
    int offset = 0,
    int limit = 21,
  }) async =>
      PageResult.parse(
        await _get('/api/v3/comics', {
          'ordering': ordering,
          'theme': ?theme,
          'limit': limit,
          'offset': offset,
        }),
        ComicBrief.fromJson,
      );

  /// [dateType]：day / week / month / total。
  Future<PageResult<RankItem>> ranks({
    String dateType = 'day',
    int offset = 0,
    int limit = 20,
  }) async =>
      PageResult.parse(
        await _get('/api/v3/ranks', {
          'type': 1,
          'date_type': dateType,
          'limit': limit,
          'offset': offset,
        }),
        RankItem.fromJson,
      );

  Future<PageResult<ComicBrief>> search(String q, {int offset = 0, int limit = 20}) async =>
      PageResult.parse(
        await _get('/api/v3/search/comic', {'q': q, 'q_type': '', 'limit': limit, 'offset': offset}),
        ComicBrief.fromJson,
      );

  Future<ComicDetail> detail(String pathWord) async =>
      ComicDetail.fromJson(await _get('/api/v3/comic2/$pathWord'));

  Future<PageResult<Chapter>> chapters(
    String pathWord,
    String group, {
    int offset = 0,
    int limit = 100,
  }) async =>
      PageResult.parse(
        await _get('/api/v3/comic/$pathWord/group/$group/chapters', {'limit': limit, 'offset': offset}),
        Chapter.fromJson,
      );

  Future<ChapterContent> chapter(String pathWord, String uuid) async =>
      ChapterContent.fromJson(await _get('/api/v3/comic/$pathWord/chapter/$uuid'));

  /// 网页端账号登录：密码按网页端协议编码为 base64(密码-6位随机数)，同时提交这个随机数。
  /// 成功返回 `{token, user_id, username, nickname, …}`。每次登录都会让旧凭证失效；
  /// 短时间多次登录会被源站风控（code 210），失败信息原样返回给用户。
  Future<Map<String, dynamic>> login(String username, String password) async {
    final salt = (100000 + Random.secure().nextInt(900000)).toString();
    try {
      final res = await _dio.post<Object>(
        '${AppConfig.webHost}/api/v1/login',
        data: {
          'username': username,
          'password': base64.encode(utf8.encode('$password-$salt')),
          'salt': salt,
          'platform': 1,
          'version': '3.1.0',
          'source': '',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'referer': '${AppConfig.webHost}/web/login', 'origin': AppConfig.webHost},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      final body = res.data is String ? jsonDecode(res.data as String) : res.data;
      if (body is Map && body['code'] == 200 && body['results'] is Map && (body['results'] as Map)['token'] is String) {
        return Map<String, dynamic>.from(body['results'] as Map);
      }
      final message = body is Map ? '${body['message'] ?? body['detail'] ?? ''}'.trim() : '';
      throw ApiException(message.isEmpty ? '登录失败（HTTP ${res.statusCode}）' : message);
    } on DioException catch (e) {
      throw ApiException(_describe(e));
    } on FormatException {
      throw const ApiException('登录接口返回了无法识别的内容');
    }
  }

  Future<Map<String, dynamic>> memberInfo(String token) => _get('/api/v3/member/info', const {}, token);

  /// 源站书架（漫画）。
  Future<PageResult<RemoteComic>> collectedComics(String token, {int offset = 0, int limit = 50}) async =>
      PageResult.parse(await _get('/api/v3/member/collect/comics', {'limit': limit, 'offset': offset}, token), RemoteComic.fromJson);

  /// 源站浏览历史（漫画），最近的在前。
  Future<PageResult<RemoteComic>> browsedComics(String token, {int offset = 0, int limit = 50}) async =>
      PageResult.parse(await _get('/api/v3/member/browse/comics', {'limit': limit, 'offset': offset}, token), RemoteComic.fromJson);

  /// 用最新列表接口测一次连通性，返回耗时。
  Future<Duration> ping() async {
    final sw = Stopwatch()..start();
    await comics(limit: 1);
    return sw.elapsed;
  }
}
