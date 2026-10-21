import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/router_provider.dart';
import 'core/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: VarysApp()));
}

class VarysApp extends ConsumerWidget {
  const VarysApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Varys',
      theme: AppTheme.darkTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}