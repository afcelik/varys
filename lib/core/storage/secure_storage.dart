import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage service for persisting sensitive data like API tokens and server URLs.
///
/// Uses flutter_secure_storage which provides platform-specific secure storage:
/// - iOS: Keychain
/// - Android: Keystore (API 23+) / SharedPreferences with encryption (API < 23)
/// - Linux: libsecret
/// - macOS: Keychain
/// - Windows: Credential Manager
class SecureStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    lOptions: LinuxOptions(),
    mOptions: MacOsOptions(),
    wOptions: WindowsOptions(),
  );

  // Storage keys
  static const String _serverUrlKey = 'server_url';
  static const String _apiTokenKey = 'api_token';

  /// Default server URL (can be overridden by user settings)
  static const String defaultServerUrl = 'http://10.0.2.2:8000'; // Android emulator default

  /// Gets the stored server URL, or returns the default if not set.
  static Future<String> getServerUrl() async {
    final url = await _storage.read(key: _serverUrlKey);
    return url ?? defaultServerUrl;
  }

  /// Stores the server URL.
  static Future<void> setServerUrl(String url) async {
    await _storage.write(key: _serverUrlKey, value: url);
  }

  /// Gets the stored API token, or returns null if not set.
  static Future<String?> getApiToken() async {
    return await _storage.read(key: _apiTokenKey);
  }

  /// Stores the API token.
  static Future<void> setApiToken(String token) async {
    await _storage.write(key: _apiTokenKey, value: token);
  }

  /// Clears the API token (logout).
  static Future<void> clearApiToken() async {
    await _storage.delete(key: _apiTokenKey);
  }

  /// Clears all stored data.
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// Checks if an API token is present.
  static Future<bool> hasApiToken() async {
    final token = await _storage.read(key: _apiTokenKey);
    return token != null && token.isNotEmpty;
  }
}