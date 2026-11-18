// Routine form routes on the real app router and shell:
// - /routines/new opens the create form (no extra needed).
// - /routines/edit needs a Routine as `extra`; anything else (none, String,
//   int) shows an error page and never the create form (no silent
//   fallback). Not a redirect: a redirect on push adds a second /home.

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
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routine_edit_screen.dart';
import 'package:varys/features/routines/presentation/routines_screen.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

List<Routine> _routines() =>
    (jsonDecode(File('test/fixtures/routines_list.json').readAsStringSync()) as List<dynamic>)
        .map((e) => Routine.fromJson(e as Map<String, dynamic>))
        .toList();

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
    when(() => routineRepo.getRoutines()).thenAnswer((_) async => Right(_routines()));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
          taskRepositoryProvider.overrideWith((ref) async => taskRepo),
          routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(router.canPop(), isFalse);
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

  Future<void> expectOnlyHome(WidgetTester tester) async {
    expect(find.byType(RoutineEditScreen), findsNothing);
    expect(find.byType(RoutineEditUnavailablePage), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRouter.homePath);
    expect(homeCount(), 1, reason: 'no duplicate /home on the stack');
    expect(stackMatches().whereType<ImperativeRouteMatch>(), isEmpty);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  }

  for (final entry in <String, Object?>{
    'no extra': null,
    "extra 'x' (String)": 'x',
    'extra 2 (int)': 2,
  }.entries) {
    testWidgets('push /routines/edit with ${entry.key}: error page (no create form) over a '
        'single /home; BackArrow returns to a single /home', (tester) async {
      await pumpApp(tester);
      router.push(AppRouter.routinesEditPath, extra: entry.value);
      await tester.pumpAndSettle();

      expect(find.byType(RoutineEditUnavailablePage), findsOneWidget);
      expect(find.text('Bu sayfa doğrudan açılamaz.'), findsOneWidget);
      expect(find.byType(RoutineEditScreen), findsNothing, reason: 'no silent create form');
      expect(find.text(RoutineEditScreen.saveText), findsNothing);
      expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');

      expect(homeCount(), 1, reason: 'no duplicate /home on the stack');
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed, hasLength(1));
      expect(pushed.single.route.path, AppRouter.routinesEditPath);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await expectOnlyHome(tester);
    });
  }

  testWidgets('go /routines/edit (deep link) without extra: error page; BackArrow lands on '
      'a single Home', (tester) async {
    await pumpApp(tester);
    router.go(AppRouter.routinesEditPath);
    await tester.pumpAndSettle();
    expect(find.byType(RoutineEditUnavailablePage), findsOneWidget);
    expect(find.byType(RoutineEditScreen), findsNothing);
    expect(router.canPop(), isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  testWidgets('push /routines/new (no extra): create form, outside the shell; BackArrow '
      'returns to a single Home', (tester) async {
    await pumpApp(tester);
    router.push(AppRouter.routinesNewPath);
    await tester.pumpAndSettle();

    expect(find.byType(RoutineEditScreen), findsOneWidget);
    expect(tester.widget<RoutineEditScreen>(find.byType(RoutineEditScreen)).routine, isNull);
    expect(find.text(RoutineEditScreen.createTitle), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(homeCount(), 1);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  testWidgets('push /routines/edit with a Routine: edit form for it; back returns Home', (
    tester,
  ) async {
    await pumpApp(tester);
    final routine = _routines()[1];
    router.push(AppRouter.routinesEditPath, extra: routine);
    await tester.pumpAndSettle();

    expect(tester.widget<RoutineEditScreen>(find.byType(RoutineEditScreen)).routine, routine);
    expect(find.text(RoutineEditScreen.editTitle), findsOneWidget);
    expect(find.byType(RoutineEditUnavailablePage), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  testWidgets('Home -> /routines -> row -> edit form; BackArrow steps back one page at a time', (
    tester,
  ) async {
    await pumpApp(tester);
    router.push(AppRouter.routinesPath);
    await tester.pumpAndSettle();
    expect(find.byType(RoutinesScreen), findsOneWidget);

    await tester.tap(find.text('Spor'));
    await tester.pumpAndSettle();
    expect(find.text(RoutineEditScreen.editTitle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(RoutinesScreen), findsOneWidget);
    expect(find.byType(RoutineEditScreen), findsNothing);

    await tester.tap(find.byKey(const ValueKey('routines-add')));
    await tester.pumpAndSettle();
    expect(find.text(RoutineEditScreen.createTitle), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(RoutinesScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  test('form routes are not menu destinations', () {
    final paths = NavigationDestinations.shellDestinations.map((d) => d.routePath).toList();
    expect(paths, [AppRouter.homePath, AppRouter.planningPath, AppRouter.varysChatPath]);
    expect(paths, isNot(contains(AppRouter.routinesNewPath)));
    expect(paths, isNot(contains(AppRouter.routinesEditPath)));
  });
}
