import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:varys/core/storage/secure_storage.dart';
import 'package:varys/features/auth/domain/auth_notifier.dart';
import 'package:varys/features/auth/domain/auth_state.dart';

/// Login page - server-based authentication.
///
/// First startup: "Server address" and "Password" fields.
/// Subsequent startups: only "Password" (address registered).
/// "Change server" link to switch servers.
/// Show/hide icon in password field.
/// Button loading status, prevent double clicks.
/// Error messages in Turkish: wrong password, server unreachable, too many attempts (429).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  static const String routePath = '/login';
  static const String routeName = 'login';

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _serverUrlController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _showServerField = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkStoredServerUrl();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Checks if server URL is already stored.
  Future<void> _checkStoredServerUrl() async {
    final storedUrl = await SecureStorage.getServerUrl();
    final defaultUrl = SecureStorage.defaultServerUrl;

    if (mounted) {
      setState(() {
        // Show server field only if no custom URL is stored (or only default)
        _showServerField = storedUrl == defaultUrl;
        if (!_showServerField) {
          _serverUrlController.text = storedUrl;
        }
      });
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Prevent double clicks
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final serverUrl = _showServerField
        ? _serverUrlController.text.trim()
        : await SecureStorage.getServerUrl();
    final password = _passwordController.text;

    // Clear password from memory immediately after getting it
    final success = await ref.read(authNotifierProvider.notifier).login(
          serverUrl: serverUrl,
          password: password,
        );

    // Password variable goes out of scope here - not stored anywhere

    if (mounted) {
      if (success) {
        // Navigate to home - router will handle redirect via AuthNotifier
        context.go('/home');
      } else {
        // Error state already set in notifier, read it
        final authState = ref.read(authNotifierProvider);
        if (authState is AuthError) {
          setState(() {
            _errorMessage = authState.message;
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  void _toggleServerField() {
    setState(() {
      _showServerField = true;
      _serverUrlController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Varys Title (Centered)
                    Text(
                      'Varys',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w300,
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Server Address Field (only on first startup or when "Change server" clicked)
                    if (_showServerField) ...[
                      TextFormField(
                        controller: _serverUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Sunucu Adresi',
                          hintText: 'Örn: http://192.168.1.100:8000',
                          prefixIcon: Icon(Icons.dns_outlined),
                          helperText: 'Backend API sunucusunun adresini girin',
                          border: OutlineInputBorder(),
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
                      const SizedBox(height: 16),
                    ] else ...[
                      // Show current server as read-only with "Change server" link
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.dns_outlined,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Sunucu Adresi',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  Text(
                                    _serverUrlController.text,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: _isLoading ? null : _toggleServerField,
                              child: const Text('Sunucu Değiştir'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Password Field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Şifre',
                        hintText: 'Şifrenizi girin',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Şifre gerekli';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _login(),
                    ),
                    const SizedBox(height: 16),

                    // Error Message
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Login Button
                    FilledButton(
                      onPressed: _isLoading ? null : _login,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Giriş Yap', style: TextStyle(fontSize: 16)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}