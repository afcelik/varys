import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer' as dev;

/// Secure storage service for persisting sensitive data like JWT tokens and server URLs.
///
/// Uses flutter_secure_storage which provides platform-specific secure storage:
/// - iOS: Keychain
/// - Android: Keystore (API 23+) / SharedPreferences with encryption (API < 23)
/// - Linux: libsecret
/// - macOS: Keychain
/// - Windows: Credential Manager
///
/// Also reads configuration from .env file (loaded at app startup).
class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    lOptions: LinuxOptions(),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    wOptions: WindowsOptions(),
  );

  // Storage keys
  static const String _serverUrlKey = 'server_url';
  static const String _authTokenKey = 'auth_token';

  /// Default server URL (can be overridden by user settings)
  static const String defaultServerUrl = 'http://10.0.2.2:8000'; // Android emulator default

  /// Gets the server URL from .env, or falls back to stored value, then default.
  static Future<String> getServerUrl() async {
    try {
      // First try .env
      final envUrl = dotenv.env['SERVER_URL'];
      if (envUrl != null && envUrl.isNotEmpty) {
        return envUrl;
      }
    } catch (e) {
      // dotenv not initialized, continue to secure storage
    }
    // Fallback to secure storage
    final url = await _storage.read(key: _serverUrlKey);
    return url ?? defaultServerUrl;
  }

  /// Stores the server URL in secure storage.
  static Future<void> setServerUrl(String url) async {
    await _storage.write(key: _serverUrlKey, value: url);
  }

  /// Gets the JWT auth token from secure storage.
  static Future<String?> getAuthToken() async {
    return await _storage.read(key: _authTokenKey);
  }

  /// Stores the JWT auth token in secure storage.
  static Future<void> setAuthToken(String token) async {
    dev.log('SecureStorage: Writing auth token (length: ${token.length})', name: 'SecureStorage');
    await _storage.write(key: _authTokenKey, value: token);
    dev.log('SecureStorage: Write completed', name: 'SecureStorage');
  }

  /// Clears the JWT auth token from secure storage.
  static Future<void> clearAuthToken() async {
    dev.log('SecureStorage: Deleting auth token', name: 'SecureStorage');
    await _storage.delete(key: _authTokenKey);
    dev.log('SecureStorage: Delete completed', name: 'SecureStorage');
  }

  /// Clears all stored data from secure storage.
  static Future<void> clearAll() async {
    dev.log('SecureStorage: Clearing all', name: 'SecureStorage');
    await _storage.deleteAll();
    dev.log('SecureStorage: Clear completed', name: 'SecureStorage');
  }

  /// Checks if a JWT auth token is available.
  static Future<bool> hasAuthToken() async {
    final token = await _storage.read(key: _authTokenKey);
    return token != null && token.isNotEmpty;
  }
}