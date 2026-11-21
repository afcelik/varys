// Home + calendar integration: the real app root and router (MainScaffold,
// HomeScreen, /calendar, the task and routine forms, real notifiers). Only
// the repositories are fakes, and they form one consistent server: the
// calendar fake computes its counts from the task, routine and schedule
// fakes' current contents with the backend's rules (checked against the real
// backend JSON first). Other Home cards' request counts must not move when
// the calendar opens or a day is chosen. pumpAndSettle is never used.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/calendar/data/calendar_repository_impl.dart';
import 'package:varys/features/calendar/presentation/calendar_screen.dart';
import 'package:varys/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routine_edit_screen.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';

import '../../helpers/varys_app_harness.dart';
import '../notes/fake_note_repository.dart';
import '../schedule/fake_schedule_repository.dart';
import 'fake_calendar_repository.dart';
import 'fake_task_server.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

final _today = DateTime(2026, 11, 21); // Saturday

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

Task _task(int id, String title, {DateTime? planned, DateTime? due, TaskStatus? status}) => Task(
  id: id,
  title: title,
  status: status ?? TaskStatus.todo,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  plannedDate: planned,
  dueDate: due,
);

Finder _cell(DateTime d) => find.byKey(ValueKey('calendar-day-${formatDateForApi(d)}'));
Finder _row(String kind, int id) => find.byKey(ValueKey('calendar-row-$kind-$id'));

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockRoutineRepository routineRepo;
  late _MockProjectRepository projectRepo;
  late FakeTaskServer taskServer;
  late FakeNoteRepository noteRepo;
  late FakeScheduleRepository scheduleRepo;
  late FakeCalendarRepository calendarRepo;
  late List<Map<String, dynamic>> routineJson;
  late List<RoutineDayItem> routines;
  late int planCalls;
  late int projectCalls;
  late List<DateTime> routineDays;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(ProjectStatus.active);
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    planRepo = _MockDailyPlanRepository();
    routineRepo = _MockRoutineRepository();
    projectRepo = _MockProjectRepository();
    noteRepo = FakeNoteRepository();
    scheduleRepo = FakeScheduleRepository();
    taskServer = FakeTaskServer([
      _task(1, 'Rapor yaz', planned: _today),
      _task(2, 'Sunum hazırla', planned: _today, due: _today),
      _task(3, 'Fatura yatır', due: DateTime(2026, 11, 24)),
      _task(4, 'Eski iş', planned: _today, status: TaskStatus.done),
    ]);
    routineJson = (_read('routines_day.json') as List).cast<Map<String, dynamic>>();
    routines = routineJson.map(RoutineDayItem.fromJson).toList();
    calendarRepo = FakeCalendarRepository.consistent(
      tasks: () => taskServer.server,
      routines: () => routines,
      blocks: () => scheduleRepo.server,
    );
    planCalls = 0;
    projectCalls = 0;
    routineDays = [];

    final projects = (_read('projects_list.json') as List)
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList();
    final limits = ProjectLimits.fromJson(_read('projects_limits.json') as Map<String, dynamic>);
    when(() => planRepo.getPlan(any())).thenAnswer((_) async {
      planCalls++;
      return Right(DailyPlan(planDate: _today, tasks: taskServer.server.take(2).toList()));
    });
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((inv) async {
      final day = inv.positionalArguments.first as DateTime;
      routineDays.add(day);
      return Right([
        for (final r in routines)
          if (routineIsDue(r, day)) r,
      ]);
    });
    when(() => projectRepo.getProjects(status: any(named: 'status'))).thenAnswer((inv) async {
      // Only the Home "Aktif Projeler" card asks for active ones; the task form
      // loads the unfiltered list for its own picker.
      if (inv.namedArguments[#status] == ProjectStatus.active) projectCalls++;
      return Right(projects);
    });
    when(() => projectRepo.getLimits()).thenAnswer((_) async => Right(limits));
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pump();
    await tester.tap(f);
    await settle(tester);
  }

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        nowProvider.overrideWithValue(() => DateTime(2026, 11, 21, 9, 10)),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskServer),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
        noteRepositoryProvider.overrideWith((ref) async => noteRepo),
        scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
        calendarRepositoryProvider.overrideWith((ref) async => calendarRepo),
      ],
    );
    await settle(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  /// Request counts of the other Home cards (plan, tasks, today's routines
  /// and blocks, projects, the note of the day).
  ({int plan, int tasks, int routinesToday, int blocksToday, int projects, int note}) homeCalls() =>
      (
        plan: planCalls,
        tasks: taskServer.listCalls,
        routinesToday: routineDays.where((d) => d == _today).length,
        blocksToday: scheduleRepo.dayRequests.where((d) => d == _today).length,
        projects: projectCalls,
        note: noteRepo.ofDayCalls,
      );

  /// The counts label the grid must show for [day], from the server contents.
  String expectedLabel(DateTime day) {
    final month = computeCalendarMonth(
      day.year,
      day.month,
      tasks: taskServer.server,
      routines: routines,
      blocks: scheduleRepo.server,
    );
    return CalendarMonthGrid.countsLabel(month.days[day.day - 1]);
  }

  Future<void> openCalendar(WidgetTester tester) async {
    await tapAndSettle(tester, find.byKey(const ValueKey('date-header-tap')));
    expect(find.byType(CalendarScreen), findsOneWidget);
  }

  test('the consistent fake reproduces the real backend months (same seed data)', () {
    // The data the fixtures were generated from in varys-api.
    DateTime d(int y, int m, int day, [int h = 0, int min = 0]) => DateTime(y, m, day, h, min);
    final tasks = [
      _task(1, 'Rapor', planned: d(2026, 11, 3)),
      _task(2, 'Sunum', planned: d(2026, 11, 3), due: d(2026, 11, 5)),
      _task(3, 'Saatli', planned: d(2026, 11, 21, 15, 30), due: d(2026, 11, 21)),
      _task(4, 'Bugün 2', planned: d(2026, 11, 21)),
      _task(5, 'Ay sonu', due: d(2026, 11, 30)),
      _task(6, 'Bitti', planned: d(2026, 11, 10), status: TaskStatus.done),
      _task(7, 'Başka ay', planned: d(2026, 12, 1)),
      _task(8, 'Artık gün', planned: d(2024, 2, 29), due: d(2024, 2, 29)),
    ];
    RoutineDayItem routine(RecurrenceType type, {List<int>? days, int? dayOfMonth}) =>
        RoutineDayItem(
          id: 1,
          title: 'r',
          recurrenceType: type,
          daysOfWeek: days,
          dayOfMonth: dayOfMonth,
          startDate: d(2024, 1, 1),
          createdAt: d(2024, 1, 1),
          updatedAt: d(2024, 1, 1),
          completed: false,
          currentStreak: 0,
          longestStreak: 0,
        );
    final seedRoutines = [
      routine(RecurrenceType.weekly, days: [0, 2]),
      routine(RecurrenceType.monthly, dayOfMonth: 15),
    ];
    final base = scheduleListFixture().first;
    final seedBlocks = [
      base.copyWith(recurrenceType: RecurrenceType.daily, startDate: d(2026, 11, 16)),
      base.copyWith(
        recurrenceType: RecurrenceType.weekly,
        daysOfWeek: [5, 6],
        startDate: d(2024, 2, 1),
      ),
    ];
    expect(
      computeCalendarMonth(2026, 11, tasks: tasks, routines: seedRoutines, blocks: seedBlocks),
      calendarMonthFixture(),
    );
    expect(
      computeCalendarMonth(2024, 2, tasks: tasks, routines: seedRoutines, blocks: seedBlocks),
      calendarLeapMonthFixture(),
    );
  });

  testWidgets('Home -> calendar -> day -> task form (title + planned day cleared) -> back: the '
      'day list and month counts follow; marking a task done lowers the count', (tester) async {
    await pumpApp(tester);
    final before = homeCalls();

    await openCalendar(tester);
    expect(calendarRepo.requests, [(year: 2026, month: 11)]);
    final handle = tester.ensureSemantics();
    expect(expectedLabel(_today), '2 görev, 1 rutin, 4 program blok, 1 bitiş');
    expect(find.bySemanticsLabel(expectedLabel(_today)), findsOneWidget);
    expect(
      find.bySemanticsLabel(expectedLabel(DateTime(2026, 11, 24))),
      findsWidgets,
      reason: '24th: the due task and its blocks',
    );
    // Opening the calendar and its first day sends nothing new for Home's cards.
    expect(homeCalls(), before);

    await tapAndSettle(tester, _cell(DateTime(2026, 11, 24)));
    expect(_row('due', 3), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-section-tasks')), findsNothing);
    expect(_row('schedule', 6), findsOneWidget);

    await tapAndSettle(tester, _cell(_today));
    expect(_row('task', 1), findsOneWidget);
    expect(_row('task', 2), findsOneWidget);
    expect(_row('due', 2), findsOneWidget);
    expect(_row('task', 4), findsNothing, reason: 'done');
    expect(_row('routine', 1), findsOneWidget);
    expect(homeCalls(), before, reason: 'choosing days: only the calendar\'s own requests');

    // Edit "Sunum hazırla": new title, planned day cleared (still due today).
    await tapAndSettle(tester, _row('task', 2));
    expect(find.byType(TaskEditScreen), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('task-title')), 'Sunum (son hali)');
    await tapAndSettle(tester, find.byKey(const ValueKey('task-planned-date-clear')));
    await tapAndSettle(tester, find.byKey(const ValueKey('task-save')));
    expect(find.byType(TaskEditScreen), findsNothing);
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(taskServer.updateCalls, [2]);

    expect(_row('task', 2), findsNothing, reason: 'no longer planned today');
    expect(_row('due', 2), findsOneWidget);
    expect(find.text('Sunum (son hali)'), findsOneWidget);
    expect(find.text('Sunum hazırla'), findsNothing);
    expect(calendarRepo.requests, hasLength(2), reason: 'one month refresh after the edit');
    expect(expectedLabel(_today), '1 görev, 1 rutin, 4 program blok, 1 bitiş');
    expect(find.bySemanticsLabel(expectedLabel(_today)), findsOneWidget);

    // Done (the same TaskListNotifier Planning and Home use): count drops once.
    final container = ProviderScope.containerOf(tester.element(find.byType(CalendarScreen)));
    await container.read(taskListNotifierProvider.notifier).toggleTaskCompletion(1);
    await settle(tester);
    expect(calendarRepo.requests, hasLength(3));
    expect(expectedLabel(_today), '0 görev, 1 rutin, 4 program blok, 1 bitiş');
    expect(find.bySemanticsLabel(expectedLabel(_today)), findsOneWidget);
    expect(find.byKey(const ValueKey('calendar-section-tasks')), findsNothing);
    handle.dispose();

    await settle(tester);
    expect(calendarRepo.requests, hasLength(3), reason: 'quiet afterwards (no loop)');
    expect(homeCalls().routinesToday, before.routinesToday);
    expect(homeCalls().blocksToday, before.blocksToday);
    expect(homeCalls().projects, before.projects);
    expect(homeCalls().note, before.note);

    await tapAndSettle(tester, find.byIcon(Icons.arrow_back));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(CalendarScreen), findsNothing);
  });

  testWidgets('a block added with quick add on Home appears in the calendar', (tester) async {
    await pumpApp(tester);
    final field = find.byKey(const ValueKey('schedule-quick-add'));
    await tester.ensureVisible(field);
    await tester.enterText(field, '20:00-21:00 akşam yürüyüşü');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(scheduleRepo.createBodies, hasLength(1));
    final before = homeCalls();

    await openCalendar(tester);
    final created = scheduleRepo.server.last;
    expect(created.title, 'akşam yürüyüşü');
    expect(_row('schedule', created.id), findsOneWidget);
    expect(find.text('akşam yürüyüşü'), findsWidgets); // the card below and the day list
    final handle = tester.ensureSemantics();
    expect(expectedLabel(_today), '2 görev, 1 rutin, 5 program blok, 1 bitiş');
    expect(find.bySemanticsLabel(expectedLabel(_today)), findsOneWidget);
    // A daily block from today: tomorrow counts it too, yesterday does not.
    expect(find.bySemanticsLabel(expectedLabel(DateTime(2026, 11, 22))), findsWidgets);
    String labelWithout(DateTime day) => CalendarMonthGrid.countsLabel(
      computeCalendarMonth(
        2026,
        11,
        tasks: taskServer.server,
        routines: routines,
        blocks: scheduleRepo.server.where((b) => b.id != created.id),
      ).days[day.day - 1],
    );
    expect(expectedLabel(DateTime(2026, 11, 20)), labelWithout(DateTime(2026, 11, 20)));
    expect(expectedLabel(DateTime(2026, 11, 22)), isNot(labelWithout(DateTime(2026, 11, 22))));
    handle.dispose();
    // The newest block is last among the day's rows (latest start time).
    final rows = [6, 1, 3, 7, created.id].map((id) => tester.getTopLeft(_row('schedule', id)).dy);
    expect(rows.toList(), orderedEquals([...rows]..sort()));
    expect(homeCalls(), before);
  });

  testWidgets('routine rows open the form with every field (no loss in the conversion)', (
    tester,
  ) async {
    await pumpApp(tester);
    await openCalendar(tester);

    // Daily routine with a description, on today.
    await tapAndSettle(tester, _row('routine', 1));
    final daily = tester.widget<RoutineEditScreen>(find.byType(RoutineEditScreen));
    expect(daily.routine, Routine.fromJson(routineJson[0]));
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('routine-title'))).controller!.text,
      'Su iç',
    );
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('routine-description'))).controller!.text,
      '8 bardak',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('routine-start-date-text'))).data,
      '01.11.2026',
    );
    await tapAndSettle(tester, find.byIcon(Icons.arrow_back));
    expect(find.byType(CalendarScreen), findsOneWidget);

    // Weekly routine (Pzt, Çar) on Monday 23rd: the day chips come filled.
    await tapAndSettle(tester, _cell(DateTime(2026, 11, 23)));
    await tapAndSettle(tester, _row('routine', 2));
    final weekly = tester.widget<RoutineEditScreen>(find.byType(RoutineEditScreen));
    expect(weekly.routine, Routine.fromJson(routineJson[1]));
    bool chip(int d) => tester.widget<FilterChip>(find.byKey(ValueKey('weekday-$d'))).selected;
    expect([for (var d = 0; d < 7; d++) chip(d)], [true, false, true, false, false, false, false]);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('routine-start-date-text'))).data,
      '02.11.2026',
    );
    expect(find.text(RoutineEditScreen.editTitle), findsOneWidget);
  });
}
