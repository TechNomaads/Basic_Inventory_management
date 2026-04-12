/// [AuthNotifier] — Riverpod state notifier for authentication state.
///
/// Responsibilities:
///   - Manage auth state: unauthenticated → loading → authenticated
///   - Expose login/logout actions
///   - Provide current user info to the widget tree
///
/// Dependencies: auth_repository, Riverpod

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../data/auth_remote_datasource.dart';
import '../data/auth_repository.dart';
import 'user_model.dart';

/// Auth state — sealed union of possible states
sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final UserModel user;
  const AuthAuthenticated(this.user);
}

class AuthUnauthenticated extends AuthState {
  final String? message;
  const AuthUnauthenticated({this.message});
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

/// Provider for the auth repository
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final storage = ref.watch(secureStorageProvider);
  return AuthRepository(AuthRemoteDatasource(dio), storage);
});

/// Provider for current auth state
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref);
});

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;

  AuthNotifier(this._ref) : super(const AuthInitial());

  /// Check if user is already logged in
  Future<void> checkAuth() async {
    state = const AuthLoading();

    final repo = _ref.read(authRepositoryProvider);
    final result = await repo.checkAuth();

    result.fold(
      (failure) => state = AuthUnauthenticated(message: failure.message),
      (user) => state = AuthAuthenticated(user),
    );
  }

  /// Login with email and password
  Future<void> login(String email, String password) async {
    state = const AuthLoading();

    // Use a separate Dio without interceptor for login
    final loginDio = Dio(BaseOptions(baseUrl: ApiEndpoints.baseUrl));
    final storage = _ref.read(secureStorageProvider);

    try {
      final response = await loginDio.post(
        ApiEndpoints.login,
        data: {'email': email, 'password': password},
      );

      final data = response.data as Map<String, dynamic>;

      await storage.saveTokens(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
      );

      // Decode JWT to get user info
      final payload = _decodeJwt(data['access_token'] as String);
      final userId = payload['sub'] as String? ?? '';
      final role = payload['role'] as String? ?? 'staff';

      await storage.saveUserInfo(
        userId: userId,
        userName: email.split('@').first,
        role: role,
      );

      state = AuthAuthenticated(UserModel(
        id: userId,
        name: email.split('@').first,
        email: email,
        role: role,
      ));
    } on DioException catch (e) {
      final msg = e.response?.data?['detail']?.toString() ??
          'Invalid email or password';
      state = AuthError(msg);
    } catch (e) {
      state = AuthError(e.toString());
    }
  }

  /// Logout
  Future<void> logout() async {
    final repo = _ref.read(authRepositoryProvider);
    await repo.logout();
    state = const AuthUnauthenticated();
  }

  /// Decode JWT payload (without verification)
  Map<String, dynamic> _decodeJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return {};

      String payload = parts[1];
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }

      final decoded = utf8.decode(base64Url.decode(payload));
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
