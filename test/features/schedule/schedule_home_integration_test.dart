// Home + schedule integration: the real app root and router (real
// MainScaffold, HomeScreen, ScheduleCard, /schedule and the form, real
// notifiers). Only the repositories are fakes; the schedule fake behaves like
// the server (real backend JSON, recurrence rules), so the card and the
// /schedule list stay consistent. The time picker is injected. Other Home
// cards' request counts must not move. pumpAndSettle is never used.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/schedule_card.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/presentation/schedule_edit_screen.dart';
import 'package:varys/features/schedule/presentation/schedule_screen.dart';

import '../../helpers/varys_app_harness.dart';
import '../notes/fake_note_repository.dart';
import 'fake_schedule_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

final _day = scheduleFixtureDay; // Monday 2026-11-02

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
  late FakeNoteRepository noteRepo;
  late FakeScheduleRepository scheduleRepo;
  late List<ScheduleTime?> pickerAnswers;

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
    noteRepo = FakeNoteRepository();
    scheduleRepo = FakeScheduleRepository();
    pickerAnswers = [];

    final planJson = _read('daily_plan_with_tasks.json') as Map<String, dynamic>;
    final tasks = (planJson['tasks'] as List)
        .map((t) => Task.fromJson(t as Map<String, dynamic>))
        .toList();
    final routines = (_read('routines_day.json') as List)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final projects = (_read('projects_list.json') as List)
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList();
    final limits = ProjectLimits.fromJson(_read('projects_limits.json') as Map<String, dynamic>);
    when(() => planRepo.getPlan(any())).thenAnswer(
      (_) async => Right(DailyPlan(planDate: _day, mainFocus: tasks.first, tasks: tasks)),
    );
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(tasks));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(routines));
    when(
      () => projectRepo.getProjects(status: any(named: 'status')),
    ).thenAnswer((_) async => Right(projects));
    when(() => projectRepo.getLimits()).thenAnswer((_) async => Right(limits));
  });

  /// Fixed time steps: requests answer, transitions and dialogs finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        nowProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9, 10)),
        timePickerProvider.overrideWithValue(
          (context, initial, helpText) async =>
              pickerAnswers.isEmpty ? null : pickerAnswers.removeAt(0),
        ),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
        noteRepositoryProvider.overrideWith((ref) async => noteRepo),
        scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
      ],
    );
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ScheduleCard), findsOneWidget);
  }

  Finder inCard(Finder f) => find.descendant(of: find.byType(ScheduleCard), matching: f);

  /// Requests of the other Home cards made since the previous call
  /// (mocktail's verify marks the calls it counts as verified).
  ({int plan, int tasks, int routines, int projects, int limits}) newOtherCalls() {
    int count(dynamic Function() call) {
      try {
        return verify(call).callCount;
      } on TestFailure {
        return 0; // no new calls
      }
    }

    return (
      plan: count(() => planRepo.getPlan(any())),
      tasks: count(() => taskRepo.getTasksByFilter(any())),
      routines: count(() => routineRepo.getRoutinesForDay(any())),
      projects: count(() => projectRepo.getProjects(status: any(named: 'status'))),
      limits: count(() => projectRepo.getLimits()),
    );
  }

  const none = (plan: 0, tasks: 0, routines: 0, projects: 0, limits: 0);

  /// Home's first load: every other card loaded (once for plan and routines).
  void expectFirstLoad() {
    final first = newOtherCalls();
    expect(first.plan, 1);
    expect(first.routines, 1);
    expect(first.tasks, greaterThan(0));
    expect(first.projects, greaterThan(0));
    expect(first.limits, greaterThan(0));
    expect(noteRepo.ofDayCalls, 1);
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) => tapAndSettle(tester, find.byIcon(Icons.arrow_back));

  testWidgets('quick add "08:30-09:00 kahvaltı": shown on the card and in the /schedule list; '
      'other cards untouched', (tester) async {
    await pumpApp(tester);
    expectFirstLoad();

    final field = find.byKey(const ValueKey('schedule-quick-add'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '08:30-09:00 kahvaltı');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(scheduleRepo.createBodies, hasLength(1));
    expect(inCard(find.text('kahvaltı')), findsOneWidget);
    // Same start as "Kahvaltı" (id 2); the new block has a higher id, so it comes after.
    expect(
      tester.getTopLeft(inCard(find.text('kahvaltı'))).dy,
      greaterThan(tester.getTopLeft(inCard(find.text('Kahvaltı'))).dy),
    );

    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-card-more')));
    expect(find.byType(ScheduleScreen), findsOneWidget);
    expect(find.text('kahvaltı'), findsOneWidget);
    await back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(inCard(find.text('kahvaltı')), findsOneWidget);

    expect(newOtherCalls(), none, reason: 'plan/tasks/routines/projects: no new requests');
    expect(noteRepo.ofDayCalls, 1, reason: 'note of the day: no new request');
  });

  testWidgets('form: add from the card, edit from a row, delete from /schedule -> the card '
      'follows each time; other cards untouched', (tester) async {
    await pumpApp(tester);
    expectFirstLoad();

    // Add: "Blok ekle" -> form -> Kaydet.
    await tapAndSettle(tester, inCard(find.byTooltip(ScheduleCard.addTooltip)));
    expect(find.byType(ScheduleEditScreen), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('schedule-title')), 'Öğle yemeği');
    pickerAnswers.addAll([ScheduleTime.hm(12, 30), ScheduleTime.hm(13, 15)]);
    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-start-time')));
    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-end-time')));
    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-save')));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(ScheduleEditScreen), findsNothing);
    final added = inCard(find.text('Öğle yemeği'));
    expect(added, findsOneWidget);
    expect(inCard(find.text('12:30\u201313:15')), findsOneWidget);

    // Edit: row tap -> form -> new title.
    await tapAndSettle(tester, added);
    expect(find.text(ScheduleEditScreen.editTitle), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('schedule-title')), 'Öğle arası');
    await tester.pump();
    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-save')));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(inCard(find.text('Öğle arası')), findsOneWidget);
    expect(inCard(find.text('Öğle yemeği')), findsNothing);
    expect(scheduleRepo.updateCalls.single.$2, {'title': 'Öğle arası'});

    // Delete: "Daha fazla" -> /schedule -> delete -> confirm -> back.
    final id = scheduleRepo.server.firstWhere((b) => b.title == 'Öğle arası').id;
    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-card-more')));
    await tapAndSettle(tester, find.byKey(ValueKey('schedule-delete-$id')));
    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-delete-confirm')));
    expect(scheduleRepo.deleteIds, [id]);
    expect(find.text('Öğle arası'), findsNothing);
    await back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(inCard(find.text('Öğle arası')), findsNothing);

    expect(newOtherCalls(), none, reason: 'plan/tasks/routines/projects: no new requests');
    expect(noteRepo.ofDayCalls, 1, reason: 'note of the day: no new request');
    expect(tester.takeException(), isNull);
  });

  testWidgets('day list requests: one load, then one per mutation (no loop)', (tester) async {
    await pumpApp(tester);
    expect(scheduleRepo.dayCalls, 1);
    final field = find.byKey(const ValueKey('schedule-quick-add'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '07:30-08:00 hazırlık');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await settle(tester);
    expect(scheduleRepo.dayCalls, 2, reason: 'one silent refresh after the quick add');
    expect(scheduleRepo.listCalls, 0, reason: 'the /schedule list is not loaded from Home');
  });
}
