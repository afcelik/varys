// Calendar providers: month request per (year, month), stale answers never
// written, previous counts kept on refresh, the page view state (month
// navigation, bounds, day selection, midnight), and the one-time refresh of
// the open month after task, routine and schedule changes made through the
// real notifiers (no loop; toggles, title edits, filter changes and silent
// re-fetches send no month request).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/calendar/data/calendar_repository_impl.dart';
import 'package:varys/features/calendar/domain/calendar_grid.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';
import 'package:varys/features/calendar/presentation/calendar_providers.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routines_day_notifier.dart';
import 'package:varys/features/routines/presentation/routines_list_notifier.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';
import 'package:varys/features/schedule/presentation/schedule_list_notifier.dart';

import '../../schedule/fake_schedule_repository.dart';
import '../fake_calendar_repository.dart';
import '../fake_task_server.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

final _today = DateTime(2026, 11, 21);

/// Today fixed at [_today]; `syncDate` moves it like the midnight ticker.
class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

Future<void> _flush() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Task _task(int id, {DateTime? planned, DateTime? due, TaskStatus status = TaskStatus.todo}) => Task(
  id: id,
  title: 'Görev $id',
  status: status,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  plannedDate: planned,
  dueDate: due,
);

void main() {
  late FakeCalendarRepository calendarRepo;
  late FakeTaskServer taskRepo;
  late _MockRoutineRepository routineRepo;
  late FakeScheduleRepository scheduleRepo;
  late List<RoutineDayItem> dayRoutines;
  late Routine routine;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(RecurrenceType.daily);
    registerFallbackValue(const RoutineChanges());
  });

  setUp(() {
    calendarRepo = FakeCalendarRepository();
    taskRepo = FakeTaskServer([
      _task(1, planned: DateTime(2026, 11, 21)),
      _task(2, planned: DateTime(2026, 11, 21, 15, 30), due: DateTime(2026, 11, 21)),
      _task(3, due: DateTime(2026, 11, 30)),
      _task(4, planned: DateTime(2026, 11, 10), status: TaskStatus.done),
    ]);
    dayRoutines = (_read('routines_day.json') as List)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();
    routine = Routine.fromJson(_read('routine_created.json') as Map<String, dynamic>);
    routineRepo = _MockRoutineRepository();
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(dayRoutines));
    when(() => routineRepo.getRoutines()).thenAnswer((_) async => Right([routine]));
    when(
      () => routineRepo.createRoutine(
        title: any(named: 'title'),
        description: any(named: 'description'),
        recurrenceType: any(named: 'recurrenceType'),
        daysOfWeek: any(named: 'daysOfWeek'),
        dayOfMonth: any(named: 'dayOfMonth'),
        intervalDays: any(named: 'intervalDays'),
        startDate: any(named: 'startDate'),
      ),
    ).thenAnswer((_) async => Right(routine.copyWith(id: 50)));
    when(
      () => routineRepo.updateRoutine(any(), any()),
    ).thenAnswer((_) async => Right(routine.copyWith(title: 'Yeni')));
    when(() => routineRepo.deleteRoutine(any())).thenAnswer((_) async => const Right(null));
    when(() => routineRepo.markDone(any(), any())).thenAnswer((_) async => const Right(null));
    scheduleRepo = FakeScheduleRepository();

    container = ProviderContainer(
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        calendarRepositoryProvider.overrideWith((ref) async => calendarRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  YearMonth ym(int y, int m) => (year: y, month: m);

  group('calendarMonthProvider', () {
    test('requests the (year, month) argument once and exposes the real month', () async {
      container.listen(calendarMonthProvider(ym(2026, 11)), (_, _) {});
      await _flush();
      expect(calendarRepo.requests, [ym(2026, 11)]);
      final month = container.read(calendarMonthProvider(ym(2026, 11))).requireValue;
      expect((month.year, month.month, month.days.length), (2026, 11, 30));
      expect(month.days[20].taskCount, 2);

      container.listen(calendarMonthProvider(ym(2024, 2)), (_, _) {});
      await _flush();
      expect(calendarRepo.requests, [ym(2026, 11), ym(2024, 2)]);
    });

    test('a failure surfaces as the error (the Failure itself)', () async {
      calendarRepo.failure = FakeScheduleRepository.invalid;
      container.listen(calendarMonthProvider(ym(2026, 11)), (_, _) {});
      await _flush();
      expect(
        container.read(calendarMonthProvider(ym(2026, 11))).error,
        FakeScheduleRepository.invalid,
      );
    });

    test('refresh keeps the previous counts while the new request runs', () async {
      container.listen(calendarMonthProvider(ym(2026, 11)), (_, _) {});
      await _flush();
      final gate = Completer<Either<Failure, CalendarMonth>>();
      calendarRepo.onMonth = (_, _) => gate.future;
      container.invalidate(calendarMonthProvider(ym(2026, 11)));
      await _flush();
      final refreshing = container.read(calendarMonthProvider(ym(2026, 11)));
      expect(refreshing.isLoading, isTrue);
      expect(refreshing.requireValue.days[20].taskCount, 2, reason: 'old counts stay');

      gate.complete(Right(emptyCalendarMonth(2026, 11)));
      await _flush();
      final done = container.read(calendarMonthProvider(ym(2026, 11)));
      expect(done.isLoading, isFalse);
      expect(done.requireValue.days[20].taskCount, 0);
    });

    test('same month: an older request answering late never overwrites the newer one', () async {
      final gates = <Completer<Either<Failure, CalendarMonth>>>[];
      calendarRepo.onMonth = (_, _) {
        final gate = Completer<Either<Failure, CalendarMonth>>();
        gates.add(gate);
        return gate.future;
      };
      container.listen(calendarMonthProvider(ym(2026, 11)), (_, _) {});
      await _flush();
      container.invalidate(calendarMonthProvider(ym(2026, 11)));
      await _flush();
      expect(gates, hasLength(2));

      gates[1].complete(Right(calendarMonthFixture()));
      await _flush();
      gates[0].complete(Right(emptyCalendarMonth(2026, 11)));
      await _flush();
      expect(
        container.read(calendarMonthProvider(ym(2026, 11))).requireValue.days[20].taskCount,
        2,
      );
    });

    test('disposing while a request is in flight does not crash', () async {
      final gate = Completer<Either<Failure, CalendarMonth>>();
      calendarRepo.onMonth = (_, _) => gate.future;
      final sub = container.listen(calendarMonthProvider(ym(2026, 11)), (_, _) {});
      await _flush();
      sub.close();
      await _flush();
      expect(container.exists(calendarMonthProvider(ym(2026, 11))), isFalse);
      gate.complete(Right(calendarMonthFixture()));
      await _flush();
      container.dispose();
      container = ProviderContainer();
    });
  });

  group('calendarViewProvider + calendarVisibleMonthProvider', () {
    test('starts on today: month 2026-11, day 21, one request for that month', () async {
      container.listen(calendarVisibleMonthProvider, (_, _) {});
      final view = container.read(calendarViewProvider);
      expect(view.month, ym(2026, 11));
      expect(view.selectedDay, DateTime(2026, 11, 21));
      expect((view.dayPicked, view.monthChanged), (false, false));
      await _flush();
      expect(calendarRepo.requests, [ym(2026, 11)]);
      expect(container.read(calendarVisibleMonthProvider).requireValue.month, 11);
    });

    test('moving to another month makes exactly one new request; the day stays', () async {
      container.listen(calendarVisibleMonthProvider, (_, _) {});
      await _flush();
      container.read(calendarViewProvider.notifier).moveMonth(1);
      await _flush();
      expect(calendarRepo.requests, [ym(2026, 11), ym(2026, 12)]);
      final view = container.read(calendarViewProvider);
      expect(view.month, ym(2026, 12));
      expect(view.selectedDay, DateTime(2026, 11, 21));
      expect(container.read(calendarVisibleMonthProvider).requireValue.month, 12);

      container.read(calendarViewProvider.notifier).moveMonth(-2);
      await _flush();
      expect(calendarRepo.requests.last, ym(2026, 10));
      expect(calendarRepo.requests, hasLength(3));
    });

    test('A answering after the switch to B is never shown for B', () async {
      final gates = <YearMonth, Completer<Either<Failure, CalendarMonth>>>{};
      calendarRepo.onMonth = (y, m) => (gates[ym(y, m)] = Completer()).future;
      container.listen(calendarVisibleMonthProvider, (_, _) {});
      await _flush();
      container.read(calendarViewProvider.notifier).moveMonth(1);
      await _flush();
      gates[ym(2026, 12)]!.complete(Right(emptyCalendarMonth(2026, 12)));
      await _flush();
      gates[ym(2026, 11)]!.complete(Right(calendarMonthFixture()));
      await _flush();
      final shown = container.read(calendarVisibleMonthProvider).requireValue;
      expect((shown.year, shown.month), (2026, 12));
      expect(shown.days.every((d) => d.taskCount == 0), isTrue);
    });

    test('bounds: no move past 2100-12 or before 2000-01, no request', () async {
      final notifier = container.read(calendarViewProvider.notifier);
      container.listen(calendarVisibleMonthProvider, (_, _) {});
      notifier.selectDay(DateTime(2100, 12, 31));
      expect(container.read(calendarViewProvider).month, ym(2100, 12));
      expect(container.read(calendarViewProvider).canGoNext, isFalse);
      expect(container.read(calendarViewProvider).canGoPrevious, isTrue);
      await _flush();
      final before = calendarRepo.requests.length;
      notifier.moveMonth(1);
      await _flush();
      expect(container.read(calendarViewProvider).month, ym(2100, 12));
      expect(calendarRepo.requests, hasLength(before));

      notifier.selectDay(DateTime(2000, 1, 1));
      expect(container.read(calendarViewProvider).canGoPrevious, isFalse);
      notifier.moveMonth(-1);
      expect(container.read(calendarViewProvider).month, ym(2000, 1));
      notifier.selectDay(DateTime(1999, 12, 31)); // a faded cell outside the bounds
      expect(container.read(calendarViewProvider).selectedDay, DateTime(2000, 1, 1));
      expect(container.read(calendarViewProvider).month, ym(2000, 1));
    });

    test('a day of the next month (faded cell) shows that month and selects it', () {
      final notifier = container.read(calendarViewProvider.notifier);
      notifier.selectDay(DateTime(2026, 12, 3, 14)); // time part dropped
      final view = container.read(calendarViewProvider);
      expect(view.month, ym(2026, 12));
      expect(view.selectedDay, DateTime(2026, 12, 3));
      expect((view.dayPicked, view.monthChanged), (true, true));
    });

    test('"Bugün" returns to today and follows today again', () {
      final notifier = container.read(calendarViewProvider.notifier);
      notifier.moveMonth(5);
      notifier.selectDay(DateTime(2027, 4, 9));
      notifier.goToToday();
      expect(
        container.read(calendarViewProvider),
        CalendarView(month: ym(2026, 11), selectedDay: DateTime(2026, 11, 21)),
      );
    });

    test('midnight: an unpicked day and an unchanged month follow today', () async {
      container.listen(calendarVisibleMonthProvider, (_, _) {});
      await _flush();
      final today = container.read(todayProvider.notifier);
      today.syncDate(DateTime(2026, 11, 22, 0, 0, 5));
      expect(container.read(calendarViewProvider).selectedDay, DateTime(2026, 11, 22));
      today.syncDate(DateTime(2026, 12, 1, 0, 1));
      await _flush();
      final view = container.read(calendarViewProvider);
      expect(view.selectedDay, DateTime(2026, 12, 1));
      expect(view.month, ym(2026, 12));
      expect(calendarRepo.requests, [ym(2026, 11), ym(2026, 12)]);
    });

    test('midnight: a picked day and a changed month are kept', () {
      container.listen(calendarViewProvider, (_, _) {});
      final notifier = container.read(calendarViewProvider.notifier);
      notifier.selectDay(DateTime(2026, 11, 5));
      container.read(todayProvider.notifier).syncDate(DateTime(2026, 11, 22));
      expect(container.read(calendarViewProvider).selectedDay, DateTime(2026, 11, 5));
      expect(container.read(calendarViewProvider).month, ym(2026, 11));

      notifier.moveMonth(-1);
      container.read(todayProvider.notifier).syncDate(DateTime(2026, 12, 1));
      final view = container.read(calendarViewProvider);
      expect(view.month, ym(2026, 10));
      expect(view.selectedDay, DateTime(2026, 11, 5));
    });

    test('the view resets when the page closes (autoDispose)', () async {
      final sub = container.listen(calendarViewProvider, (_, _) {});
      container.read(calendarViewProvider.notifier).selectDay(DateTime(2026, 11, 2));
      sub.close();
      await _flush();
      expect(container.read(calendarViewProvider).selectedDay, DateTime(2026, 11, 21));
    });
  });

  group('calendarMonthSyncProvider (open month refreshed once after changes)', () {
    /// The open /calendar page: grid, sync, and the selected day's sections.
    Future<void> openPage() async {
      container.listen(calendarVisibleMonthProvider, (_, _) {});
      container.listen(calendarMonthSyncProvider, (_, _) {});
      container.listen(taskListNotifierProvider, (_, _) {});
      container.listen(routinesForDayProvider(_today), (_, _) {});
      container.listen(scheduleForDayProvider(_today), (_, _) {});
      await _flush();
      expect(calendarRepo.requests, [ym(2026, 11)]);
    }

    int monthRequests() => calendarRepo.requests.length;
    TaskListNotifier tasks() => container.read(taskListNotifierProvider.notifier);
    Task taskById(int id) => taskRepo.server.firstWhere((t) => t.id == id);

    test('marking a task done refreshes the month once (fingerprint changed)', () async {
      await openPage();
      expect(await tasks().toggleTaskCompletion(1), const Right<Failure, void>(null));
      await _flush();
      expect(monthRequests(), 2);
      // Undo is a change too: once more.
      await tasks().toggleTaskCompletion(1);
      await _flush();
      expect(monthRequests(), 3);
    });

    test('date edit: one refresh; the silent re-fetch after it adds none', () async {
      await openPage();
      final listCallsBefore = taskRepo.listCalls;
      final result = await tasks().updateTask(
        taskById(3),
        TaskChanges(plannedDate: PlanField.set(DateTime(2026, 11, 24))),
      );
      expect(result.isRight(), isTrue);
      await _flush();
      expect(taskRepo.listCalls, greaterThan(listCallsBefore), reason: 'silent re-fetch ran');
      expect(monthRequests(), 2);
    });

    test('title-only edit, project link and Planning filter change: no refresh', () async {
      await openPage();
      await tasks().updateTask(taskById(1), const TaskChanges(title: 'Yeni başlık'));
      await _flush();
      await tasks().updateTask(taskById(2), const TaskChanges(projectId: PlanField.set(7)));
      await _flush();
      expect(await tasks().changeFilter(TaskFilter.inProgress), const Right<Failure, void>(null));
      await _flush();
      expect(await tasks().changeFilter(TaskFilter.all), const Right<Failure, void>(null));
      await _flush();
      expect(monthRequests(), 1);
    });

    test('create and delete each refresh once', () async {
      await openPage();
      await tasks().addTask(TaskCreation.create(title: 'Yeni', plannedDate: DateTime(2026, 11, 2)));
      await _flush();
      expect(monthRequests(), 2);
      await tasks().deleteTask(1);
      await _flush();
      expect(monthRequests(), 3);
    });

    test('routine create / update / delete: one month request each', () async {
      await openPage();
      container.listen(routinesListProvider, (_, _) {});
      await _flush();
      final routines = container.read(routinesListProvider.notifier);
      await routines.createRoutine(
        title: 'Yeni',
        recurrenceType: RecurrenceType.daily,
        startDate: DateTime(2026, 11, 1),
      );
      await _flush();
      expect(monthRequests(), 2);
      await routines.updateRoutine(routine.id, const RoutineChanges(title: PlanField.set('Yeni')));
      await _flush();
      expect(monthRequests(), 3);
      await routines.deleteRoutine(routine.id);
      await _flush();
      expect(monthRequests(), 4);
    });

    test('routine completion toggle: no month request', () async {
      await openPage();
      final result = await container
          .read(routinesForDayProvider(_today).notifier)
          .toggle(dayRoutines[1].id);
      expect(result.isRight(), isTrue);
      await _flush();
      verify(() => routineRepo.markDone(dayRoutines[1].id, _today)).called(1);
      verify(() => routineRepo.getRoutinesForDay(_today)).called(2); // load + silent refresh
      expect(monthRequests(), 1);
    });

    test('schedule block create / update / delete: one month request each', () async {
      await openPage();
      container.listen(scheduleBlocksProvider, (_, _) {});
      await _flush();
      final blocks = container.read(scheduleBlocksProvider.notifier);
      final created = await blocks.createBlock(
        title: 'Okuma',
        startTime: ScheduleTime.parse('20:00'),
        endTime: ScheduleTime.parse('21:00'),
        recurrenceType: RecurrenceType.daily,
        startDate: DateTime(2026, 11, 21),
      );
      final id = created.fold((f) => fail('$f'), (b) => b.id);
      await _flush();
      expect(monthRequests(), 2);
      await blocks.updateBlock(id, const ScheduleChanges(title: PlanField.set('Okuma 2')));
      await _flush();
      expect(monthRequests(), 3);
      await blocks.deleteBlock(id);
      await _flush();
      expect(monthRequests(), 4);
    });

    test('no loop: a month refresh triggers nothing else, and it settles', () async {
      await openPage();
      final taskCalls = taskRepo.listCalls;
      final dayCalls = scheduleRepo.dayCalls;
      container.invalidate(calendarMonthProvider(ym(2026, 11)));
      await _flush();
      await _flush();
      expect(monthRequests(), 2);
      expect(taskRepo.listCalls, taskCalls);
      expect(scheduleRepo.dayCalls, dayCalls);
      verify(() => routineRepo.getRoutinesForDay(_today)).called(1);

      await tasks().toggleTaskCompletion(2);
      await _flush();
      await _flush();
      expect(monthRequests(), 3, reason: 'one change, one request, then quiet');
    });

    test('after a month change the new month is the one refreshed', () async {
      await openPage();
      container.read(calendarViewProvider.notifier).moveMonth(1);
      await _flush();
      expect(calendarRepo.requests, [ym(2026, 11), ym(2026, 12)]);
      await tasks().toggleTaskCompletion(1);
      await _flush();
      expect(calendarRepo.requests, [ym(2026, 11), ym(2026, 12), ym(2026, 12)]);
    });
  });
}
