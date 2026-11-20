// End to end on the real app (VarysApp, real router and shell, real
// notifiers and providers); only the repositories are fakes. The task fake
// is a small consistent server (GET answers its state, PATCH applies the
// flags), seeded from the real GET /tasks (tasks_eisenhower.json).
//
// Flow: Home card → "Planla" quadrant → task → turn "Acil" on → Kaydet →
// back: the task leaves "Planla", shows up in "Hemen yap", the card counts
// follow; the other Home cards are not reloaded (only getPlan +1, from the
// existing task-edit sync). Then logout → server changes → login: the card
// shows the fresh data.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/auth/domain/auth_notifier.dart';
import 'package:varys/features/auth/presentation/login_page.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/eisenhower_quadrant_page.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/eisenhower_card.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/eisenhower.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

import '../../helpers/varys_app_harness.dart';
import '../notes/fake_note_repository.dart';
import '../projects/fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

/// Consistent fake task server: GET answers [tasks]; PATCH applies the
/// given fields (flags, title, dates) and answers the stored task.
class _FakeTaskServer implements TaskRepository {
  _FakeTaskServer(this.tasks);

  List<Task> tasks;
  int listCalls = 0;
  int allCalls = 0;
  final patches = <(int, bool?, bool?)>[];

  @override
  Future<Either<Failure, List<Task>>> getTasks() async {
    allCalls++;
    return Right(List.of(tasks));
  }

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
  }) async {
    patches.add((id, isImportant, isUrgent));
    final current = tasks.firstWhere((t) => t.id == id);
    final updated = current.copyWith(
      title: title ?? current.title,
      status: status ?? current.status,
      isImportant: isImportant ?? current.isImportant,
      isUrgent: isUrgent ?? current.isUrgent,
    );
    tasks = [for (final t in tasks) t.id == id ? updated : t];
    return Right(updated);
  }

  @override
  Future<Either<Failure, Task>> createTask(Task task) => throw UnimplementedError('not used');

  @override
  Future<Either<Failure, void>> deleteTask(int id) => throw UnimplementedError('not used');

  @override
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status) =>
      throw UnimplementedError('not used');

  @override
  Future<Either<Failure, Task>> planForDay(int id, DateTime day) =>
      throw UnimplementedError('not used');
}

