// Contract tests: ScheduleBlock parses real backend JSON (test/fixtures/,
// generated from varys-api with its TestClient setup) field by field.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';

import '../fake_schedule_repository.dart';

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  late List<Map<String, dynamic>> rawList;
  late List<ScheduleBlock> list;

  setUpAll(() {
    rawList = (_read('schedule_list.json') as List).cast<Map<String, dynamic>>();
    list = rawList.map(ScheduleBlock.fromJson).toList();
  });

  group('GET /schedule (ScheduleRead list)', () {
    test('parses in backend order: start time, then id', () {
      expect(list.map((b) => b.id), [6, 1, 2, 3, 7, 4, 5]);
      expect(list.map((b) => b.startTime.hhmm), [
        '00:00',
        '06:30',
        '08:30',
        '09:00',
        '09:00',
        '12:00',
        '18:00',
      ]);
    });

    test('first block: every field', () {
      final b = list.first;
      expect(b.id, 6);
      expect(b.title, 'Tüm gün nöbet');
      expect(b.description, 'Telefon açık');
      expect(b.startTime, ScheduleTime(0));
      expect(b.endTime, ScheduleTime(23 * 60 + 59));
      expect(b.endTime.hhmm, '23:59');
      expect(b.recurrenceType, RecurrenceType.daily);
      expect(b.daysOfWeek, isNull);
      expect(b.dayOfMonth, isNull);
      expect(b.intervalDays, isNull);
      expect(b.startDate, DateTime(2026, 11, 2));
      expect(b.createdAt, DateTime(2026, 11, 20, 19, 45, 39));
      expect(b.updatedAt, DateTime(2026, 11, 20, 19, 45, 39));
    });

    test('every recurrence type maps to its enum with only its own field', () {
      final byType = {for (final b in list) b.recurrenceType: b};
      expect(byType.keys.toSet(), RecurrenceType.values.toSet());

      final weekly = byType[RecurrenceType.weekly]!;
      expect(weekly.daysOfWeek, [0, 2, 4]);
      expect(weekly.dayOfMonth, isNull);
      expect(weekly.intervalDays, isNull);

      final monthly = byType[RecurrenceType.monthly]!;
      expect(monthly.dayOfMonth, 15);
      expect(monthly.daysOfWeek, isNull);
      expect(monthly.intervalDays, isNull);

      final interval = byType[RecurrenceType.interval]!;
      expect(interval.intervalDays, 3);
      expect(interval.daysOfWeek, isNull);
      expect(interval.dayOfMonth, isNull);
    });

    test('null description stays null; set description is kept', () {
      expect(list.firstWhere((b) => b.id == 2).description, isNull);
      expect(list.firstWhere((b) => b.id == 1).description, 'Sahil yolu, hafif tempo');
    });

    test('255-character unbroken title is kept whole (counted in code points)', () {
      final long = list.firstWhere((b) => b.id == 3).title;
      expect(long.runes.length, 255);
      expect(long.contains(' '), isFalse);
    });

    test('times are HH:MM on the wire and minutes since midnight in Dart', () {
      for (var i = 0; i < list.length; i++) {
        expect(list[i].startTime.hhmm, rawList[i]['start_time']);
        expect(list[i].endTime.hhmm, rawList[i]['end_time']);
        expect(list[i].startTime < list[i].endTime, isTrue);
      }
      final b = list.firstWhere((b) => b.id == 1);
      expect(b.startTime.minutes, 6 * 60 + 30);
      expect(b.startTime.hour, 6);
      expect(b.startTime.minute, 30);
    });

    test('start_date is a plain date with no time zone conversion', () {
      for (final b in list) {
        expect(b.startDate.isUtc, isFalse);
        expect((b.startDate.year, b.startDate.month, b.startDate.day), (2026, 11, 2));
        expect((b.startDate.hour, b.startDate.minute), (0, 0));
      }
    });

    test('toJson uses snake_case keys, HH:MM times, and round-trips', () {
      for (var i = 0; i < list.length; i++) {
        final json = list[i].toJson();
        expect(json.keys.toSet(), rawList[i].keys.toSet());
        expect(json['start_time'], rawList[i]['start_time']);
        expect(json['end_time'], rawList[i]['end_time']);
        expect(json['recurrence_type'], rawList[i]['recurrence_type']);
        expect(
          ScheduleBlock.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>),
          list[i],
        );
      }
    });

    test('unknown recurrence_type and malformed times are rejected', () {
      for (final (key, value) in [
        ('recurrence_type', 'yearly'),
        ('start_time', '08:30:00'),
        ('end_time', '24:00'),
        ('start_time', '7:05'),
      ]) {
        final bad = Map<String, dynamic>.from(rawList[0])..[key] = value;
        expect(() => ScheduleBlock.fromJson(bad), throwsA(anything), reason: '$key=$value');
      }
    });
  });

  group('GET /schedule/day/{day}', () {
    test('mixed times, two blocks at the same start time ordered by id', () {
      final day = (_read('schedule_day.json') as List)
          .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(day.map((b) => b.id), [6, 1, 2, 3, 7, 5]);
      final nine = day.where((b) => b.startTime.hhmm == '09:00').map((b) => b.id);
      expect(nine, [3, 7]);
      // The monthly block (day 15) is not scheduled on 2026-11-02.
      expect(day.any((b) => b.recurrenceType == RecurrenceType.monthly), isFalse);
    });
  });

  group('FakeScheduleRepository matches the real server', () {
    test('its day list for 2026-11-02 equals the real GET /schedule/day response', () async {
      final fake = FakeScheduleRepository();
      final day = (await fake.getBlocksForDay(
        scheduleFixtureDay,
      )).fold((f) => fail('$f'), (r) => r);
      expect(day, scheduleDayFixture());
    });

    test('recurrence rules: monthly clamps to the month end, interval counts from start', () {
      final b = scheduleListFixture().first;
      final monthly31 = b.copyWith(recurrenceType: RecurrenceType.monthly, dayOfMonth: 31);
      expect(FakeScheduleRepository.isDue(monthly31, DateTime(2027, 2, 28)), isTrue);
      expect(FakeScheduleRepository.isDue(monthly31, DateTime(2026, 11, 30)), isTrue);
      expect(FakeScheduleRepository.isDue(monthly31, DateTime(2026, 12, 30)), isFalse);
      final every3 = b.copyWith(recurrenceType: RecurrenceType.interval, intervalDays: 3);
      expect(FakeScheduleRepository.isDue(every3, DateTime(2026, 11, 5)), isTrue);
      expect(FakeScheduleRepository.isDue(every3, DateTime(2026, 11, 6)), isFalse);
      expect(
        FakeScheduleRepository.isDue(b, DateTime(2026, 11, 1)),
        isFalse,
        reason: 'before start',
      );
    });
  });

  group('POST /schedule 201 and PATCH 200', () {
    test('created block parses', () {
      final b = ScheduleBlock.fromJson(_read('schedule_created.json') as Map<String, dynamic>);
      expect(b.id, 8);
      expect(b.title, 'Öğle yemeği');
      expect(b.description, 'Ofiste');
      expect((b.startTime.hhmm, b.endTime.hhmm), ('12:30', '13:15'));
      expect(b.recurrenceType, RecurrenceType.daily);
    });

    test('PATCH with description null: the cleared field comes back null', () {
      final b = ScheduleBlock.fromJson(
        _read('schedule_updated_cleared.json') as Map<String, dynamic>,
      );
      expect(b.id, 1);
      expect(b.description, isNull);
      expect(b.title, 'Sabah koşusu');
    });
  });

  group('error bodies (real shapes)', () {
    test('PATCH 404 and range 422 have a plain-text detail; POST 422 a pydantic list', () {
      expect((_read('schedule_update_404.json') as Map)['detail'], isA<String>());
      expect(
        (_read('schedule_update_range_422.json') as Map)['detail'],
        'end_time must be after start_time',
      );
      final seconds = (_read('schedule_create_seconds_422.json') as Map)['detail'] as List;
      expect((seconds.single as Map)['loc'], ['body', 'start_time']);
      expect((seconds.single as Map)['input'], '08:30:00');
    });
  });

  group('ScheduleTime', () {
    test('parse/format bounds 00:00 and 23:59', () {
      expect(ScheduleTime.parse('00:00').minutes, 0);
      expect(ScheduleTime.parse('23:59').minutes, 1439);
      expect(ScheduleTime(0).hhmm, '00:00');
      expect(ScheduleTime(1439).hhmm, '23:59');
      expect(ScheduleTime.hm(8, 5).hhmm, '08:05');
    });

    test('strict format: seconds, 24:00, short forms, dots and non-ASCII digits rejected', () {
      for (final s in [
        '24:00',
        '08:30:00',
        '7:05',
        '07:5',
        '08.30',
        '',
        ' 08:30',
        '08:60',
        '\u0660\u0668:\u0663\u0660', // Arabic-Indic digits
      ]) {
        expect(ScheduleTime.tryParse(s), isNull, reason: s);
        expect(() => ScheduleTime.parse(s), throwsFormatException, reason: s);
      }
    });

    test('ordering and equality by minutes', () {
      expect(ScheduleTime.hm(9, 0), ScheduleTime(540));
      expect(ScheduleTime.hm(9, 0).compareTo(ScheduleTime.hm(9, 1)), lessThan(0));
      expect(ScheduleTime.hm(9, 0) <= ScheduleTime.hm(9, 0), isTrue);
      expect(ScheduleTime.hm(9, 0) < ScheduleTime.hm(9, 0), isFalse);
    });
  });
}
