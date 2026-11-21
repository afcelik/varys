import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/domain/schedule_repository.dart';

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// Real GET /schedule: ids 6, 1, 2, 3, 7, 4, 5 (start time, then id). 6 is
/// 00:00-23:59 daily; 1 daily 06:30-07:15; 2 weekly Pzt/Çar/Cum 08:30-09:00
/// with no description; 3 daily 09:00-10:30 with an unbroken 255-character
/// title; 7 daily 09:00-09:45; 4 monthly (15th) 12:00-12:30; 5 every 3 days
/// 18:00-18:15. All start on 2026-11-02 (a Monday).
List<ScheduleBlock> scheduleListFixture() => (_read('schedule_list.json') as List)
    .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
    .toList();

/// Real GET /schedule/day/2026-11-02: ids 6, 1, 2, 3, 7, 5.
List<ScheduleBlock> scheduleDayFixture() => (_read('schedule_day.json') as List)
    .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
    .toList();

/// Real POST /schedule 201 body (id 8, daily 12:30-13:15).
ScheduleBlock createdScheduleFixture() =>
    ScheduleBlock.fromJson(_read('schedule_created.json') as Map<String, dynamic>);

/// A Monday on which the day fixture was produced.
final DateTime scheduleFixtureDay = DateTime(2026, 11, 2);

/// In-memory stand-in for the backend behind [ScheduleRepository]. It
/// behaves like the server: lists are ordered by start time then id, the day
/// list applies the recurrence rules (never before start_date; monthly
/// clamps to the month's last day; interval counts from start_date), PATCH
/// merges and validates the time range (422), unknown ids answer 404.
/// Every request is recorded. Gates park an answer; `on*` hooks and failures
/// replace it.
class FakeScheduleRepository implements ScheduleRepository {
  FakeScheduleRepository([List<ScheduleBlock>? initial])
    : server = initial ?? scheduleListFixture();

  List<ScheduleBlock> server;

  Completer<void>? listGate;
  Completer<void>? dayGate;
  Completer<void>? mutationGate;
  Failure? listFailure;
  Failure? dayFailure;
  Failure? createFailure;
  Failure? updateFailure;
  Failure? deleteFailure;

  /// Replaces one answer (e.g. a parked Completer per call).
  Future<Either<Failure, List<ScheduleBlock>>> Function()? onList;
  Future<Either<Failure, List<ScheduleBlock>>> Function(DateTime day)? onDay;

  int listCalls = 0;
  int dayCalls = 0;
  final dayRequests = <DateTime>[];
  final createBodies = <Map<String, dynamic>>[];
  final updateCalls = <(int, Map<String, dynamic>)>[];
  final deleteIds = <int>[];

  int get mutationCalls => createBodies.length + updateCalls.length + deleteIds.length;

  int _nextId = 100;
  int _clock = 0;

