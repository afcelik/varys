// Overflow matrix for /calendar: 8 window widths x text scale 1.0 and 1.5,
// every state: filled (every day with all count kinds; 9 records in each day
// section, one with an unbroken 255-character title and the longest
// recurrence summary), empty month and empty day, loading (month and every
// section), month error, section errors, and months of 4, 5 and 6 rows. Each
// test checks takeException, drawn line counts of maxLines texts (a growing
// row throws nothing), 48x48 tap targets and the wide/narrow layout.
// pumpAndSettle is never used.

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
import 'package:varys/features/calendar/domain/calendar_grid.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';
import 'package:varys/features/calendar/presentation/calendar_providers.dart';
import 'package:varys/features/calendar/presentation/calendar_screen.dart';
import 'package:varys/features/calendar/presentation/widgets/calendar_day_list.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../schedule/fake_schedule_repository.dart';
import '../fake_calendar_repository.dart';
import '../fake_task_server.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _textScales = [1.0, 1.5];
const _height = 900.0;

final _today = DateTime(2026, 11, 21);
final _long = 'Ş' * 255;
const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

/// Every day of the month with every count kind (multi-digit counts).
CalendarMonth _busyMonth(int year, int month) => CalendarMonth(
  year: year,
  month: month,
  days: [
    for (final c in monthGrid(year, month).where((c) => c.inMonth))
      CalendarDay(day: c.day, taskCount: 12, dueCount: 9, routineCount: 10, scheduleCount: 11),
  ],
);

/// 9 daily blocks from 2026-11-01: 00:00-23:59, the long title first.
List<ScheduleBlock> _blocks() {
  final base = scheduleListFixture().first;
  return [
    for (var i = 0; i < 9; i++)
      base.copyWith(
        id: 100 + i,
        title: i == 0 ? _long : 'Blok ${i + 1} için oldukça uzun bir başlık metni',
        startTime: ScheduleTime(i * 60),
        endTime: ScheduleTime(i == 0 ? 1439 : i * 60 + 45),
        recurrenceType: RecurrenceType.daily,
        startDate: DateTime(2026, 11, 1),
      ),
  ];
}

/// 9 routines; the first has the long title and the longest summary.
List<RoutineDayItem> _routines() => [
  for (var i = 0; i < 9; i++)
    RoutineDayItem(
      id: 200 + i,
      title: i == 0 ? _long : 'Rutin ${i + 1} için uzun bir başlık',
      recurrenceType: i == 0 ? RecurrenceType.weekly : RecurrenceType.daily,
      daysOfWeek: i == 0 ? const [0, 1, 2, 3, 4, 5, 6] : null,
      startDate: DateTime(2026, 11, 1),
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      completed: i.isEven,
      currentStreak: 12,
      longestStreak: 30,
    ),
];

/// 9 tasks planned today and 9 due today; the first of each has the long title.
List<Task> _tasks() => [
  for (var i = 0; i < 9; i++)
    Task(
      id: 300 + i,
      title: i == 0 ? _long : 'Görev ${i + 1} için oldukça uzun bir başlık metni',
      status: TaskStatus.todo,
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      plannedDate: _today,
    ),
  for (var i = 0; i < 9; i++)
    Task(
      id: 400 + i,
      title: i == 0 ? _long : 'Bitiş ${i + 1} için oldukça uzun bir başlık metni',
      status: TaskStatus.inProgress,
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      dueDate: DateTime(2026, 11, 21, 18),
    ),
];

