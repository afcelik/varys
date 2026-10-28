import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer' as dev;

/// Secure storage service for persisting sensitive data like API tokens and server URLs.
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
  static const String _apiTokenKey = 'api_token';
  static const String _appPasswordKey = 'app_password';

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

  /// Gets the API token from .env, or falls back to secure storage.
  static Future<String?> getApiToken() async {
    try {
      // First try .env
      final envToken = dotenv.env['API_TOKEN'];
      if (envToken != null && envToken.isNotEmpty) {
        return envToken;
      }
    } catch (e) {
      // dotenv not initialized, continue to secure storage
    }
    // Fallback to secure storage
    return await _storage.read(key: _apiTokenKey);
  }

  /// Stores the API token in secure storage (as fallback/override).
  static Future<void> setApiToken(String token) async {
    dev.log('SecureStorage: Writing token (length: ${token.length})', name: 'SecureStorage');
    await _storage.write(key: _apiTokenKey, value: token);
    dev.log('SecureStorage: Write completed', name: 'SecureStorage');
  }

  /// Clears the API token from secure storage.
  static Future<void> clearApiToken() async {
    dev.log('SecureStorage: Deleting token', name: 'SecureStorage');
    await _storage.delete(key: _apiTokenKey);
    dev.log('SecureStorage: Delete completed', name: 'SecureStorage');
  }

  /// Clears all stored data from secure storage.
  static Future<void> clearAll() async {
    dev.log('SecureStorage: Clearing all', name: 'SecureStorage');
    await _storage.deleteAll();
    dev.log('SecureStorage: Clear completed', name: 'SecureStorage');
  }

  /// Checks if an API token is available (from .env or secure storage).
  static Future<bool> hasApiToken() async {
    try {
      final envToken = dotenv.env['API_TOKEN'];
      if (envToken != null && envToken.isNotEmpty) {
        dev.log('SecureStorage: hasApiToken - found in .env', name: 'SecureStorage');
        return true;
      }
    } catch (e) {
      // dotenv not initialized, continue to secure storage
    }
    final token = await _storage.read(key: _apiTokenKey);
    final hasToken = token != null && token.isNotEmpty;
    dev.log('SecureStorage: hasApiToken read result: $hasToken (token: ${token?.substring(0, 10) ?? "null"}...)', name: 'SecureStorage');
    return hasToken;
  }

  /// Gets the local app password from .env, or falls back to secure storage.
  static Future<String?> getAppPassword() async {
    try {
      // First try .env
      final envPassword = dotenv.env['APP_PASSWORD'];
      if (envPassword != null && envPassword.isNotEmpty) {
        return envPassword;
      }
    } catch (e) {
      // dotenv not initialized, continue to secure storage
    }
    // Fallback to secure storage
    return await _storage.read(key: _appPasswordKey);
  }

  /// Stores the app password in secure storage (as fallback/override).
  static Future<void> setAppPassword(String password) async {
    dev.log('SecureStorage: Writing app password', name: 'SecureStorage');
    await _storage.write(key: _appPasswordKey, value: password);
    dev.log('SecureStorage: Write completed', name: 'SecureStorage');
  }

  /// Checks if an app password is set.
  static Future<bool> hasAppPassword() async {
    try {
      final envPassword = dotenv.env['APP_PASSWORD'];
      if (envPassword != null && envPassword.isNotEmpty) {
        return true;
      }
    } catch (e) {
      // dotenv not initialized, continue to secure storage
    }
    final password = await _storage.read(key: _appPasswordKey);
    return password != null && password.isNotEmpty;
  }
}