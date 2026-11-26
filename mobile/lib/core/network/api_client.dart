import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../data/user_facing_error.dart';
import '../storage/token_storage.dart';
import '../../features/diagnosis/data/analyses_repository.dart';
import 'api_error.dart';

/// Thin wrapper around Dio for the FastAPI backend (/api/v1).
/// Only repositories use this — screens never import Dio.
///
/// It adds the access token to every request. When the server answers 401 it
/// exchanges the refresh token for a new pair once and repeats the request;
/// if that fails the tokens are cleared and [onSessionExpired] is called.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenStorage tokens,
    this.onSessionExpired,
    HttpClientAdapter? adapter,
  })  : _tokens = tokens,
        _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Accept': 'application/json'},
        )) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _plain.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(QueuedInterceptorsWrapper(onRequest: _addToken, onError: _refreshOn401));
  }

  final Dio _dio;

  /// Without interceptors: used for the refresh call and for repeating a
  /// request after a refresh, so neither can re-enter the 401 handling.
  late final Dio _plain = Dio(BaseOptions(baseUrl: _dio.options.baseUrl, connectTimeout: _dio.options.connectTimeout));
  final TokenStorage _tokens;

  /// Called when the session can no longer be refreshed (the user must sign in again).
  final void Function()? onSessionExpired;

  static const _retried = 'retried_after_refresh';

  bool _isAuthCall(RequestOptions o) => o.path.startsWith('/auth/');

  Future<void> _addToken(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isAuthCall(options)) {
      final token = await _tokens.readAccessToken();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  Future<void> _refreshOn401(DioException error, ErrorInterceptorHandler handler) async {
    final request = error.requestOptions;
    if (error.response?.statusCode != 401 || _isAuthCall(request) || request.extra[_retried] == true) {
      return handler.next(error);
    }
    final refresh = await _tokens.readRefreshToken();
    if (refresh == null) {
      onSessionExpired?.call();
      return handler.next(error);
    }
    try {
      final response =
          await _plain.post<Map<String, dynamic>>('/auth/refresh', data: {'refresh_token': refresh});
      final data = response.data!;
      await _tokens.saveTokens(access: data['access_token'] as String, refresh: data['refresh_token'] as String);
    } on DioException catch (e) {
      // Only a rejected refresh ends the session; a network problem does not.
      if (e.response?.statusCode == 401) {
        await _tokens.clear();
        onSessionExpired?.call();
      }
      return handler.next(error);
    }
    try {
      request.extra[_retried] = true;
      request.headers['Authorization'] = 'Bearer ${await _tokens.readAccessToken()}';
      handler.resolve(await _plain.fetch<dynamic>(request));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) async =>
      (await _send(() => _dio.get<dynamic>(path, queryParameters: query)) as Map).cast<String, dynamic>();

  Future<List<Map<String, dynamic>>> getList(String path, {Map<String, dynamic>? query}) async => [
        for (final item in await _send(() => _dio.get<dynamic>(path, queryParameters: query)) as List)
          (item as Map).cast<String, dynamic>(),
      ];

  Future<Map<String, dynamic>> postJson(String path, {Object? body}) async =>
      (await _send(() => _dio.post<dynamic>(path, data: body)) as Map).cast<String, dynamic>();

  Future<Map<String, dynamic>> patchJson(String path, {Object? body}) async =>
      (await _send(() => _dio.patch<dynamic>(path, data: body)) as Map).cast<String, dynamic>();

  /// POST of a raw file (e.g. a full MRI scan), answered with JSON.
  Future<Map<String, dynamic>> postBytes(String path, Uint8List bytes, {Map<String, dynamic>? query}) async =>
      (await _send(() => _dio.post<dynamic>(
                path,
                data: Stream.fromIterable([bytes]),
                queryParameters: query,
                options: Options(
                  contentType: 'application/octet-stream',
                  headers: {Headers.contentLengthHeader: bytes.length},
                  sendTimeout: const Duration(minutes: 5),
                ),
              )) as Map)
          .cast<String, dynamic>();

  /// GET of a file (e.g. a report PDF): its bytes and the file name the server suggests.
  Future<({Uint8List bytes, String? filename})> getFile(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 2)),
      );
      final disposition = response.headers.value('content-disposition');
      final filename = disposition == null ? null : RegExp(r'filename="([^"]+)"').firstMatch(disposition)?.group(1);
      return (bytes: Uint8List.fromList(response.data ?? const []), filename: filename);
    } on DioException catch (e) {
      // Error replies are JSON even here; decode them so the message reaches the screen.
      final data = e.response?.data;
      if (data is List<int>) {
        try {
          e.response!.data = jsonDecode(utf8.decode(data));
        } on FormatException {
          // not JSON: keep the generic message
        }
      }
      throw mapApiError(ApiError.fromDio(e));
    }
  }

  /// POST for endpoints that answer 204 with no body.
  Future<void> post(String path, {Object? body}) => _send(() => _dio.post<dynamic>(path, data: body));

  /// Server errors become the exception types the screens already handle.
  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data;
    } on DioException catch (e) {
      throw mapApiError(ApiError.fromDio(e));
    }
  }
}

/// 404 → [NotFoundException], 409 → [ConflictException], validation → the
/// server's message; everything else stays an [ApiError].
UserFacingError mapApiError(ApiError error) => switch (error.statusCode) {
      404 => NotFoundException(error.message),
      409 => ConflictException(error.message),
      _ => error,
    };

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    baseUrl: ref.watch(apiBaseUrlProvider),
    tokens: ref.watch(tokenStorageProvider),
    onSessionExpired: () => ref.read(sessionExpiredProvider.notifier).signal(),
  );
});

/// Counts how often the server has rejected the session. The session
/// controller listens to it and signs the user out.
class SessionExpiry extends Notifier<int> {
  @override
  int build() => 0;

  void signal() => state++;
}

final sessionExpiredProvider = NotifierProvider<SessionExpiry, int>(SessionExpiry.new);
