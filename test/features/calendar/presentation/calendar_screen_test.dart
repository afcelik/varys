// /calendar page widgets: grid cells and alignment, day selection, month
// navigation (bounds disable the arrows), "Bugün", count marks and their
// Semantics, day sections and their order, the empty day, row taps opening
// the right route with the right extra, per-section loading/error (only that
// section), month loading/error, >=48 targets, wide/narrow layout, 2-line
// titles and midnight.

import 'dart:async';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/calendar/data/calendar_repository_impl.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';
import 'package:varys/features/calendar/presentation/calendar_providers.dart';
import 'package:varys/features/calendar/presentation/calendar_screen.dart';
import 'package:varys/features/calendar/presentation/widgets/calendar_day_list.dart';
import 'package:varys/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../schedule/fake_schedule_repository.dart';
import '../fake_calendar_repository.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _today = DateTime(2026, 11, 21); // a Saturday

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

final _longTitle = 'Ç' * 255;

Task _task(int id, String title, {DateTime? planned, DateTime? due, TaskStatus? status}) => Task(
  id: id,
  title: title,
  status: status ?? TaskStatus.todo,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  plannedDate: planned,
  dueDate: due,
);

final _tasks = [
  _task(10, 'Rapor yaz', planned: DateTime(2026, 11, 21)),
  _task(11, 'Sunum', planned: DateTime(2026, 11, 21, 15, 30), due: DateTime(2026, 11, 21)),
  _task(12, 'Fatura öde', due: DateTime(2026, 11, 21)),
  _task(13, 'Bitti', planned: DateTime(2026, 11, 21), status: TaskStatus.done),
  _task(14, 'Alışveriş', planned: DateTime(2026, 11, 3)),
];

/// Real GET /routines/day item (daily routine) with a given id and title.
RoutineDayItem _routine(int id, String title) => RoutineDayItem(
  id: id,
  title: title,
  recurrenceType: RecurrenceType.daily,
  startDate: DateTime(2026, 11, 1),
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  completed: false,
  currentStreak: 2,
  longestStreak: 5,
);

Finder _cell(DateTime d) => find.byKey(ValueKey('calendar-day-${formatDateForApi(d)}'));