List<Task> _fixture() =>
    (jsonDecode(File('test/fixtures/tasks_eisenhower.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .map(Task.fromJson)
        .toList();

void main() {
  late _FakeTaskServer taskServer;
  late _MockDailyPlanRepository planRepo;
  late _MockRoutineRepository routineRepo;
  late FakeProjectRepository projectRepo;
  late FakeNoteRepository noteRepo;
  late int planCalls;
  late int routineCalls;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    taskServer = _FakeTaskServer(_fixture());
    planRepo = _MockDailyPlanRepository();
    routineRepo = _MockRoutineRepository();
    projectRepo = FakeProjectRepository();
    noteRepo = FakeNoteRepository();
    planCalls = 0;
    routineCalls = 0;
    when(() => planRepo.getPlan(any())).thenAnswer((_) async {
      planCalls++;
      return Right(DailyPlan(planDate: _day, tasks: const []));
    });
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async {
      routineCalls++;
      return const Right([]);
    });
  });

  Future<void> pumpApp(WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = const Size(600, 2400);
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
        noteRepositoryProvider.overrideWith((ref) async => noteRepo),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  Finder quadrant(EisenhowerQuadrant q) =>
      find.byKey(ValueKey('eisenhower-quadrant-${q.pathSegment}'));
  Finder inQuadrant(EisenhowerQuadrant q, String text) =>
      find.descendant(of: quadrant(q), matching: find.text(text));
  String count(WidgetTester tester, EisenhowerQuadrant q) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey('eisenhower-count-${q.pathSegment}')),
          matching: find.byType(Text),
        ),
      )
      .data!;
  Map<EisenhowerQuadrant, String> counts(WidgetTester tester) => {
    for (final q in EisenhowerQuadrant.values) q: count(tester, q),
  };

  /// Every non-task request so far: plan, routines, projects, notes.
  ({int plan, int routines, int projectsActive, int projectsList, int limits, int notes})
  otherCalls() => (
    plan: planCalls,
    routines: routineCalls,
    projectsActive: projectRepo.activeCalls,
    projectsList: projectRepo.listCalls,
    limits: projectRepo.limitsCalls,
    notes: noteRepo.ofDayCalls + noteRepo.listCalls + noteRepo.tagsCalls,
  );

  testWidgets('card → quadrant → task → "Acil" on → Kaydet → back: task moves, counts follow', (
    tester,
  ) async {
    await pumpApp(tester);
    const task = 'Haftalık hedefleri yaz';
    expect(counts(tester), {
      EisenhowerQuadrant.doNow: '1',
      EisenhowerQuadrant.schedule: '1',
      EisenhowerQuadrant.delegate: '1',
      EisenhowerQuadrant.eliminate: '1',
    });
    expect(inQuadrant(EisenhowerQuadrant.schedule, task), findsOneWidget);
    final before = otherCalls();
    expect(before.projectsList, 0, reason: 'Home itself does not load the projects page list');

    // Card → "Planla".
    await tester.ensureVisible(quadrant(EisenhowerQuadrant.schedule));
    await tester.pumpAndSettle();
    await tester.tap(quadrant(EisenhowerQuadrant.schedule));
    await tester.pumpAndSettle();
    expect(find.byType(EisenhowerQuadrantPage), findsOneWidget);
    expect(find.text(task), findsOneWidget);

    // Task → edit form → "Acil" on → Kaydet.
    await tester.tap(find.text(task));
    await tester.pumpAndSettle();
    expect(find.text(TaskEditScreen.editTitle), findsOneWidget);
    final urgent = find.byKey(const ValueKey('task-urgent'));
    await tester.ensureVisible(urgent);
    await tester.pumpAndSettle();
    await tester.tap(urgent);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('task-save')));
    await tester.pumpAndSettle();

    expect(taskServer.patches, [(2, null, true)], reason: 'only the changed flag');
    expect(projectRepo.listCalls, 1, reason: 'page + form share one load; save adds none');
    expect(planCalls, before.plan + 1, reason: 'the existing task-edit sync');
    // Back on the quadrant page: the task left "Planla" by itself.
    expect(find.byType(TaskEditScreen), findsNothing);
    expect(find.byType(EisenhowerQuadrantPage), findsOneWidget);
    expect(find.text(task), findsNothing);
    expect(find.text(EisenhowerQuadrantPage.emptyText), findsOneWidget);

    // Back to Home: the card shows the move.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(counts(tester), {
      EisenhowerQuadrant.doNow: '2',
      EisenhowerQuadrant.schedule: '0',
      EisenhowerQuadrant.delegate: '1',
      EisenhowerQuadrant.eliminate: '1',
    });
    expect(inQuadrant(EisenhowerQuadrant.doNow, task), findsOneWidget);
    expect(inQuadrant(EisenhowerQuadrant.schedule, task), findsNothing);

    // And the "Hemen yap" page lists it, newest first.
    await tester.tap(quadrant(EisenhowerQuadrant.doNow));
    await tester.pumpAndSettle();
    expect(find.text(task), findsOneWidget);
    expect(find.text('Vergi beyannamesini gönder'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // Other Home cards were not reloaded: only getPlan +1 (the existing
    // task-edit sync); routines, notes and the Home projects card unchanged.
    // The quadrant page loads the projects page list for row names (with
    // its limits) once per opening (2 openings, autoDispose in between);
    // the save itself did not reload it (the project did not change).
    final after = otherCalls();
    expect(after.plan, before.plan + 1);
    expect(after.routines, before.routines);
    expect(after.projectsActive, before.projectsActive);
    expect(after.notes, before.notes);
    expect(after.projectsList, 2);
    expect(after.limits, before.limits + 2);
    // Task requests: the first load + the silent refresh after the save; the
    // card never needed an unfiltered request (filter stayed "Tümü").
    expect(taskServer.listCalls, 2);
    expect(taskServer.allCalls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout, server changes, login: the card shows the fresh data', (tester) async {
    await pumpApp(tester);
    expect(count(tester, EisenhowerQuadrant.delegate), '1');

    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    final auth = container.read(authNotifierProvider.notifier);
    await auth.logout(container.invalidate);
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(EisenhowerCard), findsNothing);

    // Meanwhile on the server: a new urgent task, the old urgent one is done.
    final base = taskServer.tasks.firstWhere((t) => t.id == 3);
    taskServer.tasks = [
      base.copyWith(id: 30, title: 'Yeni oturumda acil iş', createdAt: DateTime(2026, 11, 21)),
      for (final t in taskServer.tasks) t.id == 3 ? t.copyWith(status: TaskStatus.done) : t,
    ];
    final listCallsBefore = taskServer.listCalls;

    await auth.updateToken('new.jwt.token');
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(taskServer.listCalls, listCallsBefore + 1, reason: 'list fetched again');
    expect(count(tester, EisenhowerQuadrant.delegate), '1');
    expect(inQuadrant(EisenhowerQuadrant.delegate, 'Yeni oturumda acil iş'), findsOneWidget);
    expect(find.text('Kargo görevlisini ara'), findsNothing, reason: 'old data gone');
    expect(find.byKey(const ValueKey('eisenhower-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
