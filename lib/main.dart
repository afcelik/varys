import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/router/router_provider.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Turkish date formatting
  await initializeDateFormatting('tr_TR', null);

  // Load .env file if it exists (ignore if not found for tests)
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // .env file not found, using defaults - this is fine for tests
  }

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