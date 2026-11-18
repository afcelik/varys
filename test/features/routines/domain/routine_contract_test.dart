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

  group('GET /routines and POST /routines (Routine, RoutineRead)', () {
    // test/fixtures/routines_list.json = GET /routines response and
    // test/fixtures/routine_created.json = POST /routines 201 response,
    // generated from varys-api (in-memory DB, real router and schemas).
    late List<Map<String, dynamic>> rawList;
    late List<Routine> routines;

    setUp(() {
      rawList = (jsonDecode(File('test/fixtures/routines_list.json').readAsStringSync())
              as List<dynamic>)
          .cast<Map<String, dynamic>>();
      routines = rawList.map(Routine.fromJson).toList();
    });

    test('list parses in backend order with all four recurrence types', () {
      expect(routines.map((r) => r.id), [1, 2, 3, 4]);
      expect(routines.map((r) => r.recurrenceType), [
        RecurrenceType.daily,
        RecurrenceType.weekly,
        RecurrenceType.monthly,
        RecurrenceType.interval,
      ]);
      expect(rawList.first.containsKey('current_streak'), isFalse,
          reason: 'GET /routines carries no streaks');
    });

    test('each type has only its own recurrence field; the rest are null', () {
      final [daily, weekly, monthly, interval] = routines;
      expect([daily.daysOfWeek, daily.dayOfMonth, daily.intervalDays], [null, null, null]);
      expect(weekly.daysOfWeek, [0, 2, 4]);
      expect([weekly.dayOfMonth, weekly.intervalDays], [null, null]);
      expect(monthly.dayOfMonth, 31);
      expect([monthly.daysOfWeek, monthly.intervalDays], [null, null]);
      expect(interval.intervalDays, 3);
      expect([interval.daysOfWeek, interval.dayOfMonth], [null, null]);
    });

    test('null description stays null; set description is kept', () {
      expect(routines[0].description, '8 bardak');
      expect(routines[1].description, isNull);
      expect(routines[2].description, isNull);
      expect(routines[3].description, 'Salon ve balkon');
    });

    test('start_date is a plain date with no time zone', () {
      expect(rawList[2]['start_date'], '2026-10-15');
      expect(routines[2].startDate, DateTime(2026, 10, 15));
      expect(routines[2].startDate.isUtc, isFalse);
    });

    test('list items round-trip through toJson with the same keys', () {
      for (var i = 0; i < routines.length; i++) {
        final json = routines[i].toJson();
        expect(json.keys.toSet(), rawList[i].keys.toSet());
        expect(Routine.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>),
            routines[i]);
      }
    });

    test('POST 201 body parses as Routine (weekly, days sorted by the backend)', () {
      final raw = jsonDecode(File('test/fixtures/routine_created.json').readAsStringSync())
          as Map<String, dynamic>;
      final created = Routine.fromJson(raw);
      expect(created.id, 2);
      expect(created.title, 'Spor');
      expect(created.recurrenceType, RecurrenceType.weekly);
      expect(created.daysOfWeek, [0, 2, 4]);
      expect(created.description, isNull);
      expect(created.startDate, DateTime(2026, 11, 2));
      expect(created.createdAt.isUtc, isFalse);
    });
  });
}
