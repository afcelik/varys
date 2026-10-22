import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:varys/core/network/api_client.dart';
import 'package:varys/core/storage/secure_storage.dart';

/// Settings screen for configuring backend connection.
///
/// Allows user to set server URL and API token, and test the connection.
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
  final _apiTokenController = TextEditingController();

  bool _isTestingConnection = false;
  String? _connectionTestResult;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _loadSavedSettings();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _apiTokenController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSettings() async {
    final serverUrl = await SecureStorage.getServerUrl();
    final apiToken = await SecureStorage.getApiToken();

    if (mounted) {
      _serverUrlController.text = serverUrl;
      _apiTokenController.text = apiToken ?? '';
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final notifier = ref.read(authNotifierProvider.notifier);
    await notifier.updateServerUrl(_serverUrlController.text.trim());
    await notifier.setApiToken(_apiTokenController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ayarlar kaydedildi'),
          duration: Duration(seconds: 2),
        ),
      );
      // Invalidate providers to recreate ApiClient with new settings
      ref.invalidate(apiClientProvider);
      ref.invalidate(isAuthenticatedProvider);
      ref.invalidate(serverUrlProvider);
      ref.invalidate(apiTokenProvider);
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
      final tempClient = ApiClient(
        baseUrl: _serverUrlController.text.trim(),
        authToken: _apiTokenController.text.trim().isEmpty
            ? null
            : _apiTokenController.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
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

                // API Token Section
                Text(
                  'Kimlik Doğrulama',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _apiTokenController,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    labelText: 'API Token',
                    hintText: 'Backend API token\'ınızı girin',
                    prefixIcon: const Icon(Icons.vpn_key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureToken ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureToken = !_obscureToken;
                        });
                      },
                    ),
                    helperText: 'Bu token sadece backend erişimi içindir. AI API anahtarları asla istemciye gelmez.',
                  ),
                  textInputAction: TextInputAction.done,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'API token gerekli';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _testConnection(),
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

                // Info Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: theme.colorScheme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Bilgi',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '• Sunucu adresi ve API token güvenli bir şekilde cihazınızda saklanır\n'
                          '• AI sağlayıcıları (NVIDIA vb.) için API anahtarları asla istemciye gönderilmez\n'
                          '• Tüm AI etkileşimleri backend üzerinden güvenli bir şekilde gerçekleşir\n'
                          '• Token\'ınızı kaybettiyseniz backend yöneticisinden yeni bir tane isteyin',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}