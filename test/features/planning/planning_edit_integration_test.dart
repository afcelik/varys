// Planning edit form + Home integration: the real app root and router (real
// MainScaffold, HomeScreen, TaskListPage, TaskEditScreen and real notifiers).
// Only the repositories are fakes, and they keep one consistent server state
// like the backend does:
// - tasks: real GET /tasks JSON (tasks_with_project.json); PATCH applies the
//   sent fields (explicit null clears; unknown task / project → 404);
// - projects: real GET /projects JSON; total/done/progress are recounted from
//   the task state after every PATCH (Python round = half to even);
// - daily plan: built per request like DailyPlanService.get_plan: `tasks` are
//   the tasks planned for the day, `main_focus` is looked up by id and does
//   NOT depend on the task's planned_date.

import 'dart:async';
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

/// Python's round(): half to even (backend `progress_percent`).
int _roundHalfEven(double x) {
  final floor = x.floorToDouble();
  final diff = x - floor;
  if (diff > 0.5) return floor.toInt() + 1;
  if (diff < 0.5) return floor.toInt();
  return floor.toInt().isEven ? floor.toInt() : floor.toInt() + 1;
}

/// Task server stand-in holding task JSON, as the backend stores it.
class _FakeTaskServer implements TaskRepository {
  _FakeTaskServer(this.tasks, this.projectExists, this.onChanged);

  /// Task JSON by id, in list order.
  final Map<int, Map<String, dynamic>> tasks;
  final bool Function(int projectId) projectExists;
  final void Function() onChanged;
  int patchCalls = 0;

  Task task(int id) => Task.fromJson(Map.of(tasks[id]!));
  List<Task> get all => [for (final id in tasks.keys) task(id)];

  @override
  Future<Either<Failure, List<Task>>> getTasks() async => Right(all);

  @override
  Future<Either<Failure, List<Task>>> getTasksByFilter(TaskFilter filter) async =>
      Right(switch (filter) {
        TaskFilter.all => all,
        TaskFilter.inProgress => all.where((t) => t.status != TaskStatus.done).toList(),
        TaskFilter.completed => all.where((t) => t.status == TaskStatus.done).toList(),
      });

  @override
  Future<Either<Failure, Task>> createTask(Task task) => throw UnimplementedError();

