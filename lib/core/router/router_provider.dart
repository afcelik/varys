import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/router/app_router.dart';

/// Riverpod provider for the application router
final routerProvider = Provider<GoRouter>((ref) {
  return AppRouter.router;
});