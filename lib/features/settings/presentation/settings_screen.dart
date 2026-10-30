import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:developer';

import 'package:varys/core/network/api_client.dart';
import 'package:varys/core/storage/secure_storage.dart';
import 'package:varys/features/auth/domain/auth_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Settings screen for configuring app settings.
///
/// Allows user to set server URL and log out.
/// API token is managed by backend authentication (JWT).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static const String routePath = '/settings';
  static const String routeName = 'settings';

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();

  bool _isTestingConnection = false;
  String? _connectionTestResult;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSettings() async {
    final serverUrl = await SecureStorage.getServerUrl();

    if (mounted) {
      _serverUrlController.text = serverUrl;
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    log('SettingsScreen: Saving settings...', name: 'SettingsScreen');
    log('SettingsScreen: Server URL: ${_serverUrlController.text.trim()}', name: 'SettingsScreen');

    await SecureStorage.setServerUrl(_serverUrlController.text.trim());

    if (mounted) {
      log('SettingsScreen: Settings saved', name: 'SettingsScreen');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ayarlar kaydedildi'),
          duration: Duration(seconds: 2),
        ),
      );
      // Invalidate providers to recreate ApiClient with new settings
      ref.invalidate(apiClientProvider);
      ref.invalidate(serverUrlProvider);
      ref.invalidate(authTokenProvider);
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTestingConnection = true;
      _connectionTestResult = null;
    });

    try {
      // Create a temporary ApiClient with the entered settings
      final authToken = await SecureStorage.getAuthToken();
      final tempClient = ApiClient(
        baseUrl: _serverUrlController.text.trim(),
        authToken: authToken,
      );

      final success = await tempClient.testConnection();

      if (mounted) {
        setState(() {
          _connectionTestResult = success
              ? 'Bağlantı başarılı! Sunucu yanıt verdi.'
              : 'Bağlantı başarısız. Sunucu yanıt vermedi.';
          _isTestingConnection = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionTestResult = 'Bağlantı hatası: ${e.toString()}';
          _isTestingConnection = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    // Confirm logout
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text('Oturumu kapatmak istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Logout via AuthNotifier
    await ref.read(authNotifierProvider.notifier).logout();

    // Navigate to login - router will handle redirect
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: const Text('Ayarlar'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Server URL Section
                Text(
                  'Sunucu Ayarları',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _serverUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Sunucu Adresi',
                    hintText: 'Örn: http://192.168.1.100:8000',
                    prefixIcon: Icon(Icons.dns_outlined),
                    helperText: 'Backend API sunucusunun adresini girin',
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Sunucu adresi gerekli';
                    }
                    final uri = Uri.tryParse(value.trim());
                    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                      return 'Geçerli bir URL girin (örn: http://host:port)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // Test Connection Button
                FilledButton.icon(
                  onPressed: _isTestingConnection ? null : _testConnection,
                  icon: _isTestingConnection
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering),
                  label: Text(_isTestingConnection ? 'Test Ediliyor...' : 'Bağlantıyı Test Et'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 16),

                // Connection Test Result
                if (_connectionTestResult != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _connectionTestResult!.contains('başarılı')
                          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                          : theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _connectionTestResult!.contains('başarılı')
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _connectionTestResult!.contains('başarılı')
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: _connectionTestResult!.contains('başarılı')
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _connectionTestResult!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _connectionTestResult!.contains('başarılı')
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Save Button
                FilledButton(
                  onPressed: _saveSettings,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Kaydet'),
                ),
                const SizedBox(height: 32),

                // Account Section
                Text(
                  'Hesap',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                // Logout Button
                OutlinedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Çıkış Yap'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    foregroundColor: theme.colorScheme.error,
                    side: BorderSide(color: theme.colorScheme.error),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Oturumunuzu kapatır ve giriş sayfasına yönlendirir. Sunucu adresi saklanır.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}