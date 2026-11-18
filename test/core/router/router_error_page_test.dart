// Router error page (unknown path) in the real app root with the real
// router, logged in: fixed Turkish texts only (no 'Page Not Found', no
// error.toString()), BackArrow and the home button land on a single /home
// (go and push), and no overflow at 360px with text scale 1.5.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/main.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

import '../../helpers/varys_app_harness.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 16);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _unknownPath = '/bilinmeyen';

/// Plan from real backend JSON with both focus slots filled.
DailyPlan _planWithFocus() {
  final json =
      jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
          as Map<String, dynamic>;
  final tasks = (json['tasks'] as List)
      .map((t) => Task.fromJson(t as Map<String, dynamic>))
      .toList();
  return DailyPlan(
    planDate: _day,
    mainFocus: Task.fromJson(json['main_focus'] as Map<String, dynamic>),
    sideFocus: tasks[1],
    tasks: tasks,
  );
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => const Right([]));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
    when(() => routineRepo.getRoutines()).thenAnswer((_) async => const Right([]));
  });

  /// Real app root + real router, logged in, on Home.
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(600, 1400),
    double? textScale,
  }) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      textScale: textScale,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
      ],
    );
    await tester.pumpAndSettle();
    router = ProviderScope.containerOf(tester.element(find.byType(VarysApp))).read(routerProvider);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull, reason: 'Home itself drew without errors');
  }

  /// All route matches on the stack (shell matches flattened).
  List<RouteMatch> stackMatches() {
    final matches = <RouteMatch>[];
    void collect(List<RouteMatchBase> list) {
      for (final m in list) {
        if (m is ShellRouteMatch) {
          collect(m.matches);
        } else if (m is RouteMatch) {
          matches.add(m);
        }
      }
    }

    collect(router.routerDelegate.currentConfiguration.matches);
    return matches;
  }

  int homeCount() => stackMatches().where((m) => m.route.path == AppRouter.homePath).length;

  void expectErrorPage(WidgetTester tester) {
    expect(find.text(AppRouter.errorTitle), findsOneWidget);
    expect(find.text(AppRouter.errorMessage), findsOneWidget);
    expect(find.text(AppRouter.errorHomeButton), findsOneWidget);
    expect(find.byType(BackArrow), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    // No English or raw error detail.
    for (final text in ['Page Not Found', 'Unknown error', 'Exception', 'GoException', 'no routes']) {
      expect(find.textContaining(text), findsNothing, reason: text);
    }
    expect(find.textContaining(_unknownPath), findsNothing, reason: 'path is not echoed');
    expect(tester.takeException(), isNull);
  }

  void expectSingleHome(WidgetTester tester) {
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text(AppRouter.errorTitle), findsNothing);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRouter.homePath);
    expect(homeCount(), 1, reason: 'no duplicate /home on the stack');
    expect(stackMatches().whereType<ImperativeRouteMatch>(), isEmpty);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  }

  testWidgets('go unknown path: Turkish error page; home button lands on a single /home', (
    tester,
  ) async {
    await pumpApp(tester);
    router.go(_unknownPath);
    await tester.pumpAndSettle();
    expectErrorPage(tester);

    await tester.tap(find.text(AppRouter.errorHomeButton));
    await tester.pumpAndSettle();
    expectSingleHome(tester);
  });

  testWidgets('go unknown path: BackArrow (nothing to pop) lands on a single /home', (
    tester,
  ) async {
    await pumpApp(tester);
    router.go(_unknownPath);
    await tester.pumpAndSettle();
    expectErrorPage(tester);

    await tester.tap(find.byType(BackArrow));
    await tester.pumpAndSettle();
    expectSingleHome(tester);
  });

  testWidgets('push unknown path from Home: error page, no second /home; back lands on one /home', (
    tester,
  ) async {
    await pumpApp(tester);
    router.push(_unknownPath);
    await tester.pumpAndSettle();
    expectErrorPage(tester);
    expect(homeCount(), lessThanOrEqualTo(1), reason: 'push must not add a second /home');

    await tester.tap(find.byType(BackArrow));
    await tester.pumpAndSettle();
    expectSingleHome(tester);
  });

  testWidgets('push unknown path, then the home button: a single /home', (tester) async {
    await pumpApp(tester);
    router.push(_unknownPath);
    await tester.pumpAndSettle();
    expectErrorPage(tester);

    await tester.tap(find.text(AppRouter.errorHomeButton));
    await tester.pumpAndSettle();
    expectSingleHome(tester);
  });

  for (final scale in [1.0, 1.5]) {
    testWidgets('no overflow at 360x640, text scale $scale; home button reachable', (
      tester,
    ) async {
      // Both focus slots filled (real backend JSON): the empty focus
      // placeholder on Home overflows at 360px (known, outside this test).
      when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(_planWithFocus()));
      await pumpApp(tester, size: const Size(360, 640), textScale: scale);
      router.go(_unknownPath);
      await tester.pumpAndSettle();
      expectErrorPage(tester);

      final button = find.text(AppRouter.errorHomeButton);
      final rect = tester.getRect(button);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(rect.bottom, lessThanOrEqualTo(640));
      await tester.tap(button);
      await tester.pumpAndSettle();
      expectSingleHome(tester);
    });
  }
}
