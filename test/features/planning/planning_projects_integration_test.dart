// Planning task form + Home "Aktif Projeler" integration: the real app root
// and router (real MainScaffold, HomeScreen, TaskListPage, TaskEditScreen and
// real notifiers). Only the repositories are fakes, and they behave like the
// server: creating a task adds it to the task list and bumps its project's
// task counts. Data is real backend JSON (test/fixtures/).

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
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/daily_plan_state_widgets.dart';
import 'package:varys/features/home/presentation/widgets/daily_tasks_card.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/home/presentation/widgets/projects_card.dart';
import 'package:varys/features/home/presentation/widgets/routines_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/planning/presentation/task_list_page.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

import '../../helpers/varys_app_harness.dart';
import '../projects/fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// Task server stand-in: the list grows on create (shape from the real
/// POST /tasks 201 body), and a linked project gets one more task.
class _FakeTaskServer implements TaskRepository {
  _FakeTaskServer(this.tasks, this.onProjectTask);

  List<Task> tasks;
  final void Function(int projectId) onProjectTask;
  int listCalls = 0;
  int createCalls = 0;
  int _nextId = 100;

  @override
  Future<Either<Failure, List<Task>>> getTasks() async => Right(List.of(tasks));

  @override
  Future<Either<Failure, List<Task>>> getTasksByFilter(TaskFilter filter) async {
    listCalls++;
    return Right(switch (filter) {
      TaskFilter.all => List.of(tasks),
      TaskFilter.inProgress => tasks.where((t) => t.status != TaskStatus.done).toList(),
      TaskFilter.completed => tasks.where((t) => t.status == TaskStatus.done).toList(),
    });
  }

  @override
  Future<Either<Failure, Task>> createTask(Task task) async {
    createCalls++;
    final json = Map<String, dynamic>.from(_read('task_created_with_project.json') as Map)
      ..['id'] = _nextId++
      ..['title'] = task.title
      ..['description'] = task.description
      ..['due_date'] = task.dueDate == null ? null : plannedDateForApi(task.dueDate!)
      ..['planned_date'] = null
      ..['project_id'] = task.projectId;
    final created = Task.fromJson(json);
    tasks = [created, ...tasks];
    if (created.projectId != null) onProjectTask(created.projectId!);
    return Right(created);
  }

  @override
  Future<Either<Failure, Task>> updateTask(
    int id, {
    String? title,
    PlanField<String> description = const PlanField.unset(),
    TaskStatus? status,
    PlanField<DateTime> plannedDate = const PlanField.unset(),
    PlanField<DateTime> dueDate = const PlanField.unset(),
    PlanField<int> projectId = const PlanField.unset(),
    bool? isImportant,
    bool? isUrgent,
  }) => throw UnimplementedError('not used by this flow');

  @override
  Future<Either<Failure, void>> deleteTask(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Task>> planForDay(int id, DateTime day) => throw UnimplementedError();
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockRoutineRepository routineRepo;
  late FakeProjectRepository projectRepo;
  late _FakeTaskServer taskServer;
  late DailyPlan plan;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    planRepo = _MockDailyPlanRepository();
    routineRepo = _MockRoutineRepository();
    projectRepo = FakeProjectRepository(); // 1: 25%, 2: no tasks (both active)

    final planJson = _read('daily_plan_with_tasks.json') as Map<String, dynamic>;
    final tasks = (planJson['tasks'] as List)
        .map((t) => Task.fromJson(t as Map<String, dynamic>))
        .toList();
    plan = DailyPlan(planDate: _day, mainFocus: tasks.first, tasks: tasks);
    final routines = (_read('routines_day.json') as List)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();

    taskServer = _FakeTaskServer(List.of(tasks), (projectId) {
      projectRepo.server = [
        for (final p in projectRepo.server)
          if (p.id == projectId)
            p.copyWith(
              totalTasks: p.totalTasks + 1,
              progressPercent: (p.doneTasks * 100 / (p.totalTasks + 1)).round(),
            )
          else
            p,
      ];
    });
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(routines));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(790, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskServer),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  Finder inProjects(Finder f) => find.descendant(of: find.byType(ProjectsCard), matching: f);
  Finder navTab(String label) =>
      find.descendant(of: find.byType(NavigationBar), matching: find.text(label));

