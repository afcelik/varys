// /tasks/edit on the real app router and shell: the edit form needs a Task as
// extra. Without it (none, String, Map, int) an error page is shown, built in
// pageBuilder (no redirect: a redirect on push adds a second /home). Opened
// from a Planning row it is pushed outside the shell; BackArrow returns to
// Planning. It is not a menu destination.

import 'dart:async';
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
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/planning/presentation/task_list_page.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

import '../../features/projects/fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 19);

/// Real PATCH /tasks 200 body: id 1, project 2, due 25.11, planned 19.11.
final _task = Task.fromJson(
  jsonDecode(File('test/fixtures/task_update_set.json').readAsStringSync()) as Map<String, dynamic>,
);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
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
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([_task]));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => const Right([]));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
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
          projectRepositoryProvider.overrideWith((ref) async => FakeProjectRepository()),
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
  String currentPath() => router.routerDelegate.currentConfiguration.uri.path;

  for (final (name, extra) in <(String, Object?)>[
    ('no extra', null),
    ('a String', 'görev'),
    ('a Map', <String, dynamic>{'id': 1, 'title': 'Görev'}),
    ('an int', 1),
  ]) {
    testWidgets('push /tasks/edit with $name: error page over a single Home; BackArrow returns', (
      tester,
    ) async {
      await pumpApp(tester);
      unawaited(router.push(AppRouter.tasksEditPath, extra: extra));
      await tester.pumpAndSettle();

      expect(find.text(TaskEditUnavailablePage.message), findsOneWidget);
      expect(find.byType(TaskEditScreen), findsNothing, reason: 'no silent fallback to create');
      expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');
      expect(homeCount(), 1, reason: 'no redirect, no second /home');
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed.single.route.path, AppRouter.tasksEditPath);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(currentPath(), AppRouter.homePath);
      expect(homeCount(), 1);
      expect(router.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('go /tasks/edit (deep link, no extra): error page; BackArrow falls back to /home', (
    tester,
  ) async {
    await pumpApp(tester);
    router.go(AppRouter.tasksEditPath);
    await tester.pumpAndSettle();
    expect(find.text(TaskEditUnavailablePage.message), findsOneWidget);
    expect(router.canPop(), isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(currentPath(), AppRouter.homePath);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(homeCount(), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('push with a Task: the edit form opens with its fields filled', (tester) async {
    await pumpApp(tester);
    unawaited(router.push(AppRouter.tasksEditPath, extra: _task));
    await tester.pumpAndSettle();

    final screen = tester.widget<TaskEditScreen>(find.byType(TaskEditScreen));
    expect(screen.task, _task);
    expect(find.text(TaskEditScreen.editTitle), findsOneWidget);
    expect(find.text('Giriş ekranını bitir ve test et'), findsOneWidget);
    expect(find.text('Form ve hata mesajları'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('task-due-date-text'))).data,
      '25.11.2026',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('task-planned-date-text'))).data,
      '19.11.2026',
    );
    expect(find.byType(NavigationBar), findsNothing);
    expect(homeCount(), 1);
  });

  testWidgets('Planning row tap pushes the form; BackArrow returns to Planning with the menu', (
    tester,
  ) async {
    await pumpApp(tester);
    router.go(AppRouter.planningPath);
    await tester.pumpAndSettle();
    expect(find.byType(TaskListPage), findsOneWidget);

    await tester.tap(find.text('Giriş ekranını bitir ve test et'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditScreen), findsOneWidget);
    expect(find.text(TaskEditScreen.editTitle), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
    expect(pushed.single.route.path, AppRouter.tasksEditPath, reason: 'pushed, not go');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditScreen), findsNothing);
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(currentPath(), AppRouter.planningPath);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('/tasks/edit is not a menu destination: still exactly 3 tabs', (tester) async {
    await pumpApp(tester);

    expect(NavigationDestinations.shellDestinations.map((d) => d.routePath), [
      AppRouter.homePath,
      AppRouter.planningPath,
      AppRouter.varysChatPath,
    ]);
    expect(
      NavigationDestinations.shellDestinations.map((d) => d.routePath),
      isNot(contains(AppRouter.tasksEditPath)),
    );
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations, hasLength(3));
  });
}
