// End-to-end inside the app: real app router, real HomeScreen, real
// notifiers (projectsListProvider, activeProjectsProvider, daily plan,
// tasks, routines). Only the repositories are fake: projects come from the
// shared in-memory FakeProjectRepository (server-like limit rule), the
// other Home data from mocks returning real fixture JSON.
//
// Each project change made on /projects must show up in the Home "Aktif
// Projeler" card (titles and the Aktif N/M counter) and must not reload or
// change the other Home cards (focus, daily tasks, routines).

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
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
import 'package:varys/features/projects/presentation/project_edit_screen.dart';
import 'package:varys/features/projects/presentation/projects_screen.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

import '../../helpers/varys_app_harness.dart';
import 'fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late FakeProjectRepository projectRepo;
  late DailyPlan plan;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    projectRepo = FakeProjectRepository();

    final planJson = _read('daily_plan_with_tasks.json') as Map<String, dynamic>;
    final tasks =
        (planJson['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();
    plan = DailyPlan(planDate: _day, mainFocus: tasks.first, tasks: tasks);
    final routines = (_read('routines_day.json') as List)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();

    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(plan.tasks));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => Right(plan.tasks));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(routines));
  });

  Finder inCard(Finder f) => find.descendant(of: find.byType(ProjectsCard), matching: f);
  final saveButton = find.byKey(const ValueKey('project-save'));
  final titleField = find.byKey(const ValueKey('project-title'));

  /// Real app (real routerProvider) logged in on Home. Interactions with the
  /// other Home repositories are cleared after the first load.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(790, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(inCard(find.text('Aktif 2/3')), findsOneWidget);
    expect(inCard(find.text('Ev taşıma')), findsOneWidget);
    expect(inCard(find.text('Kitap okuma listesi')), findsOneWidget);
    clearInteractions(planRepo);
    clearInteractions(taskRepo);
    clearInteractions(routineRepo);
  }

  /// Home card "Daha fazla" -> /projects.
  Future<void> openProjectsPage(WidgetTester tester) async {
    final more = inCard(find.text(ProjectsCard.moreText));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.byType(ProjectsScreen), findsOneWidget);
  }

  Future<void> backToHome(WidgetTester tester) async {
    while (find.byType(HomeScreen).hitTestable().evaluate().isEmpty) {
      await tester.tap(find.byIcon(Icons.arrow_back).last);
      await tester.pumpAndSettle();
    }
    expect(find.byType(ProjectsScreen), findsNothing);
  }

  Future<void> saveForm(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  Future<void> rowMenu(WidgetTester tester, int id, String actionKey) async {
    final menu = find.byKey(ValueKey('project-menu-$id'));
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('project-action-$actionKey')));
    await tester.pumpAndSettle();
  }

  /// The other Home cards still show their data and were not reloaded.
  void expectOtherCardsUntouched() {
    expect(find.descendant(of: find.byType(MainFocusCard), matching: find.text(plan.mainFocus!.title)),
        findsOneWidget);
    expect(find.descendant(of: find.byType(DailyTasksCard), matching: find.text(plan.tasks[1].title)),
        findsOneWidget);
    expect(find.descendant(of: find.byType(RoutinesCard), matching: find.text('Su iç')),
        findsOneWidget);
    verifyNever(() => planRepo.getPlan(any()));
    verifyNever(() => taskRepo.getTasksByFilter(any()));
    verifyNever(() => routineRepo.getRoutinesForDay(any()));
  }

  testWidgets('create an active project on /projects: it appears on the Home card and the '
      'counter goes 2/3 -> 3/3', (tester) async {
    await pumpApp(tester);
    await openProjectsPage(tester);

    await tester.tap(find.byKey(const ValueKey('projects-add')));
    await tester.pumpAndSettle();
    await tester.enterText(titleField, 'Bahçe düzenleme');
    await tester.pumpAndSettle();
    await saveForm(tester);

    expect(find.byType(ProjectsScreen), findsOneWidget, reason: 'form popped back to the list');
    expect(find.text('Aktif 3/3'), findsOneWidget);
    expect(projectRepo.createBodies.single['status'], 'active');

    await backToHome(tester);
    expect(inCard(find.text('Bahçe düzenleme')), findsOneWidget);
    expect(inCard(find.text('Aktif 3/3')), findsOneWidget);
    expectOtherCardsUntouched();
  });

  testWidgets('limit filled meanwhile: creating an active project shows the limit message and '
      'keeps the form; choosing Beklemede then saves; card shows the server state',
      (tester) async {
    await pumpApp(tester);
    await openProjectsPage(tester);
    await tester.tap(find.byKey(const ValueKey('projects-add')));
    await tester.pumpAndSettle();
    await tester.enterText(titleField, 'Fazla proje');
    await tester.pumpAndSettle();

    // Another client activates project 3: the server is now full.
    projectRepo.server = [
      for (final p in projectRepo.server)
        p.id == 3 ? p.copyWith(status: ProjectStatus.active) : p,
    ];
    await saveForm(tester);

    expect(find.byType(ProjectEditScreen), findsOneWidget, reason: 'form stays open');
    expect(find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(ActiveProjectLimitFailure.message)), findsOneWidget);
    expect(find.text('Fazla proje'), findsOneWidget, reason: 'title kept');
    expect(projectRepo.server.where((p) => p.title == 'Fazla proje'), isEmpty);

    // "Aktif" is no longer allowed; pick Beklemede and save.
    await tester.tap(find.byType(DropdownMenu<ProjectStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Beklemede').last);
    await tester.pumpAndSettle();
    await saveForm(tester);
    expect(find.byType(ProjectEditScreen), findsNothing);
    expect(projectRepo.createBodies.last['status'], 'on_hold');

    await backToHome(tester);
    expect(inCard(find.text('Aktif 3/3')), findsOneWidget);
    expect(inCard(find.text('Fazla proje')), findsNothing, reason: 'created on hold');
    expectOtherCardsUntouched();
  });

  testWidgets('"Beklemeye al" on /projects: project leaves the Home card, counter drops',
      (tester) async {
    await pumpApp(tester);
    await openProjectsPage(tester);
    await rowMenu(tester, 1, 'hold');
    expect(find.text('Aktif 1/3'), findsOneWidget);

    await backToHome(tester);
    expect(inCard(find.text('Ev taşıma')), findsNothing);
    expect(inCard(find.text('Kitap okuma listesi')), findsOneWidget);
    expect(inCard(find.text('Aktif 1/3')), findsOneWidget);
    expectOtherCardsUntouched();
  });

  testWidgets('delete on /projects: project leaves the Home card, counter drops',
      (tester) async {
    await pumpApp(tester);
    await openProjectsPage(tester);
    await rowMenu(tester, 2, 'delete');
    await tester.tap(find.byKey(const ValueKey('project-delete-confirm')));
    await tester.pumpAndSettle();
    expect(projectRepo.deleteIds, [2]);
    expect(find.byKey(const ValueKey('project-row-2')), findsNothing);

    await backToHome(tester);
    expect(inCard(find.text('Kitap okuma listesi')), findsNothing);
    expect(inCard(find.text('Ev taşıma')), findsOneWidget);
    expect(inCard(find.text('Aktif 1/3')), findsOneWidget);
    expectOtherCardsUntouched();
  });
}
