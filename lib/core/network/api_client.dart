import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/secure_storage.dart';
import '../../features/auth/domain/auth_notifier.dart'; // For authNotifierProvider

/// Dio-based API client for communicating with the Varys backend.
///
/// JWT token is loaded from secure storage (set after login).
/// Provides methods for making authenticated API requests.
/// Includes interceptor for automatic 401 handling (token expiry).
class ApiClient {
  late final Dio _dio;
  final String? _authToken;
  final Future<void> Function()? _onSessionExpired;

  /// Creates an ApiClient with the given base URL and optional auth token.
  ApiClient({
    required String baseUrl,
    String? authToken,
    Future<void> Function()? onSessionExpired,
  }) : _authToken = authToken,
       _onSessionExpired = onSessionExpired {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    if (authToken != null && authToken.isNotEmpty) {
      _dio.options.headers['Authorization'] = 'Bearer $authToken';
    }

    // Add logging interceptor only in debug mode
    if (kDebugMode) {
      _dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestHeader: false,
          requestBody: false,
          responseHeader: false,
          responseBody: false,
          error: true,
        ),
      );
    }

    // Add 401 interceptor for token expiry handling
    _dio.interceptors.add(InterceptorsWrapper(
      onError: (DioException error, ErrorInterceptorHandler handler) async {
        if (error.response?.statusCode == 401 && _onSessionExpired != null) {
          // Check if this is a login request - don't trigger logout for wrong password
          final requestPath = error.requestOptions.path;
          if (requestPath == '/auth/login') {
            return handler.next(error);
          }

          // Check if request has Authorization header
          final requestAuthHeader = error.requestOptions.headers['Authorization'];
          if (requestAuthHeader == null) {
            return handler.next(error);
          }

          // Extract token from request header
          final requestToken = requestAuthHeader.toString().replaceFirst('Bearer ', '');

          // Compare with current session token
          if (requestToken == _authToken) {
            // Token matches current session - trigger session expired
            await _onSessionExpired();
          }
          // If tokens don't match, it's a late 401 from old token after re-login - ignore
        }
        return handler.next(error);
      },
    ));
  }

  /// Creates an ApiClient from stored credentials (loads from secure storage).
  static Future<ApiClient> fromStorage() async {
    final baseUrl = await SecureStorage.getServerUrl();
    final authToken = await SecureStorage.getAuthToken();
    return ApiClient(baseUrl: baseUrl, authToken: authToken);
  }

  /// Creates an ApiClient from stored credentials with session expiry callback.
  static Future<ApiClient> fromStorageWithCallback(
    String baseUrl,
    String? authToken,
    Future<void> Function() onSessionExpired,
  ) async {
    return ApiClient(
      baseUrl: baseUrl,
      authToken: authToken,
      onSessionExpired: onSessionExpired,
    );
  }

  /// Creates a login client (no auth token) for authentication requests.
  static Future<ApiClient> forLogin(String serverUrl) async {
    return ApiClient(baseUrl: serverUrl, authToken: null);
  }

  /// Gets the underlying Dio instance for advanced usage.
  Dio get dio => _dio;

  /// Gets the current base URL.
  String get baseUrl => _dio.options.baseUrl;

  /// Updates the base URL and recreates the Dio instance.
  void updateBaseUrl(String newBaseUrl) {
    _dio.options.baseUrl = newBaseUrl;
  }

  /// Sets the authentication token.
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Clears the authentication token.
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  /// Checks if an auth token is currently set.
  bool get hasAuthToken => _dio.options.headers['Authorization'] != null;

  /// Makes a GET request to test the connection (health endpoint).
  Future<bool> testConnection() async {
    try {
      final response = await _dio.get('/health');
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  /// Makes a POST request for login.
  Future<Response<Map<String, dynamic>>> login(String password) async {
    return _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'password': password},
    );
  }

  /// Makes a GET request.
  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters}) async {
    return _dio.get<T>(path, queryParameters: queryParameters);
  }

  /// Makes a POST request.
  Future<Response<T>> post<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    return _dio.post<T>(path, data: data, queryParameters: queryParameters);
  }

  /// Makes a PUT request.
  Future<Response<T>> put<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    return _dio.put<T>(path, data: data, queryParameters: queryParameters);
  }

  /// Makes a PATCH request.
  Future<Response<T>> patch<T>(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    return _dio.patch<T>(path, data: data, queryParameters: queryParameters);
  }

  /// Makes a DELETE request.
  Future<Response<T>> delete<T>(String path, {Map<String, dynamic>? queryParameters}) async {
    return _dio.delete<T>(path, queryParameters: queryParameters);
  }
}

/// Riverpod provider for the ApiClient.
///
/// This provider creates an ApiClient instance from stored credentials.
/// It uses a FutureProvider since reading from secure storage is async.
/// The onSessionExpired callback is evaluated at call time to avoid circular dependency.
final apiClientProvider = FutureProvider<ApiClient>((ref) async {
  final baseUrl = await SecureStorage.getServerUrl();
  final authToken = await SecureStorage.getAuthToken();

  return ApiClient.fromStorageWithCallback(
    baseUrl,
    authToken,
    () => ref.read(authNotifierProvider.notifier).handleSessionExpired(ref),
  );
});

/// Riverpod provider for the Dio instance (for direct access if needed).
///
/// Uses FutureProvider since it depends on ApiClient which is async.
final dioProvider = FutureProvider<Dio>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return apiClient.dio;
});

/// Riverpod provider for the current server URL.
final serverUrlProvider = FutureProvider<String>((ref) async {
  return await SecureStorage.getServerUrl();
});

/// Riverpod provider for the current JWT auth token (nullable).
final authTokenProvider = FutureProvider<String?>((ref) async {
  return await SecureStorage.getAuthToken();
});