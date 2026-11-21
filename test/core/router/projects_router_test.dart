// Project routes on the real app router and shell:
// - /projects/new opens the create form (no extra needed).
// - /projects/edit needs a Project as `extra`; anything else (none, String,
//   int, a Map that looks like a project) shows an error page and never the
//   form (no silent fallback). Not a redirect: a redirect on push adds a
//   second /home.

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
import 'package:varys/features/home/presentation/widgets/projects_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/presentation/project_detail_screen.dart';
import 'package:varys/features/projects/presentation/project_edit_screen.dart';
import 'package:varys/features/projects/presentation/projects_screen.dart';
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
  late FakeProjectRepository projectRepo;
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
    projectRepo = FakeProjectRepository();
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
          projectRepositoryProvider.overrideWith((ref) async => projectRepo),
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
    expect(find.byType(ProjectEditScreen), findsNothing);
    expect(find.byType(ProjectEditUnavailablePage), findsNothing);
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
    'extra project JSON (Map)': {'id': 1, 'title': 'Ev taşıma', 'status': 'active'},
  }.entries) {
    testWidgets('push /projects/edit with ${entry.key}: error page (no form) over a single '
        'Home; BackArrow returns to it', (tester) async {
      await pumpApp(tester);
      router.push(AppRouter.projectsEditPath, extra: entry.value);
      await tester.pumpAndSettle();

      expect(find.byType(ProjectEditUnavailablePage), findsOneWidget);
      expect(find.text(ProjectEditUnavailablePage.message), findsOneWidget);
      expect(find.byType(ProjectEditScreen), findsNothing, reason: 'no fallback to a form');
      expect(find.byType(NavigationBar), findsNothing);
      expect(homeCount(), 1);
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed, hasLength(1));
      expect(pushed.single.route.path, AppRouter.projectsEditPath);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await expectOnlyHome(tester);
    });
  }

  testWidgets('go /projects/edit (deep link) without extra: error page, no form; BackArrow '
      'lands on a single Home', (tester) async {
    await pumpApp(tester);
    router.go(AppRouter.projectsEditPath);
    await tester.pumpAndSettle();
    expect(find.byType(ProjectEditUnavailablePage), findsOneWidget);
    expect(find.byType(ProjectEditScreen), findsNothing);
    expect(router.canPop(), isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  testWidgets('push /projects/new (no extra): create form outside the shell; BackArrow '
      'returns to a single Home', (tester) async {
    await pumpApp(tester);
    router.push(AppRouter.projectsNewPath);
    await tester.pumpAndSettle();

    expect(find.byType(ProjectEditScreen), findsOneWidget);
    expect(tester.widget<ProjectEditScreen>(find.byType(ProjectEditScreen)).project, isNull);
    expect(find.text(ProjectEditScreen.createTitle), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(homeCount(), 1);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  testWidgets('push /projects/edit with a Project: edit form for it; back returns Home', (
    tester,
  ) async {
    await pumpApp(tester);
    final project = projectsFixture()[2];
    router.push(AppRouter.projectsEditPath, extra: project);
    await tester.pumpAndSettle();

    expect(tester.widget<ProjectEditScreen>(find.byType(ProjectEditScreen)).project, project);
    expect(find.text(ProjectEditScreen.editTitle), findsOneWidget);
    expect(find.byType(ProjectEditUnavailablePage), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  testWidgets('Home card -> /projects -> row -> detail -> Düzenle -> add; BackArrow steps back '
      'one page at a time', (tester) async {
    await pumpApp(tester);
    final more = find.descendant(
      of: find.byType(ProjectsCard),
      matching: find.text(ProjectsCard.moreText),
    );
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.byType(ProjectsScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('project-title-1')));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    expect(tester.widget<ProjectDetailScreen>(find.byType(ProjectDetailScreen)).initial.id, 1);

    await tester.tap(find.byKey(const ValueKey('project-detail-edit')));
    await tester.pumpAndSettle();
    expect(find.text(ProjectEditScreen.editTitle), findsOneWidget);
    expect(tester.widget<ProjectEditScreen>(find.byType(ProjectEditScreen)).project!.id, 1);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    expect(find.byType(ProjectEditScreen), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectsScreen), findsOneWidget);
    expect(find.byType(ProjectDetailScreen), findsNothing);

    await tester.tap(find.byKey(const ValueKey('projects-add')));
    await tester.pumpAndSettle();
    expect(find.text(ProjectEditScreen.createTitle), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(ProjectsScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  test('project routes are not menu destinations', () {
    final paths = NavigationDestinations.shellDestinations.map((d) => d.routePath).toList();
    expect(paths, [AppRouter.homePath, AppRouter.planningPath, AppRouter.varysChatPath]);
    for (final p in [
      AppRouter.projectsPath,
      AppRouter.projectsNewPath,
      AppRouter.projectsEditPath,
      AppRouter.projectDetailPath,
    ]) {
      expect(paths, isNot(contains(p)));
    }
    expect(AppRouter.projectsNewPath, '/projects/new');
    expect(AppRouter.projectsEditPath, '/projects/edit');
    expect(AppRouter.projectDetailPath, '/projects/detail');
  });
}
