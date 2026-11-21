// One-time ('once') blocks end to end: the real app root and router
// (MainScaffold, HomeScreen, /calendar, /schedule/new, real notifiers). Only
// the repositories are fakes, and they form one consistent server: the
// calendar fake computes its counts from the task, routine and schedule
// fakes' current contents with the backend's rules. The time picker is
// injected. The other Home cards' request counts must not move. pumpAndSettle
// is never used.

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
import 'package:varys/features/calendar/domain/calendar_month.dart';
import 'package:varys/features/calendar/presentation/calendar_providers.dart';
import 'package:varys/features/calendar/presentation/calendar_screen.dart';
import 'package:varys/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/schedule_card.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/presentation/schedule_edit_screen.dart';

import '../../helpers/varys_app_harness.dart';
import '../calendar/fake_calendar_repository.dart';
import '../calendar/fake_task_server.dart';
import '../notes/fake_note_repository.dart';
import 'fake_schedule_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

final _today = DateTime(2026, 11, 21); // Saturday
final _d25 = DateTime(2026, 11, 25);
final _d26 = DateTime(2026, 11, 26);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

Finder _cell(DateTime d) => find.byKey(ValueKey('calendar-day-${formatDateForApi(d)}'));

/// Answers the time picker from a queue (no picker UI in tests).
class _FakePicker {
  final answers = <ScheduleTime>[];

  Future<ScheduleTime?> call(BuildContext context, ScheduleTime initial, String helpText) async =>
      answers.isEmpty ? null : answers.removeAt(0);
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockRoutineRepository routineRepo;
  late _MockProjectRepository projectRepo;
  late FakeTaskServer taskServer;
  late FakeNoteRepository noteRepo;
  late FakeScheduleRepository scheduleRepo;
  late FakeCalendarRepository calendarRepo;
  late List<RoutineDayItem> routines;
  late _FakePicker picker;
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
    taskServer = FakeTaskServer(const []);
    routines = (_read('routines_day.json') as List)
        .cast<Map<String, dynamic>>()
        .map(RoutineDayItem.fromJson)
        .toList();
    calendarRepo = FakeCalendarRepository.consistent(
      tasks: () => taskServer.server,
      routines: () => routines,
      blocks: () => scheduleRepo.server,
    );
    picker = _FakePicker();
    planCalls = 0;
    projectCalls = 0;
    routineDays = [];

