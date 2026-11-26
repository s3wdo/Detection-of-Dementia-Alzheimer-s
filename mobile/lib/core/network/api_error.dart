import 'package:dio/dio.dart';

import '../data/user_facing_error.dart';

/// Error returned by the future FastAPI backend.
/// The backend's error envelope is: {"error": {"code": "...", "message": "...", "details": {}}}.
class ApiError implements UserFacingError {
  const ApiError({required this.code, required this.message, this.statusCode});

  final String code;
  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;

  factory ApiError.fromDio(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return ApiError(
        code: err['code']?.toString() ?? 'UNKNOWN',
        message: err['message']?.toString() ?? 'Something went wrong.',
        statusCode: status,
      );
    }
    return switch (e.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout =>
        const ApiError(code: 'TIMEOUT', message: 'The server took too long to respond. Please retry.'),
      DioExceptionType.connectionError => const ApiError(code: 'NETWORK', message: 'Connection lost. Please retry.'),
      _ => ApiError(code: 'HTTP_${status ?? 0}', message: 'Something went wrong.', statusCode: status),
    };
  }

  @override
  String toString() => message;
}
