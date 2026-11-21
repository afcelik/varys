import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/calendar/domain/calendar_grid.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';
import 'package:varys/features/calendar/domain/calendar_repository.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';

import '../schedule/fake_schedule_repository.dart';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

/// Real GET /calendar/month?year=2026&month=11 (30 days; 21st: 2 planned,
/// 1 due, 0 routines, 2 blocks; 6th empty).
CalendarMonth calendarMonthFixture() =>
    CalendarMonth.fromJson(_read('calendar_month_2026_11.json'));

/// Real GET /calendar/month?year=2024&month=2 (leap year, 29 days).
CalendarMonth calendarLeapMonthFixture() =>
    CalendarMonth.fromJson(_read('calendar_month_2024_02.json'));

/// Every day of [year]/[month] with all counts 0 (the backend's empty month).
CalendarMonth emptyCalendarMonth(int year, int month) => CalendarMonth(
  year: year,
  month: month,
  days: [
    for (final c in monthGrid(year, month).where((c) => c.inMonth))
      CalendarDay(day: c.day, taskCount: 0, dueCount: 0, routineCount: 0, scheduleCount: 0),
  ],
);

/// The server's is_due for a recurrence on [day] (same rules as
/// [FakeScheduleRepository.isDue]: never before start_date; weekly uses
/// Monday=0; monthly clamps to the month's last day; interval counts from
/// start_date).
bool recurrenceIsDue({
  required RecurrenceType type,
  List<int>? daysOfWeek,
  int? dayOfMonth,
  int? intervalDays,
  required DateTime startDate,
  required DateTime day,
}) {
  final d = DateTime.utc(day.year, day.month, day.day);
  final start = DateTime.utc(startDate.year, startDate.month, startDate.day);
  if (d.isBefore(start)) return false;
  switch (type) {
    case RecurrenceType.daily:
      return true;
    case RecurrenceType.weekly:
      return (daysOfWeek ?? const []).contains(d.weekday - 1);
    case RecurrenceType.monthly:
      final lastDay = DateTime.utc(d.year, d.month + 1, 0).day;
      final target = dayOfMonth! < lastDay ? dayOfMonth : lastDay;
      return d.day == target;
    case RecurrenceType.interval:
      return d.difference(start).inDays % intervalDays! == 0;
  }
}

/// Whether routine [r] is scheduled on [day].
bool routineIsDue(RoutineDayItem r, DateTime day) => recurrenceIsDue(
  type: r.recurrenceType,
  daysOfWeek: r.daysOfWeek,
  dayOfMonth: r.dayOfMonth,
  intervalDays: r.intervalDays,
  startDate: r.startDate,
  day: day,
);

bool _sameDay(DateTime? a, DateTime b) =>
    a != null && a.year == b.year && a.month == b.month && a.day == b.day;

/// What the backend's month_summary returns for these server contents:
/// open (not done, not deleted) tasks counted on the date part of
/// planned_date / due_date; routines and blocks due on each day.
CalendarMonth computeCalendarMonth(
  int year,
  int month, {
  required Iterable<Task> tasks,
  required Iterable<RoutineDayItem> routines,
  required Iterable<ScheduleBlock> blocks,
}) {
  final open = tasks.where((t) => t.status != TaskStatus.done && t.deletedAt == null).toList();
  return CalendarMonth(
    year: year,
    month: month,
    days: [
      for (final c in monthGrid(year, month).where((c) => c.inMonth))
        CalendarDay(
          day: c.day,
          taskCount: open.where((t) => _sameDay(t.plannedDate, c.day)).length,
          dueCount: open.where((t) => _sameDay(t.dueDate, c.day)).length,
          routineCount: routines.where((r) => routineIsDue(r, c.day)).length,
          scheduleCount: blocks.where((b) => FakeScheduleRepository.isDue(b, c.day)).length,
        ),
    ],
  );
}

/// In-memory stand-in for [CalendarRepository]. Every request is recorded.
/// [monthFor] builds the answer (default: the real November 2026 fixture for
/// 2026-11, otherwise an empty month); [failure] replaces it; [onMonth]
/// replaces the whole answer (e.g. a parked Completer per call).
class FakeCalendarRepository implements CalendarRepository {
  FakeCalendarRepository({CalendarMonth Function(int year, int month)? monthFor})
    : monthFor = monthFor ?? _defaultMonth;

  static CalendarMonth _defaultMonth(int year, int month) =>
      (year == 2026 && month == 11) ? calendarMonthFixture() : emptyCalendarMonth(year, month);

  /// A server consistent with the other fakes: every answer is computed from
  /// their current contents ([computeCalendarMonth]).
  FakeCalendarRepository.consistent({
    required Iterable<Task> Function() tasks,
    required Iterable<RoutineDayItem> Function() routines,
    required Iterable<ScheduleBlock> Function() blocks,
  }) : monthFor = ((year, month) => computeCalendarMonth(
         year,
         month,
         tasks: tasks(),
         routines: routines(),
         blocks: blocks(),
       ));

  CalendarMonth Function(int year, int month) monthFor;
  Failure? failure;
  Future<Either<Failure, CalendarMonth>> Function(int year, int month)? onMonth;

  final requests = <YearMonth>[];

  @override
  Future<Either<Failure, CalendarMonth>> getMonth(int year, int month) async {
    requests.add((year: year, month: month));
    final hook = onMonth;
    if (hook != null) return hook(year, month);
    await Future<void>.delayed(Duration.zero);
    final f = failure;
    if (f != null) return Left(f);
    return Right(monthFor(year, month));
  }
}
