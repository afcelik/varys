// Auth state notifier for Riverpod.
//
// Manages authentication state and token storage.
// Loads token from secure storage on initialization.
// Provides methods for login, logout, and token validation.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/core/storage/secure_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'auth_state.dart';

/// Riverpod provider for AuthNotifier.
///
/// Uses StateNotifierProvider which provides a Listenable notifier.
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) => AuthNotifier());

/// AuthNotifier manages authentication state.
///
/// State transitions:
/// - AuthInitial -> (load) -> AuthAuthenticated | AuthUnauthenticated
/// - AuthUnauthenticated -> (login) -> AuthLoading -> AuthAuthenticated | AuthError
/// - AuthAuthenticated -> (logout) -> AuthUnauthenticated
/// - AuthError -> (retry) -> AuthUnauthenticated
///
/// Extends StateNotifier (which extends ChangeNotifier) for GoRouter refreshListenable.
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthInitial()) {
    _loadStoredToken();
  }

  /// Loads stored JWT token from secure storage on app startup.
  Future<void> _loadStoredToken() async {
    try {
      final token = await SecureStorage.getAuthToken();
      if (token != null && token.isNotEmpty) {
        // Validate token format (basic check)
        if (_isValidJwtFormat(token)) {
          state = AuthAuthenticated(token);
        } else {
          // Invalid format, clear it
          await SecureStorage.clearAuthToken();
          state = const AuthUnauthenticated();
        }
      } else {
        state = const AuthUnauthenticated();
      }
    } catch (e) {
      // If storage fails, treat as unauthenticated
      state = const AuthUnauthenticated();
    }
  }

  /// Basic JWT format validation (3 parts separated by dots).
  bool _isValidJwtFormat(String token) {
    final parts = token.split('.');
    return parts.length == 3;
  }

  /// Logs in with server address and password.
  ///
  /// Returns true on success, false on failure.
  /// On success, state becomes AuthAuthenticated with token.
  /// On failure, state becomes AuthError with Turkish error message.
  Future<bool> login({
    required String serverUrl,
    required String password,
  }) async {
    state = const AuthLoading();

    try {
      // Save server URL first
      await SecureStorage.setServerUrl(serverUrl);

      // Create login client (no auth token)
      final apiClient = await ApiClient.forLogin(serverUrl);

      // Make login request
      final response = await apiClient.login(password);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data!;
        final token = data['access_token'] as String?;
        // final expiresIn = data['expires_in'] as int?; // Not used currently

        if (token != null && token.isNotEmpty) {
          // Store token
          await SecureStorage.setAuthToken(token);

          // Update state
          state = AuthAuthenticated(token);
          return true;
        }
      }

      // Unexpected response
      state = const AuthError('Beklenmeyen sunucu yanıtı');
      return false;
    } on Exception catch (e) {
      // Handle DioException and other errors
      final errorMessage = AuthNotifier.mapErrorToTurkish(e);
      state = AuthError(errorMessage);
      return false;
    }
  }

  /// Maps exceptions to Turkish error messages.
  ///
  /// This method maps based on exception type and properties, NOT string matching.
  /// - DioException: maps by type and response statusCode
  /// - PlatformException: secure storage access issues
  /// - Other exceptions: generic error message with debug logging
  ///
  /// This is exposed as a static method for unit testing.
  static String mapErrorToTurkish(Exception e) {
    // Handle DioException (network/HTTP errors)
    if (e is DioException) {
      final statusCode = e.response?.statusCode;

      // Map by HTTP status code
      if (statusCode == 401) {
        return 'Yanlış şifre';
      }
      if (statusCode == 429) {
        return 'Çok fazla deneme. Lütfen 15 dakika bekleyin.';
      }
      if (statusCode != null) {
        return 'Sunucu hatası ($statusCode)';
      }

      // Map by DioExceptionType (connection/timeout errors)
      switch (e.type) {
        case DioExceptionType.connectionError:
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.';
        case DioExceptionType.badResponse:
          // Status code already handled above, but handle unexpected cases
          return 'Sunucu hatası (${e.response?.statusCode ?? 'bilinmiyor'})';
        case DioExceptionType.cancel:
          return 'İstek iptal edildi';
        case DioExceptionType.badCertificate:
          return 'Güvenlik sertifikası hatası';
        case DioExceptionType.unknown:
      case DioExceptionType.transformTimeout:
          return 'Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.';
      }
    }

    // Handle PlatformException (secure storage, etc.)
    if (e is PlatformException) {
      debugPrint('PlatformException caught: code=${e.code}, message=${e.message}, details=${e.details}');
      return 'Güvenli depolama erişilemiyor. Lütfen uygulama izinlerini kontrol edin.';
    }

    // Unexpected errors - log details but show generic message
    debugPrint('Unexpected error during login: ${e.runtimeType} - $e');
    return 'Giriş sırasında bir hata oluştu';
  }

  /// Logs out the user - clears token and returns to unauthenticated state.
  Future<void> logout() async {
    await SecureStorage.clearAuthToken();
    state = const AuthUnauthenticated();
  }

  /// Updates the stored token (e.g., after token refresh).
  Future<void> updateToken(String token) async {
    await SecureStorage.setAuthToken(token);
    state = AuthAuthenticated(token);
  }

  /// Clears error state, returns to unauthenticated.
  void clearError() {
    if (state is AuthError) {
      state = const AuthUnauthenticated();
    }
  }
}