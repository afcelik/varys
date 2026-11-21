// /projects/detail on the real app router and shell: the project detail page
// opens only with a Project extra, outside the shell (no menu), with no
// redirect (a redirect on push adds a second /home). Any other extra (none,
// String, Map, int) shows the error page. BackArrow pops, or goes to Home
// when there is nothing to pop. It is not a menu destination.

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

  Future<void> expectBackToSingleHome(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ProjectDetailScreen), findsNothing);
    expect(find.text(ProjectDetailUnavailablePage.message), findsNothing);
    expect(homeCount(), 1);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  }

  testWidgets('push with a Project: detail page outside the shell over a single Home; '
      'BackArrow returns to it', (tester) async {
    await pumpApp(tester);
    final project = projectsFixture().first;
    router.push(AppRouter.projectDetailPath, extra: project);
    await tester.pumpAndSettle();

    final page = tester.widget<ProjectDetailScreen>(find.byType(ProjectDetailScreen));
    expect(page.initial, project);
    expect(find.text('Ev taşıma'), findsWidgets);
    expect(find.text(ProjectDetailUnavailablePage.message), findsNothing);
    expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');
    expect(homeCount(), 1, reason: 'no redirect, no second /home');
    final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
    expect(pushed.single.route.path, AppRouter.projectDetailPath);

    await expectBackToSingleHome(tester);
  });

  testWidgets('Home "Aktif Projeler" row -> detail of that project; BackArrow returns', (
    tester,
  ) async {
    await pumpApp(tester);
    final rowTitle = find.descendant(
      of: find.byType(ProjectsCard),
      matching: find.text('Kitap okuma listesi'),
    );
    await tester.ensureVisible(rowTitle);
    await tester.tap(rowTitle);
    await tester.pumpAndSettle();

    expect(tester.widget<ProjectDetailScreen>(find.byType(ProjectDetailScreen)).initial.id, 2);
    expect(homeCount(), 1);
    await expectBackToSingleHome(tester);
  });

  for (final (name, extra) in <(String, Object?)>[
    ('none', null),
    ('String', 'Ev taşıma'),
    ('Map', {'id': 1, 'title': 'Ev taşıma'}),
    ('int', 1),
  ]) {
    testWidgets('push with extra $name: error page, no detail, a single Home; BackArrow returns', (
      tester,
    ) async {
      await pumpApp(tester);
      router.push(AppRouter.projectDetailPath, extra: extra);
      await tester.pumpAndSettle();

      expect(find.text(ProjectDetailUnavailablePage.message), findsOneWidget);
      expect(find.byType(ProjectDetailScreen), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(homeCount(), 1, reason: 'no redirect, no second /home');
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed.single.route.path, AppRouter.projectDetailPath);

      await expectBackToSingleHome(tester);
    });
  }

  testWidgets('go /projects/detail (deep link, no extra): error page, nothing to pop; '
      'BackArrow falls back to Home', (tester) async {
    await pumpApp(tester);
    router.go(AppRouter.projectDetailPath);
    await tester.pumpAndSettle();
    expect(find.text(ProjectDetailUnavailablePage.message), findsOneWidget);
    expect(router.canPop(), isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRouter.homePath);
    expect(tester.takeException(), isNull);
  });

  testWidgets('/projects/detail is not a menu destination: still exactly 3 tabs', (tester) async {
    await pumpApp(tester);
    final paths = NavigationDestinations.shellDestinations.map((d) => d.routePath).toList();
    expect(paths, [AppRouter.homePath, AppRouter.planningPath, AppRouter.varysChatPath]);
    expect(paths, isNot(contains(AppRouter.projectDetailPath)));
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations, hasLength(3));
  });
}