  /// Texts the focus, daily tasks and routines cards show.
  List<String> homeCardTexts(WidgetTester tester) => [
    for (final card in [MainFocusCard, DailyTasksCard, RoutinesCard])
      for (final e
          in find.descendant(of: find.byType(card), matching: find.byType(Text)).evaluate())
        '$card:${(e.widget as Text).data}',
  ];

  testWidgets('create a task linked to a project from the form: Planning shows it with project '
      'and due day; Home "Aktif Projeler" progress updates; other Home cards unaffected', (
    tester,
  ) async {
    await pumpApp(tester);

    // Before: project 2 has no tasks, project 1 is at 25%.
    expect(inProjects(find.byKey(const ValueKey('project-no-tasks-2'))), findsOneWidget);
    expect(inProjects(find.byKey(const ValueKey('project-progress-2'))), findsNothing);
    expect(inProjects(find.text('%25')), findsOneWidget);
    expect(inProjects(find.text('Aktif 2/3')), findsOneWidget);
    final homeBefore = homeCardTexts(tester);
    expect(homeBefore, isNotEmpty);
    final routineCallsBefore = verify(() => routineRepo.getRoutinesForDay(any())).callCount;
    final planCallsBefore = verify(() => planRepo.getPlan(any())).callCount;
    final activeCallsBefore = projectRepo.activeCalls;

    // Planning tab → "Yeni Görev" → form.
    await tester.tap(navTab('Planlama'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskListPage), findsOneWidget);
    await tester.tap(find.text('Yeni Görev'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditScreen), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('task-title')), 'Kitap listesini hazırla');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownMenu<ProjectChoice>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Kitap okuma listesi').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-due-date-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('21')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-save')));
    await tester.pumpAndSettle();

    // Back on Planning: the new task with its project name and due day.
    expect(taskServer.createCalls, 1);
    expect(find.byType(TaskEditScreen), findsNothing);
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(find.text('Kitap listesini hazırla'), findsOneWidget);
    expect(find.text('Kitap okuma listesi · 21 Kas'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);

    // Home: project 2 now has a task (0%), project 1 and the limit unchanged.
    await tester.tap(navTab('Ana Sayfa'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(inProjects(find.byKey(const ValueKey('project-no-tasks-2'))), findsNothing);
    final progress2 = inProjects(find.byKey(const ValueKey('project-progress-2')));
    expect(progress2, findsOneWidget);
    expect(find.descendant(of: progress2, matching: find.text('%0')), findsOneWidget);
    expect(inProjects(find.text('%25')), findsOneWidget);
    expect(inProjects(find.text('Aktif 2/3')), findsOneWidget);
    expect(projectRepo.activeCalls, activeCallsBefore + 1, reason: 'card re-fetched once');

    // Focus, daily tasks and routines cards: same content, no skeleton/error.
    expect(homeCardTexts(tester), homeBefore);
    expect(find.byType(DailyPlanLoading), findsNothing);
    expect(find.byType(DailyPlanError), findsNothing);
    expect(routineCallsBefore, greaterThan(0));
    // No new routine request since the count above (verify consumed them).
    verifyNever(() => routineRepo.getRoutinesForDay(any()));
    // Existing Planning → Home sync (TaskListNotifier._syncHome, unchanged in
    // this step) reloads the daily plan exactly once; its cards keep their
    // content (checked above).
    expect(planCallsBefore, greaterThan(0));
    verify(() => planRepo.getPlan(_day)).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a task without a project leaves the projects card alone', (tester) async {
    await pumpApp(tester);

    await tester.tap(navTab('Planlama'));
    await tester.pumpAndSettle();
    // Counted after Planning loaded its project names (first load).
    final activeCallsBefore = projectRepo.activeCalls;
    final listCallsBefore = projectRepo.listCalls;
    expect(listCallsBefore, 1);
    await tester.tap(find.text('Yeni Görev'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('task-title')), 'Market alışverişi');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-save')));
    await tester.pumpAndSettle();

    expect(find.text('Market alışverişi'), findsOneWidget);
    expect(projectRepo.activeCalls, activeCallsBefore);
    expect(projectRepo.listCalls, listCallsBefore);
    await tester.tap(navTab('Ana Sayfa'));
    await tester.pumpAndSettle();
    expect(inProjects(find.byKey(const ValueKey('project-no-tasks-2'))), findsOneWidget);
  });
}
