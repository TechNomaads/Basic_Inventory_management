/// [AuthRemoteDatasource] — Handles authentication API calls.
///
/// Responsibilities:
///   - POST /auth/login
///   - POST /auth/refresh
///   - POST /auth/logout

import 'package:dio/dio.dart';

import '../../../core/constants/api_endpoints.dart';

class AuthRemoteDatasource {
  final Dio _dio;

  AuthRemoteDatasource(this._dio);

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post(
      ApiEndpoints.login,
      data: {'email': email, 'password': password},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> refreshToken(String refreshToken) async {
    final response = await _dio.post(
      ApiEndpoints.refresh,
      data: {'refresh_token': refreshToken},
    );
    return response.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await _dio.post(ApiEndpoints.logout);
  }
}
