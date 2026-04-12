/// Dio HTTP client with JWT refresh interceptor.
///
/// Responsibilities:
///   - Attach access token to every request
///   - On 401: call /auth/refresh, retry original request
///   - Throw typed exceptions for error handling
///
/// Dependencies: dio, flutter_secure_storage, api_endpoints

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/api_endpoints.dart';
import '../errors/exceptions.dart';
import '../storage/secure_storage.dart';

/// Global Dio instance provider
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiEndpoints.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ));

  dio.interceptors.add(JwtInterceptor(dio: dio, ref: ref));
  return dio;
});

/// JWT interceptor that:
/// 1. Attaches Authorization header
/// 2. Catches 401 → refreshes token → retries request
class JwtInterceptor extends Interceptor {
  final Dio dio;
  final Ref ref;
  bool _isRefreshing = false;

  JwtInterceptor({required this.dio, required this.ref});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final storage = ref.read(secureStorageProvider);
    final token = await storage.getAccessToken();

    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 && !_isRefreshing) {
      _isRefreshing = true;

      try {
        final storage = ref.read(secureStorageProvider);
        final refreshToken = await storage.getRefreshToken();

        if (refreshToken == null) {
          _isRefreshing = false;
          handler.reject(err);
          return;
        }

        // Call refresh endpoint with a fresh Dio instance (no interceptor)
        final refreshDio = Dio(BaseOptions(baseUrl: ApiEndpoints.baseUrl));
        final response = await refreshDio.post(
          ApiEndpoints.refresh,
          data: {'refresh_token': refreshToken},
        );

        if (response.statusCode == 200) {
          final newAccess = response.data['access_token'] as String;
          final newRefresh = response.data['refresh_token'] as String;

          await storage.saveTokens(
            accessToken: newAccess,
            refreshToken: newRefresh,
          );

          // Retry original request with new token
          final opts = err.requestOptions;
          opts.headers['Authorization'] = 'Bearer $newAccess';
          final retryResponse = await dio.fetch(opts);

          _isRefreshing = false;
          handler.resolve(retryResponse);
          return;
        }
      } catch (_) {
        // Refresh failed — force logout
        final storage = ref.read(secureStorageProvider);
        await storage.clearAll();
      }

      _isRefreshing = false;
    }

    // Map HTTP errors to typed exceptions
    if (err.response != null) {
      final status = err.response!.statusCode;
      final message = err.response!.data?['detail'] ?? 'Server error';

      if (status == 403) {
        handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: ForbiddenException(message: message.toString()),
          type: DioExceptionType.badResponse,
          response: err.response,
        ));
        return;
      }
      if (status == 404) {
        handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: NotFoundException(message: message.toString()),
          type: DioExceptionType.badResponse,
          response: err.response,
        ));
        return;
      }
      if (status == 409) {
        handler.reject(DioException(
          requestOptions: err.requestOptions,
          error: const ConflictException(),
          type: DioExceptionType.badResponse,
          response: err.response,
        ));
        return;
      }
    }

    handler.next(err);
  }
}
