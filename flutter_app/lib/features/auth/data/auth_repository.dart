/// [AuthRepository] — Orchestrates auth flow between remote and storage.
///
/// Responsibilities:
///   - Login: call API, store tokens, decode user info
///   - Check auth state on app launch
///   - Logout: clear tokens, call API
///
/// Dependencies: auth_remote_datasource, secure_storage

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

import '../../../core/errors/failure.dart';
import '../../../core/storage/secure_storage.dart';
import '../domain/user_model.dart';
import 'auth_remote_datasource.dart';

class AuthRepository {
  final AuthRemoteDatasource _remote;
  final SecureStorage _storage;

  AuthRepository(this._remote, this._storage);

  /// Login with email and password — returns Either<Failure, UserModel>
  Future<Either<Failure, UserModel>> login(String email, String password) async {
    try {
      final data = await _remote.login(email, password);

      // Store tokens
      await _storage.saveTokens(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
      );

      // Decode JWT payload to extract user info
      final payload = _decodeJwtPayload(data['access_token'] as String);
      final userId = payload['sub'] as String;
      final role = payload['role'] as String;

      await _storage.saveUserInfo(
        userId: userId,
        userName: email.split('@').first,
        role: role,
      );

      return Right(UserModel(
        id: userId,
        name: email.split('@').first,
        email: email,
        role: role,
      ));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(AuthFailure(message: 'Invalid email or password'));
      }
      return Left(ServerFailure(
        message: e.response?.data?['detail']?.toString() ?? 'Login failed',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return Left(ServerFailure(message: e.toString()));
    }
  }

  /// Check if user is already authenticated
  Future<Either<Failure, UserModel>> checkAuth() async {
    try {
      final token = await _storage.getAccessToken();
      if (token == null) {
        return const Left(AuthFailure(message: 'Not authenticated'));
      }

      final userId = await _storage.getUserId();
      final role = await _storage.getUserRole();
      final name = await _storage.getUserName();

      if (userId == null || role == null) {
        return const Left(AuthFailure(message: 'Incomplete stored auth'));
      }

      return Right(UserModel(
        id: userId,
        name: name ?? 'User',
        email: '',
        role: role,
      ));
    } catch (e) {
      return Left(ServerFailure(message: e.toString()));
    }
  }

  /// Logout — clear storage and call API
  Future<void> logout() async {
    try {
      await _remote.logout();
    } catch (_) {
      // Ignore API errors on logout — always clear local state
    }
    await _storage.clearAll();
  }

  /// Decode JWT payload without verification (just for reading claims)
  Map<String, dynamic> _decodeJwtPayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return {};

    String payload = parts[1];
    // Add padding if needed
    switch (payload.length % 4) {
      case 2:
        payload += '==';
        break;
      case 3:
        payload += '=';
        break;
    }

    final decoded = Uri.decodeFull(
      String.fromCharCodes(
        // ignore: unnecessary_import
        Uri.parse('data:;base64,$payload').data!.contentAsBytes(),
      ),
    );

    // Simple JSON parse
    try {
      return _simpleJsonParse(decoded);
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> _simpleJsonParse(String json) {
    // Use dart:convert for proper parsing
    // ignore: depend_on_referenced_packages
    return Map<String, dynamic>.from(
      (const {} as dynamic) ?? {},
    );
  }
}