void main() {
  late FakeCalendarRepository calendarRepo;
  late FakeScheduleRepository scheduleRepo;
  late FakeTaskServer taskServer;
  late _MockRoutineRepository routineRepo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    calendarRepo = FakeCalendarRepository(monthFor: _busyMonth);
    scheduleRepo = FakeScheduleRepository(_blocks());
    taskServer = FakeTaskServer(_tasks());
    routineRepo = _MockRoutineRepository();
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(_routines()));
  });

  Future<void> steps(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpAt(WidgetTester tester, double width, double scale, {bool wait = true}) async {
    tester.view.physicalSize = Size(width, _height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRouter.calendarPath,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.calendarPath, builder: (_, _) => const CalendarScreen()),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      textScale: scale,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        calendarRepositoryProvider.overrideWith((ref) async => calendarRepo),
        scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskServer),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
      ],
    );
    if (wait) await steps(tester);
  }

  /// Lines the text at [finder] really draws ('Ağ' line-height reference).
  int drawnLines(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final oneLine = TextPainter(
      text: TextSpan(text: 'Ağ', style: (paragraph.text as TextSpan).style),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    final lines = (tester.getSize(finder).height / oneLine.height).round();
    oneLine.dispose();
    return lines;
  }

  void expectLines(WidgetTester tester, Finder f, int max, String what, {int? exactly}) {
    expect(f, findsOneWidget, reason: what);
    final lines = drawnLines(tester, f);
    if (exactly != null) {
      expect(lines, exactly, reason: '$what lines');
    } else {
      expect(lines, inInclusiveRange(1, max), reason: '$what lines');
    }
  }

  void expectTarget(WidgetTester tester, Finder f, String what) {
    expect(f, findsOneWidget, reason: what);
    final size = tester.getSize(f);
    expect(size.width, greaterThanOrEqualTo(48), reason: '$what width');
    expect(size.height, greaterThanOrEqualTo(48), reason: '$what height');
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  /// Header, weekday row and every cell of [year]/[month]: one-line texts,
  /// 48x48 cells and arrows, the expected number of rows.
  void expectGrid(WidgetTester tester, String label, int year, int month, {required int rows}) {
    expectLines(tester, key('calendar-month-title'), 1, '$label month title', exactly: 1);
    for (final name in weekdayShortNames) {
      expectLines(tester, key('calendar-weekday-$name'), 1, '$label $name', exactly: 1);
    }
    final cells = monthGrid(year, month);
    expect(cells.length, rows * 7, reason: label);
    final tops = <double>{};
    for (final c in cells) {
      final id = formatDateForApi(c.day);
      expectTarget(tester, key('calendar-day-$id'), '$label cell $id');
      expectLines(tester, key('calendar-day-number-$id'), 1, '$label number $id', exactly: 1);
      tops.add(tester.getTopLeft(key('calendar-day-$id')).dy);
    }
    expect(tops, hasLength(rows), reason: '$label rows');
    expectTarget(tester, key('calendar-prev'), '$label prev');
    expectTarget(tester, key('calendar-next'), '$label next');
    expectTarget(tester, key('calendar-today'), '$label Bugün');
  }

  void expectLayout(WidgetTester tester, double width, String label) {
    final wide = width >= CalendarScreen.wideBreakpoint;
    expect(key(wide ? 'calendar-wide' : 'calendar-narrow'), findsOneWidget, reason: label);
    final grid = tester.getRect(key('calendar-grid'));
    final title = tester.getRect(key('calendar-day-title'));
    if (wide) {
      expect(title.left, greaterThan(grid.right), reason: '$label list right of grid');
    } else {
      expect(title.top, greaterThan(grid.bottom), reason: '$label list below grid');
    }
    expect(grid.width, lessThanOrEqualTo(CalendarScreen.gridMaxWidth), reason: label);
    expect(grid.right, lessThanOrEqualTo(width), reason: label);
  }

  void expectDayTitle(WidgetTester tester, String label) =>
      expectLines(tester, key('calendar-day-title'), 2, '$label day title');

  for (final width in _widths) {
    for (final scale in _textScales) {
      final label = '${width.toInt()}px x$scale';

      group(label, () {
        testWidgets('filled: busy month, 9 records per section, 255-char titles', (tester) async {
          await pumpAt(tester, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expectGrid(tester, label, 2026, 11, rows: 6);
          expectLayout(tester, width, label);
          expectDayTitle(tester, label);
          for (final c in monthGrid(2026, 11).where((c) => c.inMonth)) {
            final id = formatDateForApi(c.day);
            for (final kind in ['task', 'routine', 'schedule']) {
              expect(key('calendar-mark-$kind-$id'), findsOneWidget, reason: '$label $kind $id');
            }
          }
          for (final id in ['schedule', 'routines', 'tasks', 'due']) {
            expectLines(tester, key('calendar-section-title-$id'), 1, '$label $id', exactly: 1);
          }
          final rows = <(String, int)>[
            for (var i = 0; i < 9; i++) ('schedule', 100 + i),
            for (var i = 0; i < 9; i++) ('routine', 200 + i),
            for (var i = 0; i < 9; i++) ('task', 300 + i),
            for (var i = 0; i < 9; i++) ('due', 400 + i),
          ];
          for (final (kind, id) in rows) {
            final what = '$label $kind $id';
            expectTarget(tester, key('calendar-row-$kind-$id'), what);
            final title = key('calendar-row-title-$kind-$id');
            final isLong = id % 100 == 0;
            expectLines(tester, title, 2, what, exactly: isLong ? 2 : null);
            if (isLong) {
              expect(
                tester.renderObject<RenderParagraph>(title).didExceedMaxLines,
                isTrue,
                reason: '$what cut with ellipsis',
              );
            }
            if (kind == 'schedule' || kind == 'routine') {
              expectLines(tester, key('calendar-row-subtitle-$kind-$id'), 1, what, exactly: 1);
            }
          }
          expect(
            tester.widget<Text>(key('calendar-row-subtitle-routine-200')).data,
            'Pzt, Sal, Çar, Per, Cum, Cmt, Paz',
          );
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('empty month and empty day', (tester) async {
          calendarRepo.monthFor = emptyCalendarMonth;
          scheduleRepo.server = [];
          taskServer.server = [];
          when(
            () => routineRepo.getRoutinesForDay(any()),
          ).thenAnswer((_) async => const Right(<RoutineDayItem>[]));
          await pumpAt(tester, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expectGrid(tester, label, 2026, 11, rows: 6);
          expectLayout(tester, width, label);
          expectDayTitle(tester, label);
          expect(
            find.byWidgetPredicate((w) => '${w.key}'.contains('calendar-marks-')),
            findsNothing,
          );
          expect(find.text(CalendarDayList.emptyText), findsOneWidget);
          expect(key('calendar-section-schedule'), findsNothing);
        });

        testWidgets('loading: month skeleton and every section spinner', (tester) async {
          final month = Completer<Either<Failure, CalendarMonth>>();
          final day = Completer<Either<Failure, List<ScheduleBlock>>>();
          final routinesGate = Completer<Either<Failure, List<RoutineDayItem>>>();
          calendarRepo.onMonth = (_, _) => month.future;
          scheduleRepo.onDay = (_) => day.future;
          when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) => routinesGate.future);
          final tasksGate = taskServer.listGate = Completer<void>();
          await pumpAt(tester, width, scale, wait: false);
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull, reason: label);
          expect(key('calendar-month-loading'), findsOneWidget, reason: label);
          expect(key('calendar-skeleton-2026-11-21'), findsOneWidget, reason: label);
          expectGrid(tester, label, 2026, 11, rows: 6);
          expectLayout(tester, width, label);
          expectDayTitle(tester, label);
          expect(key('calendar-section-loading-schedule'), findsOneWidget, reason: label);
          expect(key('calendar-section-loading-routines'), findsOneWidget, reason: label);
          expect(key('calendar-section-loading-tasks'), findsOneWidget, reason: label);
          expect(key('calendar-section-loading-due'), findsOneWidget, reason: label);
          // Let the parked requests finish so nothing is left pending.
          month.complete(Right(_busyMonth(2026, 11)));
          day.complete(const Right([]));
          routinesGate.complete(const Right([]));
          tasksGate.complete();
          await steps(tester, 3);
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('month error: message and retry under the grid', (tester) async {
          calendarRepo.failure = _serverError;
          await pumpAt(tester, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expect(key('calendar-month-error'), findsOneWidget, reason: label);
          expect(find.text(_serverError.userMessage), findsOneWidget);
          expectTarget(tester, key('calendar-month-retry'), '$label month retry');
          expectGrid(tester, label, 2026, 11, rows: 6);
          expectLayout(tester, width, label);
          expect(key('calendar-row-schedule-100'), findsOneWidget, reason: 'the list still works');
        });

        testWidgets('section errors: each section with its own message and retry', (tester) async {
          scheduleRepo.dayFailure = _serverError;
          when(
            () => routineRepo.getRoutinesForDay(any()),
          ).thenAnswer((_) async => const Left(_serverError));
          await pumpAt(tester, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          for (final id in ['schedule', 'routines']) {
            expect(key('calendar-section-error-$id'), findsOneWidget, reason: '$label $id');
            expectTarget(tester, key('calendar-section-retry-$id'), '$label $id retry');
          }
          expect(key('calendar-row-task-300'), findsOneWidget, reason: '$label tasks drawn');
          expect(key('calendar-month-error'), findsNothing);
          expectGrid(tester, label, 2026, 11, rows: 6);
          expectLayout(tester, width, label);
        });

        for (final (year, month, rows) in [(2027, 2, 4), (2026, 12, 5), (2026, 3, 6)]) {
          testWidgets('$rows-row month ($year-$month)', (tester) async {
            await pumpAt(tester, width, scale);
            final container = ProviderScope.containerOf(
              tester.element(find.byType(CalendarScreen)),
            );
            container.read(calendarViewProvider.notifier).selectDay(DateTime(year, month, 10));
            await steps(tester);
            expect(tester.takeException(), isNull, reason: label);
            expectGrid(tester, label, year, month, rows: rows);
            expectLayout(tester, width, label);
            expectDayTitle(tester, label);
          });
        }
      });
    }
  }
}
