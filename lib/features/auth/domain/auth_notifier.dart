// Auth state notifier for Riverpod.
//
// Manages authentication state and token storage.
// Loads token from secure storage on initialization.
// Provides methods for login, logout, and token validation.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/core/storage/secure_storage.dart';
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
      final errorMessage = _mapErrorToTurkish(e);
      state = AuthError(errorMessage);
      return false;
    }
  }

  /// Maps exceptions to Turkish error messages.
  String _mapErrorToTurkish(Exception e) {
    final errorString = e.toString();

    if (errorString.contains('401') || errorString.contains('Unauthorized')) {
      return 'Yanlış şifre';
    }
    if (errorString.contains('429') || errorString.contains('Too Many Requests')) {
      return 'Çok fazla deneme. Lütfen 15 dakika bekleyin.';
    }
    if (errorString.contains('Connection refused') ||
        errorString.contains('Failed host lookup') ||
        errorString.contains('SocketException') ||
        errorString.contains('HttpException')) {
      return 'Sunucuya bağlanılamıyor. Adresi kontrol edin.';
    }
    if (errorString.contains('Timeout')) {
      return 'Sunucu yanıt vermiyor (zaman aşımı)';
    }
    return 'Giriş hatası: ${e.toString()}';
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