void main() {
  late FakeCalendarRepository calendarRepo;
  late FakeScheduleRepository scheduleRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late List<RoutineDayItem> routines;
  late Object? pushedExtra;
  late String? pushedPath;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    calendarRepo = FakeCalendarRepository();
    scheduleRepo = FakeScheduleRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    routines = [_routine(1, 'Su iç'), _routine(2, 'Kitap oku')];
    pushedExtra = null;
    pushedPath = null;
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(_tasks));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => Right(_tasks));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((inv) async {
      final day = inv.positionalArguments.first as DateTime;
      return Right(day == _today ? routines : const <RoutineDayItem>[]);
    });
  });

  GoRouter makeRouter() {
    Widget edit(String path, GoRouterState state) {
      pushedPath = path;
      pushedExtra = state.extra;
      return Scaffold(body: Text('opened $path'));
    }

    return GoRouter(
      initialLocation: AppRouter.calendarPath,
      routes: [
        GoRoute(path: AppRouter.calendarPath, builder: (_, _) => const CalendarScreen()),
        GoRoute(
          path: AppRouter.scheduleEditPath,
          builder: (_, s) => edit(AppRouter.scheduleEditPath, s),
        ),
        GoRoute(path: AppRouter.tasksEditPath, builder: (_, s) => edit(AppRouter.tasksEditPath, s)),
        GoRoute(
          path: AppRouter.routinesEditPath,
          builder: (_, s) => edit(AppRouter.routinesEditPath, s),
        ),
      ],
    );
  }

  Future<void> pumpPage(WidgetTester tester, {double width = 600, bool settle = true}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      router: makeRouter(),
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        calendarRepositoryProvider.overrideWith((ref) async => calendarRepo),
        scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
      ],
    );
    if (settle) await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(CalendarScreen)));

  String monthTitle(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('calendar-month-title'))).data!;

  String dayTitle(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('calendar-day-title'))).data!;

  IconButton arrow(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(ValueKey(key)));

  Finder section(String id) => find.byKey(ValueKey('calendar-section-$id'));

  group('grid', () {
    testWidgets('Kasım 2026: 42 cells, Monday-first columns, today and selection', (tester) async {
      await pumpPage(tester);
      expect(monthTitle(tester), 'Kasım 2026');
      final cells = find.byWidgetPredicate(
        (w) => w is InkWell && '${w.key}'.contains('calendar-day-2'),
      );
      expect(cells, findsNWidgets(42));
      for (final name in ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']) {
        expect(find.text(name), findsOneWidget);
      }
      double x(Finder f) => tester.getCenter(f).dx;
      // 1 Kasım 2026 is a Sunday: last column, first row; 2 Kasım starts row 2.
      expect(x(_cell(DateTime(2026, 11, 1))), moreOrLessEquals(x(find.text('Paz')), epsilon: 0.5));
      expect(x(_cell(DateTime(2026, 11, 2))), moreOrLessEquals(x(find.text('Pzt')), epsilon: 0.5));
      expect(x(_cell(DateTime(2026, 10, 26))), moreOrLessEquals(x(find.text('Pzt')), epsilon: 0.5));
      expect(
        tester.getCenter(_cell(DateTime(2026, 11, 2))).dy,
        greaterThan(tester.getCenter(_cell(DateTime(2026, 11, 1))).dy),
      );
      // 30 Kasım (Monday) and 6 Aralık (Sunday) share the last row.
      expect(
        tester.getCenter(_cell(DateTime(2026, 12, 6))).dy,
        tester.getCenter(_cell(DateTime(2026, 11, 30))).dy,
      );
      expect(x(_cell(DateTime(2026, 12, 6))), moreOrLessEquals(x(find.text('Paz')), epsilon: 0.5));
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('21 Kasım, bugün'), findsOneWidget);
      expect(
        tester.getSemantics(_cell(_today)),
        matchesSemantics(
          label: '21 Kasım, bugün',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
          children: [matchesSemantics(label: '2 görev, 0 rutin, 2 program blok, 1 bitiş')],
        ),
      );
      handle.dispose();
      expect(dayTitle(tester), 'Cumartesi, 21 Kasım');
      expect(calendarRepo.requests, [(year: 2026, month: 11)]);
    });

    testWidgets('count marks: one shape per kind, Semantics labels, empty day has none', (
      tester,
    ) async {
      await pumpPage(tester);
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('2 görev, 0 rutin, 2 program blok, 1 bitiş'), findsOneWidget);
      expect(find.bySemanticsLabel('0 görev, 1 rutin, 0 program blok'), findsNWidgets(4));
      expect(find.bySemanticsLabel('0 görev, 0 rutin, 0 program blok, 1 bitiş'), findsOneWidget);
      expect(find.bySemanticsLabel('0 görev, 1 rutin, 1 program blok, 1 bitiş'), findsOneWidget);
      handle.dispose();

      expect(find.byKey(const ValueKey('calendar-mark-task-2026-11-21')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-mark-routine-2026-11-21')), findsNothing);
      expect(find.byKey(const ValueKey('calendar-mark-schedule-2026-11-21')), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byKey(const ValueKey('calendar-mark-task-2026-11-21'))).icon,
        Icons.circle,
      );
      expect(
        tester.widget<Icon>(find.byKey(const ValueKey('calendar-mark-schedule-2026-11-21'))).icon,
        Icons.change_history,
      );
      expect(
        tester.widget<Icon>(find.byKey(const ValueKey('calendar-mark-routine-2026-11-02'))).icon,
        Icons.square,
      );
      // Due-only day (5th) still shows the task mark.
      expect(find.byKey(const ValueKey('calendar-mark-task-2026-11-05')), findsOneWidget);
      // Empty day and faded cells: no marks.
      expect(find.byKey(const ValueKey('calendar-marks-2026-11-06')), findsNothing);
      expect(find.byKey(const ValueKey('calendar-marks-2026-12-01')), findsNothing);
      expect(find.byKey(const ValueKey('calendar-marks-2026-10-26')), findsNothing);
    });

    testWidgets('tapping a day selects it; a faded next-month day shows that month', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.tap(_cell(DateTime(2026, 11, 3)));
      await tester.pumpAndSettle();
      expect(dayTitle(tester), 'Salı, 3 Kasım');
      expect(monthTitle(tester), 'Kasım 2026');
      final view = containerOf(tester).read(calendarViewProvider);
      expect(view.selectedDay, DateTime(2026, 11, 3));
      expect(find.byKey(const ValueKey('calendar-row-task-14')), findsOneWidget);

      await tester.tap(_cell(DateTime(2026, 12, 1)));
      await tester.pumpAndSettle();
      expect(monthTitle(tester), 'Aralık 2026');
      expect(dayTitle(tester), 'Salı, 1 Aralık');
      expect(calendarRepo.requests.last, (year: 2026, month: 12));
    });

    testWidgets('arrows move one month; "Bugün" returns to today', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-next')));
      await tester.pumpAndSettle();
      expect(monthTitle(tester), 'Aralık 2026');
      expect(dayTitle(tester), 'Cumartesi, 21 Kasım', reason: 'arrows keep the selected day');
      await tester.tap(find.byKey(const ValueKey('calendar-prev')));
      await tester.tap(find.byKey(const ValueKey('calendar-prev')));
      await tester.pumpAndSettle();
      expect(monthTitle(tester), 'Ekim 2026');
      await tester.tap(_cell(DateTime(2026, 10, 7)));
      await tester.pumpAndSettle();
      expect(dayTitle(tester), 'Çarşamba, 7 Ekim');

      await tester.tap(find.text(CalendarScreen.todayText));
      await tester.pumpAndSettle();
      expect(monthTitle(tester), 'Kasım 2026');
      expect(dayTitle(tester), 'Cumartesi, 21 Kasım');
      expect(arrow(tester, 'calendar-prev').tooltip, 'Önceki ay');
      expect(arrow(tester, 'calendar-next').tooltip, 'Sonraki ay');
    });

    testWidgets('bounds: arrows are disabled on 2100-12 and 2000-01', (tester) async {
      await pumpPage(tester);
      containerOf(tester).read(calendarViewProvider.notifier).selectDay(DateTime(2100, 12, 31));
      await tester.pumpAndSettle();
      expect(monthTitle(tester), 'Aralık 2100');
      expect(arrow(tester, 'calendar-next').onPressed, isNull);
      expect(arrow(tester, 'calendar-prev').onPressed, isNotNull);
      // The trailing 2101 cells cannot be selected.
      expect(tester.widget<InkWell>(_cell(DateTime(2101, 1, 1))).onTap, isNull);

      containerOf(tester).read(calendarViewProvider.notifier).selectDay(DateTime(2000, 1, 1));
      await tester.pumpAndSettle();
      expect(monthTitle(tester), 'Ocak 2000');
      expect(arrow(tester, 'calendar-prev').onPressed, isNull);
      expect(arrow(tester, 'calendar-next').onPressed, isNotNull);
      expect(tester.widget<InkWell>(_cell(DateTime(1999, 12, 31))).onTap, isNull);
    });

    testWidgets('midnight: the today frame moves and an unpicked day follows', (tester) async {
      await pumpPage(tester);
      containerOf(tester).read(todayProvider.notifier).syncDate(DateTime(2026, 11, 22, 0, 0, 3));
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('22 Kasım, bugün'), findsOneWidget);
      expect(find.bySemanticsLabel('21 Kasım, bugün'), findsNothing);
      handle.dispose();
      expect(dayTitle(tester), 'Pazar, 22 Kasım');
    });
  });

  group('month loading and error', () {
    testWidgets('first load: progress bar and skeleton marks, day numbers visible', (tester) async {
      final gate = Completer<Either<Failure, CalendarMonth>>();
      calendarRepo.onMonth = (_, _) => gate.future;
      await pumpPage(tester, settle: false);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('calendar-month-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-skeleton-2026-11-21')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-skeleton-2026-12-01')), findsNothing);
      expect(find.byKey(const ValueKey('calendar-day-number-2026-11-21')), findsOneWidget);
      gate.complete(Right(calendarMonthFixture()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-month-loading')), findsNothing);
      expect(find.byKey(const ValueKey('calendar-skeleton-2026-11-21')), findsNothing);
      expect(find.byKey(const ValueKey('calendar-marks-2026-11-21')), findsOneWidget);
    });

    testWidgets('error: userMessage and "Tekrar dene"; grid and day list still work', (
      tester,
    ) async {
      calendarRepo.failure = _serverError;
      await pumpPage(tester);
      expect(find.byKey(const ValueKey('calendar-month-error')), findsOneWidget);
      expect(find.text(_serverError.userMessage), findsOneWidget);
      expect(_cell(_today), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-schedule-6')), findsOneWidget);

      calendarRepo.failure = null;
      await tester.tap(find.byKey(const ValueKey('calendar-month-retry')));
      await tester.pumpAndSettle();
      expect(calendarRepo.requests, hasLength(2));
      expect(find.byKey(const ValueKey('calendar-month-error')), findsNothing);
      expect(find.byKey(const ValueKey('calendar-marks-2026-11-21')), findsOneWidget);
    });

    testWidgets('a failed refresh keeps the old marks and shows the error', (tester) async {
      await pumpPage(tester);
      calendarRepo.failure = _serverError;
      containerOf(tester).invalidate(calendarMonthProvider((year: 2026, month: 11)));
      // The rebuild starts the request in the next frame; its answer needs one more pump.
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-month-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-marks-2026-11-21')), findsOneWidget);
    });
  });

  group('day list', () {
    testWidgets('sections in fixed order with their rows; done tasks left out', (tester) async {
      await pumpPage(tester);
      final ids = ['schedule', 'routines', 'tasks', 'due'];
      final tops = [for (final id in ids) tester.getTopLeft(section(id)).dy];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(
        [
          for (final id in ids)
            tester.widget<Text>(find.byKey(ValueKey('calendar-section-title-$id'))).data,
        ],
        ['Program', 'Rutinler', 'Görevler', 'Bitiş tarihi bu gün'],
      );
      // Schedule rows by start time (Saturday 21: daily blocks 6, 1, 3, 7).
      final blockRows = [6, 1, 3, 7].map((id) => find.byKey(ValueKey('calendar-row-schedule-$id')));
      final blockTops = [for (final r in blockRows) tester.getTopLeft(r).dy];
      expect(blockTops, orderedEquals([...blockTops]..sort()));
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('calendar-row-subtitle-schedule-1'))).data,
        formatTimeRange(ScheduleTime.parse('06:30'), ScheduleTime.parse('07:15')),
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('calendar-row-subtitle-routine-1'))).data,
        'Her gün',
      );
      expect(find.byKey(const ValueKey('calendar-row-task-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-task-11')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-task-13')), findsNothing, reason: 'done');
      expect(find.byKey(const ValueKey('calendar-row-due-11')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-due-12')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-day-empty')), findsNothing);
    });

    testWidgets('empty sections are hidden; an all-empty day says so', (tester) async {
      await pumpPage(tester);
      await tester.tap(_cell(DateTime(2026, 11, 3)));
      await tester.pumpAndSettle();
      // 3 Kasım (Tuesday): daily blocks and one planned task; no routines, nothing due.
      expect(section('schedule'), findsOneWidget);
      expect(section('tasks'), findsOneWidget);
      expect(section('routines'), findsNothing);
      expect(section('due'), findsNothing);

      // 1 Kasım: blocks start on the 2nd, no routines, no tasks.
      await tester.tap(_cell(DateTime(2026, 11, 1)));
      await tester.pumpAndSettle();
      expect(find.text(CalendarDayList.emptyText), findsOneWidget);
      for (final id in ['schedule', 'routines', 'tasks', 'due']) {
        expect(section(id), findsNothing);
      }
    });

    testWidgets('row taps open the edit route with the record as extra', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const ValueKey('calendar-row-schedule-3')));
      await tester.pumpAndSettle();
      expect(pushedPath, AppRouter.scheduleEditPath);
      expect((pushedExtra! as ScheduleBlock).id, 3);
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendar-row-task-10')));
      await tester.pumpAndSettle();
      expect(pushedPath, AppRouter.tasksEditPath);
      expect(pushedExtra, _tasks.first);
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendar-row-due-12')));
      await tester.pumpAndSettle();
      expect(pushedPath, AppRouter.tasksEditPath);
      expect((pushedExtra! as Task).id, 12);
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('calendar-row-routine-2')));
      await tester.pumpAndSettle();
      expect(pushedPath, AppRouter.routinesEditPath);
      final routine = pushedExtra! as Routine;
      expect(
        (routine.id, routine.title, routine.recurrenceType),
        (2, 'Kitap oku', RecurrenceType.daily),
      );
      expect(routine.startDate, DateTime(2026, 11, 1));
    });

    testWidgets('schedule error affects only that section; its retry reloads only it', (
      tester,
    ) async {
      scheduleRepo.dayFailure = _serverError;
      await pumpPage(tester);
      expect(find.byKey(const ValueKey('calendar-section-error-schedule')), findsOneWidget);
      expect(find.text(_serverError.userMessage), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-routine-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-task-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-due-12')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-marks-2026-11-21')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-month-error')), findsNothing);

      scheduleRepo.dayFailure = null;
      await tester.tap(find.byKey(const ValueKey('calendar-section-retry-schedule')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-row-schedule-6')), findsOneWidget);
      expect(scheduleRepo.dayCalls, 2);
      verify(() => routineRepo.getRoutinesForDay(_today)).called(1);
      expect(calendarRepo.requests, hasLength(1));
    });

    testWidgets('routine error affects only the routines section', (tester) async {
      when(
        () => routineRepo.getRoutinesForDay(any()),
      ).thenAnswer((_) async => const Left(_serverError));
      await pumpPage(tester);
      expect(find.byKey(const ValueKey('calendar-section-error-routines')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-schedule-6')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-task-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-section-error-schedule')), findsNothing);

      when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(routines));
      await tester.tap(find.byKey(const ValueKey('calendar-section-retry-routines')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-row-routine-1')), findsOneWidget);
      expect(scheduleRepo.dayCalls, 1);
      expect(calendarRepo.requests, hasLength(1));
    });

    testWidgets('task list error affects only the two task sections', (tester) async {
      when(
        () => taskRepo.getTasksByFilter(any()),
      ).thenAnswer((_) async => const Left(_serverError));
      await pumpPage(tester);
      expect(find.byKey(const ValueKey('calendar-section-error-tasks')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-section-error-due')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-schedule-6')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-routine-1')), findsOneWidget);

      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(_tasks));
      await tester.tap(find.byKey(const ValueKey('calendar-section-retry-tasks')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-row-task-10')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-due-12')), findsOneWidget);
      expect(scheduleRepo.dayCalls, 1);
    });

    testWidgets('a loading section shows its own spinner; others are drawn', (tester) async {
      final gate = Completer<Either<Failure, List<ScheduleBlock>>>();
      scheduleRepo.onDay = (_) => gate.future;
      await pumpPage(tester, settle: false);
      for (var i = 0; i < 5; i++) {
        await tester.pump();
      }
      expect(find.byKey(const ValueKey('calendar-section-loading-schedule')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-routine-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-row-task-10')), findsOneWidget);
      gate.complete(Right(scheduleDayFixture()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('calendar-section-loading-schedule')), findsNothing);
    });

    testWidgets('a 255-character unbroken title is cut at 2 lines', (tester) async {
      when(
        () => taskRepo.getTasksByFilter(any()),
      ).thenAnswer((_) async => Right([_task(20, _longTitle, planned: _today)]));
      await pumpPage(tester, width: 360);
      final title = find.byKey(const ValueKey('calendar-row-title-task-20'));
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.didExceedMaxLines, isTrue);
      final oneLine = TextPainter(
        text: TextSpan(text: 'Ağ', style: (paragraph.text as TextSpan).style),
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      final lines = (tester.getSize(title).height / oneLine.height).round();
      oneLine.dispose();
      expect(lines, 2);
    });
  });

  group('targets and layout', () {
    testWidgets('every tap target is at least 48x48', (tester) async {
      await pumpPage(tester, width: 360);
      void atLeast48(Finder f, String what) {
        final size = tester.getSize(f);
        expect(size.width, greaterThanOrEqualTo(48), reason: what);
        expect(size.height, greaterThanOrEqualTo(48), reason: what);
      }

      atLeast48(find.byKey(const ValueKey('calendar-prev')), 'prev');
      atLeast48(find.byKey(const ValueKey('calendar-next')), 'next');
      atLeast48(find.byKey(const ValueKey('calendar-today')), 'Bugün');
      atLeast48(_cell(_today), 'today cell');
      atLeast48(_cell(DateTime(2026, 10, 26)), 'faded cell');
      atLeast48(find.byKey(const ValueKey('calendar-row-schedule-6')), 'block row');
      atLeast48(find.byKey(const ValueKey('calendar-row-routine-1')), 'routine row');
      atLeast48(find.byKey(const ValueKey('calendar-row-task-10')), 'task row');
      atLeast48(find.byKey(const ValueKey('calendar-row-due-12')), 'due row');
    });

    testWidgets('>= 900 wide: grid left, list right', (tester) async {
      await pumpPage(tester, width: 1000);
      expect(find.byKey(const ValueKey('calendar-wide')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-narrow')), findsNothing);
      final grid = tester.getRect(find.byKey(const ValueKey('calendar-grid')));
      final list = tester.getRect(find.byKey(const ValueKey('calendar-day-title')));
      expect(list.left, greaterThan(grid.right));
      expect(list.top, lessThan(grid.bottom));
    });

    testWidgets('narrow: grid on top, list below', (tester) async {
      await pumpPage(tester, width: 899);
      expect(find.byKey(const ValueKey('calendar-narrow')), findsOneWidget);
      expect(find.byKey(const ValueKey('calendar-wide')), findsNothing);
      final grid = tester.getRect(find.byKey(const ValueKey('calendar-grid')));
      final list = tester.getRect(find.byKey(const ValueKey('calendar-day-title')));
      expect(list.top, greaterThan(grid.bottom));
    });

    testWidgets('the counts label helper matches the agreed text', (tester) async {
      final day = CalendarDay(
        day: _today,
        taskCount: 3,
        dueCount: 0,
        routineCount: 1,
        scheduleCount: 4,
      );
      expect(CalendarMonthGrid.countsLabel(day), '3 görev, 1 rutin, 4 program blok');
      expect(
        CalendarMonthGrid.countsLabel(day.copyWith(dueCount: 2)),
        '3 görev, 1 rutin, 4 program blok, 2 bitiş',
      );
    });
  });
}