  static Object? _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}T00:00:00';

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
    patchCalls++;
    final current = tasks[id];
    if (current == null) return const Left(ServerFailure('Kaynak bulunamadı.', statusCode: 404));
    if (projectId case PlanFieldSet<int>(:final value) when !projectExists(value)) {
      return const Left(ServerFailure('Seçilen proje bulunamadı.', statusCode: 404));
    }
    final next = Map<String, dynamic>.of(current);
    if (title != null) next['title'] = title;
    description.writeTo(next, 'description');
    projectId.writeTo(next, 'project_id');
    switch (plannedDate) {
      case PlanFieldSet<DateTime>(:final value):
        next['planned_date'] = _day(value);
      case PlanFieldClear<DateTime>():
        next['planned_date'] = null;
      case PlanFieldUnset<DateTime>():
    }
    switch (dueDate) {
      case PlanFieldSet<DateTime>(:final value):
        next['due_date'] = _day(value);
      case PlanFieldClear<DateTime>():
        next['due_date'] = null;
      case PlanFieldUnset<DateTime>():
    }
    tasks[id] = next;
    onChanged();
    return Right(task(id));
  }

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

  /// When set, getPlan waits on it (to look at Home while it reloads).
  Completer<void>? planGate;

  /// Today's main focus: task 3 "Adres değişikliği" (planned today).
  const mainFocusId = 3;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    planRepo = _MockDailyPlanRepository();
    routineRepo = _MockRoutineRepository();
    planGate = null;
    // Real GET /projects: 1 "Ev taşıma" (4 tasks, 1 done = 25%) and 2 "Kitap
    // okuma listesi" (no tasks) are active; 5 completed (2/2). These counts
    // match the real GET /tasks fixture below.
    projectRepo = FakeProjectRepository();

    // Real GET /tasks. Tasks 1 (done), 2 and 3 are planned for today.
    final tasks = {
      for (final t in (_read('tasks_with_project.json') as List).cast<Map<String, dynamic>>())
        t['id'] as int: Map<String, dynamic>.of(t),
    };
    for (final id in [2, 3]) {
      tasks[id]!['planned_date'] = '2026-11-19T00:00:00';
    }

    void recountProjects() {
      final all = taskServer.all;
      projectRepo.server = [
        for (final p in projectRepo.server)
          () {
            final linked = all.where((t) => t.projectId == p.id).toList();
            final done = linked.where((t) => t.status == TaskStatus.done).length;
            return p.copyWith(
              totalTasks: linked.length,
              doneTasks: done,
              progressPercent: linked.isEmpty ? null : _roundHalfEven(done * 100 / linked.length),
            );
          }(),
      ];
    }

    taskServer = _FakeTaskServer(
      tasks,
      (projectId) => projectRepo.server.any((p) => p.id == projectId),
      recountProjects,
    );
    recountProjects(); // no-op on the fixtures (they already agree)

    final routines = (_read('routines_day.json') as List)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();
    when(() => planRepo.getPlan(any())).thenAnswer((inv) async {
      final gate = planGate;
      if (gate != null) await gate.future;
      final day = inv.positionalArguments.first as DateTime;
      final all = taskServer.all;
      return Right(
        DailyPlan(
          planDate: day,
          mainFocus: all.where((t) => t.id == mainFocusId).firstOrNull,
          tasks: all
              .where((t) => t.plannedDate != null && DateUtils.isSameDay(t.plannedDate, day))
              .toList(),
        ),
      );
    });
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

  Finder inCard(Type card, Finder f) => find.descendant(of: find.byType(card), matching: f);
  Finder navTab(String label) =>
      find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
  Finder row(String title) => find.ancestor(of: find.text(title), matching: find.byType(ListTile));
  Finder meta(int id) => find.byKey(ValueKey('task-meta-$id'));
  final saveButton = find.byKey(const ValueKey('task-save'));

  /// Every text of the given Home cards, prefixed with the card type.
  List<String> cardTexts(List<Type> cards) => [
    for (final card in cards)
      for (final e
          in find.descendant(of: find.byType(card), matching: find.byType(Text)).evaluate())
        '$card:${(e.widget as Text).data}',
  ];

  Future<void> goPlanning(WidgetTester tester) async {
    await tester.tap(navTab('Planlama'));
    await tester.pumpAndSettle();
    expect(find.byType(TaskListPage), findsOneWidget);
  }

  Future<void> goHome(WidgetTester tester) async {
    await tester.tap(navTab('Ana Sayfa'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  /// From Planning: tap the row → form.
  Future<void> openRow(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(find.byType(TaskEditScreen), findsOneWidget);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  Future<void> clearDay(WidgetTester tester, String prefix) async {
    final clear = find.byKey(ValueKey('$prefix-clear'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
  }

  String dailyCounter(WidgetTester tester) {
    final counter = inCard(DailyTasksCard, find.textContaining(RegExp(r'^\d+/\d+$')));
    expect(counter, findsOneWidget);
    return tester.widget<Text>(counter).data!;
  }

  testWidgets('(1) project A → B: Planning row shows B; Home "Aktif Projeler" recounts both; '
      'other cards unaffected; getPlan exactly +1', (tester) async {
    await pumpApp(tester);
    expect(
      find.descendant(
        of: inCard(ProjectsCard, find.byKey(const ValueKey('project-progress-1'))),
        matching: find.text('%25'),
      ),
      findsOneWidget,
    );
    expect(inCard(ProjectsCard, find.byKey(const ValueKey('project-no-tasks-2'))), findsOneWidget);
    final othersBefore = cardTexts([MainFocusCard, DailyTasksCard, RoutinesCard]);
    expect(othersBefore, isNotEmpty);
    final planCallsBefore = verify(() => planRepo.getPlan(any())).callCount;
    final routineCallsBefore = verify(() => routineRepo.getRoutinesForDay(any())).callCount;
    expect(planCallsBefore, greaterThan(0));
    expect(routineCallsBefore, greaterThan(0));
    final activeCallsBefore = projectRepo.activeCalls;

    await goPlanning(tester);
    expect(tester.widget<Text>(meta(2)).data, 'Ev taşıma');
    await openRow(tester, 'Kutuları topla');
    await tester.tap(find.byType(DropdownMenu<ProjectChoice>));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Kitap okuma listesi').last);
    await tester.pumpAndSettle();
    await save(tester);

    expect(taskServer.patchCalls, 1);
    expect(find.byType(TaskEditScreen), findsNothing);
    expect(tester.widget<Text>(meta(2)).data, 'Kitap okuma listesi');
    expect(find.byType(SnackBar), findsNothing);

    await goHome(tester);
    // Project 1: 3 tasks, 1 done → 33%. Project 2: 1 task, 0 done → 0%.
    final progress1 = inCard(ProjectsCard, find.byKey(const ValueKey('project-progress-1')));
    final progress2 = inCard(ProjectsCard, find.byKey(const ValueKey('project-progress-2')));
    expect(find.descendant(of: progress1, matching: find.text('%33')), findsOneWidget);
    expect(find.descendant(of: progress2, matching: find.text('%0')), findsOneWidget);
    expect(inCard(ProjectsCard, find.byKey(const ValueKey('project-no-tasks-2'))), findsNothing);
    expect(projectRepo.activeCalls, activeCallsBefore + 1, reason: 'card re-fetched once');

    expect(cardTexts([MainFocusCard, DailyTasksCard, RoutinesCard]), othersBefore);
    expect(find.byType(DailyPlanLoading), findsNothing);
    expect(find.byType(DailyPlanError), findsNothing);
    // The verifies above consumed the earlier calls: only new ones count now.
    verify(() => planRepo.getPlan(_day)).called(1);
    verifyNever(() => routineRepo.getRoutinesForDay(any()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('(2) planned day cleared: the task leaves "Bugün Yapılacaklar", counter drops', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(inCard(DailyTasksCard, find.text('Kutuları topla')), findsOneWidget);
    expect(dailyCounter(tester), '1/3');

    await goPlanning(tester);
    await openRow(tester, 'Kutuları topla');
    await clearDay(tester, 'task-planned-date');
    await save(tester);
    expect(taskServer.task(2).plannedDate, isNull);

    await goHome(tester);
    expect(inCard(DailyTasksCard, find.text('Kutuları topla')), findsNothing);
    expect(dailyCounter(tester), '1/2');
    expect(tester.takeException(), isNull);
  });

  testWidgets('(3) planned day of the MAIN FOCUS cleared: leaves the daily list, the focus card '
      'keeps it; no skeleton or error while Home reloads', (tester) async {
    await pumpApp(tester);
    expect(inCard(MainFocusCard, find.text('Adres değişikliği')), findsOneWidget);
    expect(inCard(DailyTasksCard, find.text('Adres değişikliği')), findsOneWidget);
    expect(dailyCounter(tester), '1/3');
    final focusBefore = cardTexts([MainFocusCard]);

    await goPlanning(tester);
    await openRow(tester, 'Adres değişikliği');
    // Park Home's reload so its in-between state can be checked.
    planGate = Completer<void>();
    await clearDay(tester, 'task-planned-date');
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(navTab('Ana Sayfa'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(DailyPlanLoading), findsNothing, reason: 'no skeleton while reloading');
    expect(find.byType(DailyPlanError), findsNothing);
    expect(cardTexts([MainFocusCard]), focusBefore, reason: 'old plan stays on screen');

    planGate!.complete();
    planGate = null;
    await tester.pumpAndSettle();

    expect(taskServer.task(mainFocusId).plannedDate, isNull);
    expect(inCard(DailyTasksCard, find.text('Adres değişikliği')), findsNothing);
    expect(dailyCounter(tester), '1/2');
    expect(cardTexts([MainFocusCard]), focusBefore, reason: 'main focus card unchanged');
    expect(inCard(MainFocusCard, find.text('Adres değişikliği')), findsOneWidget);
    expect(find.byType(DailyPlanLoading), findsNothing);
    expect(find.byType(DailyPlanError), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('(4) due date cleared: the day leaves the row (meta line gone)', (tester) async {
    await pumpApp(tester);
    await goPlanning(tester);
    expect(tester.widget<Text>(meta(7)).data, '25 Kas');

    await openRow(tester, 'Projesiz görev');
    await clearDay(tester, 'task-due-date');
    await save(tester);

    expect(taskServer.task(7).dueDate, isNull);
    expect(meta(7), findsNothing, reason: 'no project, no due day → no meta line');
    expect(find.text('Projesiz görev'), findsOneWidget);
  });

  testWidgets('(5) title and description changed: the row shows both', (tester) async {
    await pumpApp(tester);
    await goPlanning(tester);

    await openRow(tester, 'İnternet taşıma');
    await tester.enterText(find.byKey(const ValueKey('task-title')), 'Fiber internet taşıma');
    await tester.enterText(find.byKey(const ValueKey('task-description')), 'Randevu: sabah 9-12');
    await tester.pumpAndSettle();
    await save(tester);

    expect(find.text('İnternet taşıma'), findsNothing);
    expect(
      find.descendant(of: row('Fiber internet taşıma'), matching: find.text('Randevu: sabah 9-12')),
      findsOneWidget,
    );
    expect(tester.widget<Text>(meta(4)).data, 'Ev taşıma', reason: 'project untouched');
  });

  testWidgets('(6) task deleted elsewhere (404): message, form stays; back on Planning the row '
      'is gone', (tester) async {
    await pumpApp(tester);
    await goPlanning(tester);

    await openRow(tester, 'İnternet taşıma');
    taskServer.tasks.remove(4); // deleted on another device
    await tester.enterText(find.byKey(const ValueKey('task-title')), 'Geç kalan düzenleme');
    await tester.pumpAndSettle();
    await save(tester);

    expect(
      find.descendant(of: find.byType(SnackBar), matching: find.text('Kaynak bulunamadı.')),
      findsOneWidget,
    );
    expect(find.byType(TaskEditScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(TaskListPage), findsOneWidget);
    expect(find.text('İnternet taşıma'), findsNothing);
    expect(find.text('Geç kalan düzenleme'), findsNothing);
    expect(find.text('Kutuları topla'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
