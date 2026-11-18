import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/main.dart';

/// Pumps the real app root ([VarysApp] from main.dart: theme, forced `tr`
/// locale and localization delegates). With [router] null the real
/// `routerProvider` (AppRouter.createRouter) is used; otherwise [router].
///
/// Use this for every test that opens a date picker or another Material
/// dialog, so Material texts (İptal/Tamam, tooltips) are the real Turkish ones.
///
/// [textScale] sets the platform text scale for this test (reset on teardown).
/// Does not pump-and-settle; callers decide how to wait.
Future<void> pumpVarysApp(
  WidgetTester tester, {
  GoRouter? router,
  List<Override> overrides = const [],
  double? textScale,
}) async {
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (router != null) routerProvider.overrideWithValue(router),
        ...overrides,
      ],
      child: const VarysApp(),
    ),
  );
}
