import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';

/// Contract tests for the one-time ('once') recurrence type against real
/// backend JSON, generated from varys-api (in-memory DB, real router and
/// schemas):
/// - schedule_list_with_once.json = GET /schedule (daily, monthly, once)
/// - schedule_created_once.json = POST /schedule 201 (once on 2026-11-25)
/// - schedule_updated_monthly_to_once.json = PATCH /schedule/3 200
///   (monthly -> once, unrelated fields sent as null)
/// - routines_list_with_once.json = GET /routines (daily, once)
/// - routine_create_once_interval_422.json = POST /routines 422
///   (once + interval_days, pydantic list body)

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  group('GET /schedule with a once block', () {
    late List<Map<String, dynamic>> raw;
    late List<ScheduleBlock> blocks;

    setUp(() {
      raw = (_read('schedule_list_with_once.json') as List).cast<Map<String, dynamic>>();
      blocks = raw.map(ScheduleBlock.fromJson).toList();
    });

    test('parses in backend order with the once type', () {
      expect(blocks.map((b) => b.id), [1, 3, 2]);
      expect(blocks.map((b) => b.recurrenceType), [
        RecurrenceType.daily,
        RecurrenceType.monthly,
        RecurrenceType.once,
      ]);
    });

    test('once block: every field; the three recurrence fields null', () {
      final b = blocks.last;
      expect(raw.last['recurrence_type'], 'once');
      expect(b.id, 2);
      expect(b.title, 'Doktor randevusu');
      expect(b.description, 'Kardiyoloji, 3. kat');
      expect(b.startTime.hhmm, '14:00');
      expect(b.endTime.hhmm, '15:00');
      expect(b.daysOfWeek, isNull);
      expect(b.dayOfMonth, isNull);
      expect(b.intervalDays, isNull);
      expect(b.startDate, DateTime(2026, 11, 25));
      expect(b.startDate.isUtc, isFalse);
    });

    test("toJson round-trips with 'once' on the wire", () {
      for (var i = 0; i < blocks.length; i++) {
        final json = jsonDecode(jsonEncode(blocks[i].toJson())) as Map<String, dynamic>;
        expect(json['recurrence_type'], raw[i]['recurrence_type']);
        expect(json.keys.toSet(), raw[i].keys.toSet());
        expect(ScheduleBlock.fromJson(json), blocks[i]);
      }
    });

    test('an unknown recurrence_type is still rejected', () {
      for (final value in ['yearly', 'ONCE', 'one_time', '']) {
        final bad = Map<String, dynamic>.from(raw.last)..['recurrence_type'] = value;
        expect(() => ScheduleBlock.fromJson(bad), throwsA(anything), reason: value);
      }
    });
  });

  group('POST /schedule 201 and PATCH 200 (once)', () {
    test('created once block parses', () {
      final b = ScheduleBlock.fromJson(_read('schedule_created_once.json') as Map<String, dynamic>);
      expect(b.recurrenceType, RecurrenceType.once);
      expect(b.startDate, DateTime(2026, 11, 25));
      expect([b.daysOfWeek, b.dayOfMonth, b.intervalDays], [null, null, null]);
    });

    test('PATCH monthly -> once: type once, day_of_month cleared, start_date unchanged', () {
      final raw = _read('schedule_updated_monthly_to_once.json') as Map<String, dynamic>;
      final b = ScheduleBlock.fromJson(raw);
      expect(b.id, 3);
      expect(b.recurrenceType, RecurrenceType.once);
      expect(raw.containsKey('day_of_month'), isTrue);
      expect(b.dayOfMonth, isNull);
      expect(b.daysOfWeek, isNull);
      expect(b.intervalDays, isNull);
      expect(b.startDate, DateTime(2026, 11, 2), reason: 'PATCH never changes start_date');
    });
  });

  group('GET /routines with a once routine', () {
    late List<Map<String, dynamic>> raw;
    late List<Routine> routines;

    setUp(() {
      raw = (_read('routines_list_with_once.json') as List).cast<Map<String, dynamic>>();
      routines = raw.map(Routine.fromJson).toList();
    });

    test('parses daily and once', () {
      expect(routines.map((r) => r.recurrenceType), [RecurrenceType.daily, RecurrenceType.once]);
      final once = routines.last;
      expect(once.title, 'Vergi beyannamesi');
      expect(once.description, 'Son gün');
      expect(once.startDate, DateTime(2026, 11, 25));
      expect([once.daysOfWeek, once.dayOfMonth, once.intervalDays], [null, null, null]);
    });

    test('round-trips through toJson', () {
      for (var i = 0; i < routines.length; i++) {
        final json = jsonDecode(jsonEncode(routines[i].toJson())) as Map<String, dynamic>;
        expect(json['recurrence_type'], raw[i]['recurrence_type']);
        expect(Routine.fromJson(json), routines[i]);
      }
    });

    test('an unknown recurrence_type is still rejected', () {
      final bad = Map<String, dynamic>.from(raw.last)..['recurrence_type'] = 'yearly';
      expect(() => Routine.fromJson(bad), throwsA(anything));
    });
  });

  group('POST /routines 422 (once + interval_days)', () {
    test('real body is a pydantic list naming the rule', () {
      final detail = (_read('routine_create_once_interval_422.json') as Map)['detail'] as List;
      expect(detail, hasLength(1));
      final item = detail.single as Map;
      expect(item['type'], 'value_error');
      expect(item['msg'], contains("interval_days must be null for recurrence_type 'once'"));
    });
  });
}
