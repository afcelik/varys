// /tasks/new on the real app router and shell: the task create form opens
// without any extra, outside the shell (no menu), with no redirect (a
// redirect on push adds a second /home). BackArrow pops, or goes to
// Planning when there is nothing to pop. It is not a menu destination.

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
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/planning/presentation/task_new_args.dart';
import 'package:varys/features/planning/presentation/task_list_page.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

import '../../features/projects/fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 19);

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
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
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

  testWidgets('push /tasks/new (no extra): create form outside the shell over a single Home; '
      'BackArrow returns to it', (tester) async {
    await pumpApp(tester);
    router.push(AppRouter.tasksNewPath);
    await tester.pumpAndSettle();

    expect(find.byType(TaskEditScreen), findsOneWidget);
    expect(tester.widget<TaskEditScreen>(find.byType(TaskEditScreen)).task, isNull);
    expect(find.text(TaskEditScreen.createTitle), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');
    expect(homeCount(), 1, reason: 'no redirect, no second /home');
    final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
    expect(pushed, hasLength(1));
    expect(pushed.single.route.path, AppRouter.tasksNewPath);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(currentPath(), AppRouter.homePath);
    expect(homeCount(), 1);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Planning "Yeni Görev" pushes the form; BackArrow returns to Planning with the menu',
    (tester) async {
      await pumpApp(tester);
      router.go(AppRouter.planningPath);
      await tester.pumpAndSettle();
      expect(find.byType(TaskListPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.tap(find.text('Yeni Görev'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing, reason: 'the old dialog is gone');
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed.single.route.path, AppRouter.tasksNewPath, reason: 'pushed, not go');

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.byType(TaskListPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(currentPath(), AppRouter.planningPath);
      expect(stackMatches().whereType<ImperativeRouteMatch>(), isEmpty, reason: 'form popped');
      expect(router.canPop(), isFalse);
    },
  );

  testWidgets('go /tasks/new (deep link, no extra): the form opens, nothing to pop; BackArrow '
      'falls back to Planning', (tester) async {
    await pumpApp(tester);
    router.go(AppRouter.tasksNewPath);
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditScreen), findsOneWidget);
    expect(router.canPop(), isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditScreen), findsNothing);
    expect(currentPath(), AppRouter.planningPath);
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('/tasks/new is not a menu destination: still exactly 3 tabs', (tester) async {
    await pumpApp(tester);

    expect(NavigationDestinations.shellDestinations.map((d) => d.routePath), [
      AppRouter.homePath,
      AppRouter.planningPath,
      AppRouter.varysChatPath,
    ]);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations, hasLength(3));
  });

  group('extra', () {
    testWidgets('TaskNewArgs: create form with that project chosen, over a single Home; '
        'BackArrow returns to it', (tester) async {
      await pumpApp(tester);
      router.push(AppRouter.tasksNewPath, extra: const TaskNewArgs(projectId: 1));
      await tester.pumpAndSettle();

      final form = tester.widget<TaskEditScreen>(find.byType(TaskEditScreen));
      expect(form.task, isNull);
      expect(form.initialProjectId, 1);
      expect(find.text(TaskEditScreen.createTitle), findsOneWidget);
      expect(
        tester
            .widget<DropdownMenu<ProjectChoice>>(find.byType(DropdownMenu<ProjectChoice>))
            .initialSelection
            ?.id,
        1,
      );
      expect(find.text(TaskEditUnavailablePage.message), findsNothing);
      expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');
      expect(homeCount(), 1, reason: 'no redirect, no second /home');
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed.single.route.path, AppRouter.tasksNewPath);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(homeCount(), 1);
      expect(router.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no extra: form starts with no initial project (as before)', (tester) async {
      await pumpApp(tester);
      router.push(AppRouter.tasksNewPath);
      await tester.pumpAndSettle();
      expect(tester.widget<TaskEditScreen>(find.byType(TaskEditScreen)).initialProjectId, isNull);
    });

    for (final (name, extra) in <(String, Object)>[
      ('String', '1'),
      ('Map', {'projectId': 1}),
      ('int', 1),
    ]) {
      testWidgets('wrong extra ($name): error page, no form, a single Home; BackArrow returns', (
        tester,
      ) async {
        await pumpApp(tester);
        router.push(AppRouter.tasksNewPath, extra: extra);
        await tester.pumpAndSettle();

        expect(find.text(TaskEditUnavailablePage.message), findsOneWidget);
        expect(find.byType(TaskEditScreen), findsNothing);
        expect(find.byType(NavigationBar), findsNothing);
        expect(homeCount(), 1, reason: 'no redirect, no second /home');
        final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
        expect(pushed.single.route.path, AppRouter.tasksNewPath);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(homeCount(), 1);
        expect(router.canPop(), isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