  static const notFound = ServerFailure('Kaynak bulunamadı.', statusCode: 404);
  static const invalid = ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);

  DateTime _now() => DateTime(2026, 11, 20, 9).add(Duration(seconds: _clock++));

  List<ScheduleBlock> get sorted => sortBlocks(server);

  /// The server's is_due for [b] on [day].
  static bool isDue(ScheduleBlock b, DateTime day) {
    final d = DateTime.utc(day.year, day.month, day.day);
    final start = DateTime.utc(b.startDate.year, b.startDate.month, b.startDate.day);
    if (d.isBefore(start)) return false;
    switch (b.recurrenceType) {
      case RecurrenceType.daily:
        return true;
      case RecurrenceType.weekly:
        return (b.daysOfWeek ?? const []).contains(d.weekday - 1);
      case RecurrenceType.monthly:
        final lastDay = DateTime.utc(d.year, d.month + 1, 0).day;
        final target = b.dayOfMonth! < lastDay ? b.dayOfMonth! : lastDay;
        return d.day == target;
      case RecurrenceType.interval:
        return d.difference(start).inDays % b.intervalDays! == 0;
      case RecurrenceType.once:
        return d == start;
    }
  }

  @override
  Future<Either<Failure, List<ScheduleBlock>>> getBlocks() async {
    listCalls++;
    final hook = onList;
    if (hook != null) return hook();
    final gate = listGate;
    if (gate != null) await gate.future;
    final failure = listFailure;
    if (failure != null) return Left(failure);
    return Right(sorted);
  }

  @override
  Future<Either<Failure, List<ScheduleBlock>>> getBlocksForDay(DateTime day) async {
    dayCalls++;
    dayRequests.add(day);
    final hook = onDay;
    if (hook != null) return hook(day);
    final gate = dayGate;
    if (gate != null) await gate.future;
    final failure = dayFailure;
    if (failure != null) return Left(failure);
    return Right([
      for (final b in sorted)
        if (isDue(b, day)) b,
    ]);
  }

  @override
  Future<Either<Failure, ScheduleBlock>> createBlock({
    required String title,
    String? description,
    required ScheduleTime startTime,
    required ScheduleTime endTime,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
  }) async {
    createBodies.add({
      'title': title,
      'description': description,
      'start_time': startTime.hhmm,
      'end_time': endTime.hhmm,
      'recurrence_type': recurrenceType.name,
      'days_of_week': daysOfWeek,
      'day_of_month': dayOfMonth,
      'interval_days': intervalDays,
      'start_date': startDate,
    });
    final gate = mutationGate;
    if (gate != null) await gate.future;
    final failure = createFailure;
    if (failure != null) return Left(failure);
    if (validateTimeRange(startTime, endTime) != null) return const Left(invalid);
    final now = _now();
    final created = createdScheduleFixture().copyWith(
      id: _nextId++,
      title: title.trim(),
      description: description,
      startTime: startTime,
      endTime: endTime,
      recurrenceType: recurrenceType,
      daysOfWeek: daysOfWeek == null ? null : (List<int>.of(daysOfWeek)..sort()),
      dayOfMonth: dayOfMonth,
      intervalDays: intervalDays,
      startDate: DateTime(startDate.year, startDate.month, startDate.day),
      createdAt: now,
      updatedAt: now,
    );
    server = [...server, created];
    return Right(created);
  }

  @override
  Future<Either<Failure, ScheduleBlock>> updateBlock(int id, ScheduleChanges changes) async {
    updateCalls.add((id, changes.toBody()));
    final gate = mutationGate;
    if (gate != null) await gate.future;
    final failure = updateFailure;
    if (failure != null) return Left(failure);
    final index = server.indexWhere((b) => b.id == id);
    if (index < 0) return const Left(notFound);
    T? pick<T>(PlanField<T> f, T? current) => switch (f) {
      PlanFieldUnset<T>() => current,
      PlanFieldSet<T>(:final value) => value,
      PlanFieldClear<T>() => null,
    };
    final b = server[index];
    final start = pick(changes.startTime, b.startTime);
    final end = pick(changes.endTime, b.endTime);
    final title = pick(changes.title, b.title);
    final type = pick(changes.recurrenceType, b.recurrenceType);
    if (start == null || end == null || title == null || type == null) {
      return const Left(invalid);
    }
    if (validateTimeRange(start, end) != null) return const Left(invalid);
    final updated = b.copyWith(
      title: title,
      description: pick(changes.description, b.description),
      startTime: start,
      endTime: end,
      recurrenceType: type,
      daysOfWeek: pick(changes.daysOfWeek, b.daysOfWeek),
      dayOfMonth: pick(changes.dayOfMonth, b.dayOfMonth),
      intervalDays: pick(changes.intervalDays, b.intervalDays),
      updatedAt: _now(),
    );
    server = [...server]..[index] = updated;
    return Right(updated);
  }

  @override
  Future<Either<Failure, void>> deleteBlock(int id) async {
    deleteIds.add(id);
    final gate = mutationGate;
    if (gate != null) await gate.future;
    final failure = deleteFailure;
    if (failure != null) return Left(failure);
    if (!server.any((b) => b.id == id)) return const Left(notFound);
    server = server.where((b) => b.id != id).toList();
    return const Right(null);
  }
}
