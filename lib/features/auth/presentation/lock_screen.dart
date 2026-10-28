import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:developer';

import 'package:varys/core/storage/secure_storage.dart';
import 'package:varys/core/router/app_router.dart';

/// Lock screen - entry point when app is locked.
///
/// The password is the local app password (from .env or secure storage).
/// Clean, minimalist dark theme with password visibility toggle.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  static const String routePath = '/lock';
  static const String routeName = 'lock';

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final password = _passwordController.text.trim();

    try {
      final storedPassword = await SecureStorage.getAppPassword();

      if (storedPassword == password) {
        log('LockScreen: Password verified', name: 'LockScreen');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kilit açıldı'),
              duration: Duration(seconds: 2),
            ),
          );
          context.go(AppRouter.homePath);
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = 'Yanlış şifre';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      log('LockScreen: Unlock error: $e', name: 'LockScreen');
      if (mounted) {
        setState(() {
          _errorMessage = 'Hata: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToChangePassword() {
    context.push('/change-password');
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
                    // App Logo/Title
                    Icon(
                      Icons.lock_outline,
                      size: 80,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Varys',
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w300,
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Uygulama Kilitli',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 48),

                    // Password Field
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Uygulama Şifresi',
                        hintText: 'Uygulama şifrenizi girin',
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
                        helperText: '.env dosyasındaki APP_PASSWORD veya ayarlarda belirlenen şifre',
                        border: const OutlineInputBorder(),
                      ),
                      textInputAction: TextInputAction.done,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Şifre gerekli';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _unlock(),
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

                    // Unlock Button
                    FilledButton(
                      onPressed: _isLoading ? null : _unlock,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Kilidi Aç', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(height: 16),

                    // Change Password Button
                    TextButton(
                      onPressed: _isLoading ? null : _navigateToChangePassword,
                      child: const Text('Şifre Değiştir'),
                    ),
                    const SizedBox(height: 16),

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
                              '• Uygulama şifresi .env dosyasındaki APP_PASSWORD değerinden alınır\n'
                              '• Şifre güvenli bir şekilde cihazınızda saklanır (Ayarlar > Şifre Değiştir)\n'
                              '• Backend API token .env dosyasından okunur, kullanıcıdan istenmez\n'
                              '• AI sağlayıcıları (NVIDIA vb.) için API anahtarları asla istemciye gönderilmez\n'
                              '• Tüm AI etkileşimleri backend üzerinden güvenli bir şekilde gerçekleşir',
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
        ),
      ),
    );
  }
}