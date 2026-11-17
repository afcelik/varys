import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/routines/domain/routine.dart';

/// Contract tests against real backend JSON.
/// test/fixtures/routines_day.json = GET /routines/day/2026-11-16 response,
/// generated from varys-api (in-memory DB, real router and schemas).
void main() {
  late List<Map<String, dynamic>> rawItems;
  late List<RoutineDayItem> items;

  setUp(() {
    final decoded =
        jsonDecode(File('test/fixtures/routines_day.json').readAsStringSync()) as List<dynamic>;
    rawItems = decoded.cast<Map<String, dynamic>>();
    items = rawItems.map(RoutineDayItem.fromJson).toList();
  });

  test('fixture parses as a list of RoutineDayItem in backend order', () {
    expect(items.map((i) => i.id), [1, 2, 3, 4]);
    expect(items.map((i) => i.title), ['Su iç', 'Spor', 'Fatura öde', 'Bitki sula']);
  });

  test('daily item: every field, completion and streaks', () {
    final daily = items[0];
    expect(daily.recurrenceType, RecurrenceType.daily);
    expect(daily.description, '8 bardak');
    expect(daily.daysOfWeek, isNull);
    expect(daily.dayOfMonth, isNull);
    expect(daily.intervalDays, isNull);
    expect(daily.completed, isTrue);
    expect(daily.currentStreak, 3);
    expect(daily.longestStreak, 3);
  });

  test('every recurrence_type value maps to its enum with its own field', () {
    expect(items.map((i) => i.recurrenceType), [
      RecurrenceType.daily,
      RecurrenceType.weekly,
      RecurrenceType.monthly,
      RecurrenceType.interval,
    ]);
    expect(items[1].daysOfWeek, [0, 2]);
    expect(items[2].dayOfMonth, 16);
    expect(items[3].intervalDays, 2);
  });

  test('null fields stay null (description, unused recurrence fields)', () {
    final weekly = items[1];
    expect(weekly.description, isNull);
    expect(weekly.dayOfMonth, isNull);
    expect(weekly.intervalDays, isNull);
    expect(weekly.completed, isFalse);
    expect(weekly.currentStreak, 0);
    expect(weekly.longestStreak, 0);

    final monthly = items[2];
    expect(monthly.daysOfWeek, isNull);
    expect(monthly.intervalDays, isNull);

    final interval = items[3];
    expect(interval.daysOfWeek, isNull);
    expect(interval.dayOfMonth, isNull);
  });

  test('dates are plain local values with no time zone conversion', () {
    // Fixture strings carry no TZ suffix.
    expect(rawItems[3]['start_date'], '2026-11-14');
    expect(rawItems[3]['created_at'], isNot(endsWith('Z')));

    final interval = items[3];
    expect(interval.startDate, DateTime(2026, 11, 14));
    expect(interval.startDate.isUtc, isFalse);
    expect(interval.createdAt.isUtc, isFalse);
    expect(interval.createdAt, DateTime.parse(rawItems[3]['created_at'] as String));
  });

  test('toJson uses snake_case backend keys and enum values, and round-trips', () {
    for (var i = 0; i < items.length; i++) {
      final json = items[i].toJson();
      expect(json.keys.toSet(), rawItems[i].keys.toSet());
      expect(json['recurrence_type'], rawItems[i]['recurrence_type']);
      expect(RoutineDayItem.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>),
          items[i]);
    }
  });

  test('unknown recurrence_type is rejected', () {
    final bad = Map<String, dynamic>.from(rawItems[0])..['recurrence_type'] = 'yearly';
    expect(() => RoutineDayItem.fromJson(bad), throwsA(anything));
  });

  test('Routine parses the RoutineRead subset of the same payload', () {
    final routine = Routine.fromJson(rawItems[1]);
    expect(routine.id, 2);
    expect(routine.recurrenceType, RecurrenceType.weekly);
    expect(routine.daysOfWeek, [0, 2]);
    expect(routine.description, isNull);
    expect(routine.startDate, DateTime(2026, 11, 2));
    final json = routine.toJson();
    expect(json.containsKey('completed'), isFalse);
    expect(Routine.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>), routine);
  });
}