    final projects = (_read('projects_list.json') as List)
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList();
    final limits = ProjectLimits.fromJson(_read('projects_limits.json') as Map<String, dynamic>);
    when(() => planRepo.getPlan(any())).thenAnswer((_) async {
      planCalls++;
      return Right(DailyPlan(planDate: _today, tasks: const []));
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
        timePickerProvider.overrideWithValue(picker.call),
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

  /// Request counts of the other Home cards (plan, tasks, today's routines,
  /// projects, the note of the day). The schedule card itself may refresh.
  ({int plan, int tasks, int routinesToday, int projects, int note}) otherHomeCalls() => (
    plan: planCalls,
    tasks: taskServer.listCalls,
    routinesToday: routineDays.where((d) => d == _today).length,
    projects: projectCalls,
    note: noteRepo.ofDayCalls,
  );

  Future<void> openCalendar(WidgetTester tester) async {
    await tapAndSettle(tester, find.byKey(const ValueKey('date-header-tap')));
    expect(find.byType(CalendarScreen), findsOneWidget);
  }

  /// The month the calendar page currently shows (its provider's value).
  List<CalendarDay> shownMonth(WidgetTester tester) {
    final container = ProviderScope.containerOf(tester.element(find.byType(CalendarScreen)));
    return container.read(calendarMonthProvider((year: 2026, month: 11))).requireValue.days;
  }

  /// Days whose counts differ between [before] and [after], with the change.
  Map<DateTime, (int, int, int, int)> diff(List<CalendarDay> before, List<CalendarDay> after) => {
    for (var i = 0; i < after.length; i++)
      if (before[i] != after[i])
        after[i].day: (
          after[i].taskCount - before[i].taskCount,
          after[i].dueCount - before[i].dueCount,
          after[i].routineCount - before[i].routineCount,
          after[i].scheduleCount - before[i].scheduleCount,
        ),
  };

  Finder inProgram(String text) => find.descendant(
    of: find.byKey(const ValueKey('calendar-section-schedule')),
    matching: find.text(text),
  );

  testWidgets('calendar: 25 Kasım -> Bu güne blok ekle -> title and times -> Kaydet -> back: '
      'the block is on the 25th only and only its month count rose', (tester) async {
    await pumpApp(tester);
    final home = otherHomeCalls();

    await openCalendar(tester);
    await tapAndSettle(tester, _cell(_d25));
    final before = shownMonth(tester);
    expect(inProgram('Doktor randevusu'), findsNothing);

    await tapAndSettle(tester, find.byKey(const ValueKey('calendar-day-add-block')));
    expect(find.byType(ScheduleEditScreen), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('schedule-start-date-text'))).data,
      '25.11.2026',
    );
    expect(
      tester.widget<ChoiceChip>(find.byKey(const ValueKey('schedule-type-once'))).selected,
      isTrue,
    );
    await tester.enterText(find.byKey(const ValueKey('schedule-title')), 'Doktor randevusu');
    await tester.pump();
    picker.answers.add(ScheduleTime.hm(14, 0));
    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-start-time')));
    picker.answers.add(ScheduleTime.hm(15, 0));
    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-end-time')));
    await tapAndSettle(tester, find.byKey(const ValueKey('schedule-save')));

    // One request, exactly as the backend expects it.
    final body = scheduleRepo.createBodies.single;
    expect(body['title'], 'Doktor randevusu');
    expect((body['start_time'], body['end_time']), ('14:00', '15:00'));
    expect(body['recurrence_type'], 'once');
    expect(body['start_date'], _d25);
    expect([body['days_of_week'], body['day_of_month'], body['interval_days']], [null, null, null]);

    // Back on the calendar, the 25th still selected.
    expect(find.byType(ScheduleEditScreen), findsNothing);
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(inProgram('Doktor randevusu'), findsOneWidget);
    expect(inProgram('14:00\u201315:00'), findsOneWidget);
    expect(diff(before, shownMonth(tester)), {_d25: (0, 0, 0, 1)});
    final handle = tester.ensureSemantics();
    final label = CalendarMonthGrid.countsLabel(shownMonth(tester)[_d25.day - 1]);
    expect(label, contains('program blok'));
    expect(find.bySemanticsLabel(label), findsWidgets);
    handle.dispose();

    await tapAndSettle(tester, _cell(_d26));
    expect(inProgram('Doktor randevusu'), findsNothing, reason: 'one-time: not on the 26th');
    await tapAndSettle(tester, _cell(_today));
    expect(inProgram('Doktor randevusu'), findsNothing, reason: 'not today either');

    await tapAndSettle(tester, find.byIcon(Icons.arrow_back));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(ScheduleCard), matching: find.text('Doktor randevusu')),
      findsNothing,
      reason: 'the Home card shows today only',
    );
    expect(otherHomeCalls(), home, reason: 'the other Home cards sent nothing new');
    expect(tester.takeException(), isNull);
  });

  testWidgets("Home quick add 'bugün 14:00-15:00 doktor': in the card and on the calendar on "
      'today only; only today\'s month count rose', (tester) async {
    await pumpApp(tester);
    final home = otherHomeCalls();
    await openCalendar(tester);
    final before = shownMonth(tester);
    await tapAndSettle(tester, find.byIcon(Icons.arrow_back));
    expect(find.byType(HomeScreen), findsOneWidget);

    final quickAdd = find.byKey(const ValueKey('schedule-quick-add'));
    await tester.ensureVisible(quickAdd);
    await tester.pump();
    await tester.enterText(quickAdd, 'bugün 14:00-15:00 doktor');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    final body = scheduleRepo.createBodies.single;
    expect(body['recurrence_type'], 'once');
    expect(body['start_date'], _today);
    expect(body['title'], 'doktor');
    final card = find.byType(ScheduleCard);
    expect(find.descendant(of: card, matching: find.text('doktor')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('14:00\u201315:00')), findsOneWidget);
    expect(otherHomeCalls(), home, reason: 'the other Home cards sent nothing new');

    await openCalendar(tester);
    expect(inProgram('doktor'), findsOneWidget, reason: 'today is selected');
    expect(diff(before, shownMonth(tester)), {_today: (0, 0, 0, 1)});
    await tapAndSettle(tester, _cell(DateTime(2026, 11, 22)));
    expect(inProgram('doktor'), findsNothing, reason: 'one-time: not tomorrow');
    await tapAndSettle(tester, _cell(DateTime(2026, 11, 20)));
    expect(inProgram('doktor'), findsNothing, reason: 'not before its day');

    await tapAndSettle(tester, find.byIcon(Icons.arrow_back));
    expect(otherHomeCalls(), home);
    expect(tester.takeException(), isNull);
  });
}
