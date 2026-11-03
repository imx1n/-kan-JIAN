import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'config.dart';
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
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

  /// 最近一次成功的主机，下次优先使用。
  int _hostIndex = 0;

  String get activeHost => AppConfig.apiHosts[_hostIndex];

  Future<Map<String, dynamic>> _get(String path, [Map<String, Object?> query = const {}]) async {
    final params = {...query, 'platform': 3, 'region': 0};
    Object? lastFailure;
    for (var i = 0; i < AppConfig.apiHosts.length; i++) {
      final idx = (_hostIndex + i) % AppConfig.apiHosts.length;
      final host = AppConfig.apiHosts[idx];
      try {
        final res = await _dio.get<Object>('$host$path', queryParameters: params);
        final body = res.data is String ? jsonDecode(res.data as String) : res.data;
        if (body is Map && body['results'] is Map) {
          _hostIndex = idx;
          if (lastError.value != null) lastError.value = null;
          return Map<String, dynamic>.from(body['results'] as Map);
        }
        // results:null 是校验未过的静默失败，换下一个主机。
        lastFailure = ApiException(
          body is Map ? '数据源拒绝请求（${body['code']}：${body['message']}）' : '数据源返回了无法识别的内容',
        );
      } on DioException catch (e) {
        lastFailure = e;
      } on FormatException {
        lastFailure = const ApiException('数据源返回了无法识别的内容');
      }
    }
    final failure = lastFailure is ApiException ? lastFailure : ApiException(_describe(lastFailure));
    lastError.value = ApiDiagnosis(
      host: Uri.parse(AppConfig.apiHosts[_hostIndex]).host,
      message: failure.message,
      at: DateTime.now(),
    );
    throw failure;
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

  /// 用最新列表接口测一次连通性，返回耗时。
  Future<Duration> ping() async {
    final sw = Stopwatch()..start();
    await comics(limit: 1);
    return sw.elapsed;
  }
}
