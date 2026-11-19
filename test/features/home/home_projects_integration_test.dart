// Home + ProjectsCard integration: the real app root and router (real
// MainScaffold, real HomeScreen, real notifiers); only the repositories are
// fakes returning real Either values. Data is real backend JSON
// (test/fixtures/: daily_plan_with_tasks, routines_day, projects_list,
// projects_limits).

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/daily_tasks_card.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/home/presentation/widgets/projects_card.dart';
import 'package:varys/features/home/presentation/widgets/routines_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/projects/presentation/projects_screen.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

import '../../helpers/varys_app_harness.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

final _day = DateTime(2026, 11, 1);
const _serverError =
    ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late _MockProjectRepository projectRepo;
  late DailyPlan plan;
  late List<RoutineDayItem> routines;
  late List<Project> active;
  late ProjectLimits limits;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(ProjectStatus.active);
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    projectRepo = _MockProjectRepository();

    final planJson = _read('daily_plan_with_tasks.json') as Map<String, dynamic>;
    final tasks =
        (planJson['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();
    plan = DailyPlan(planDate: _day, mainFocus: tasks.first, tasks: tasks);
    routines = (_read('routines_day.json') as List)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();
    active = (_read('projects_list.json') as List)
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .where((p) => p.status == ProjectStatus.active)
        .toList();
    limits = ProjectLimits.fromJson(_read('projects_limits.json') as Map<String, dynamic>);

    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(plan.tasks));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(routines));
    when(() => routineRepo.markDone(any(), any())).thenAnswer((_) async => const Right(null));
    when(() => projectRepo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => Right(active));
    when(() => projectRepo.getLimits()).thenAnswer((_) async => Right(limits));
  });

  List<Override> overrides() => [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ];

  /// Real app (real routerProvider) logged in on Home.
  Future<void> pumpApp(WidgetTester tester, {double width = 790}) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(tester, overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  Finder inProjects(Finder f) => find.descendant(of: find.byType(ProjectsCard), matching: f);
  Finder inRoutines(Finder f) => find.descendant(of: find.byType(RoutinesCard), matching: f);

  testWidgets('projects card sits after the routines card and before "Diğer Kategoriler"',
      (tester) async {
    await pumpApp(tester);

    final routinesTop = tester.getTopLeft(find.byType(RoutinesCard)).dy;
    final projectsTop = tester.getTopLeft(find.byType(ProjectsCard)).dy;
    final othersTop = tester.getTopLeft(find.text('Diğer Kategoriler')).dy;
    expect(projectsTop, greaterThan(routinesTop));
    expect(othersTop, greaterThan(projectsTop));
    expect(inProjects(find.text('Aktif 2/3')), findsOneWidget);
    expect(inProjects(find.text('Ev taşıma')), findsOneWidget);
  });

  testWidgets('wide layout: projects card in the right column, below the routines card',
      (tester) async {
    await pumpApp(tester, width: 1400);

    final routines = tester.getRect(find.byType(RoutinesCard));
    final projects = tester.getRect(find.byType(ProjectsCard));
    expect(projects.left, routines.left);
    expect(projects.top, greaterThan(routines.bottom));
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  testWidgets('project error stays in its card: focus, tasks and routines keep working',
      (tester) async {
    when(() => projectRepo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => const Left(_serverError));
    await pumpApp(tester);

    expect(inProjects(find.text(userMessage(_serverError))), findsOneWidget);
    expect(inProjects(find.text(ProjectsCard.retryText)), findsOneWidget);
    expect(find.textContaining('Instance of'), findsNothing);

    // Main focus and daily tasks are drawn.
    final focusTitle = plan.mainFocus!.title;
    expect(
      find.descendant(of: find.byType(MainFocusCard), matching: find.text(focusTitle)),
      findsOneWidget,
    );
    for (final t in plan.tasks) {
      expect(
        find.descendant(of: find.byType(DailyTasksCard), matching: find.text(t.title)),
        findsOneWidget,
        reason: t.title,
      );
    }

    // A routine can still be ticked (the server then reports it completed).
    final open = routines.firstWhere((r) => !r.completed);
    when(() => routineRepo.markDone(any(), any())).thenAnswer((_) async {
      when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right([
            for (final r in routines) r.id == open.id ? r.copyWith(completed: true) : r,
          ]));
      return const Right(null);
    });
    final checkbox = find.descendant(
      of: find.ancestor(of: inRoutines(find.text(open.title)), matching: find.byType(ListTile)),
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    verify(() => routineRepo.markDone(open.id, _day)).called(1);
    expect(tester.widget<Checkbox>(checkbox).value, isTrue);
  });

  testWidgets('"Tekrar dene" reloads only the projects card', (tester) async {
    when(() => projectRepo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => const Left(_serverError));
    await pumpApp(tester);
    clearInteractions(planRepo);
    clearInteractions(routineRepo);
    clearInteractions(taskRepo);
    clearInteractions(projectRepo);

    when(() => projectRepo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => Right(active));
    final retry = inProjects(find.text(ProjectsCard.retryText));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(inProjects(find.text('Aktif 2/3')), findsOneWidget);
    expect(inProjects(find.text(userMessage(_serverError))), findsNothing);
    verify(() => projectRepo.getProjects(status: ProjectStatus.active)).called(1);
    verify(() => projectRepo.getLimits()).called(1);
    verifyNever(() => planRepo.getPlan(any()));
    verifyNever(() => routineRepo.getRoutinesForDay(any()));
    verifyNever(() => taskRepo.getTasksByFilter(any()));
  });

  testWidgets('"Daha fazla" opens /projects outside the shell; back arrow returns to Home',
      (tester) async {
    await pumpApp(tester);

    final more = inProjects(find.text(ProjectsCard.moreText));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(find.byType(ProjectsScreen), findsOneWidget);
    expect(find.text(ProjectsScreen.title), findsOneWidget);
    expect(find.byKey(const ValueKey('projects-section-active')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(HomeScreen), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectsScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(ProjectsCard), findsOneWidget);
  });

  for (final width in [790.0, 1400.0]) {
    testWidgets('menu still has exactly 3 tabs and no "Projeler" (width ${width.toInt()}px)',
        (tester) async {
      await pumpApp(tester, width: width);

      if (width > 800) {
        final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
        expect(rail.destinations, hasLength(3));
        expect(
          find.descendant(of: find.byType(NavigationRail), matching: find.text('Projeler')),
          findsNothing,
        );
      } else {
        final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(bar.destinations, hasLength(3));
        expect(
          find.descendant(of: find.byType(NavigationBar), matching: find.text('Projeler')),
          findsNothing,
        );
      }
      expect(find.text('Projeler'), findsNothing);
    });
  }
}
