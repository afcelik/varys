// Contract tests: CalendarMonth parses real backend JSON (test/fixtures/,
// generated from varys-api with its TestClient setup) field by field.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('GET /calendar/month 2026-11 (CalendarMonthRead)', () {
    late Map<String, dynamic> raw;
    late CalendarMonth month;

    setUpAll(() {
      raw = _read('calendar_month_2026_11.json');
      month = CalendarMonth.fromJson(raw);
    });

    test('year, month and all 30 days in order, local midnight, no time zone', () {
      expect(month.year, 2026);
      expect(month.month, 11);
      expect(month.days, hasLength(30));
      for (var i = 0; i < 30; i++) {
        final day = month.days[i].day;
        expect(day, DateTime(2026, 11, i + 1));
        expect(day.isUtc, isFalse);
        expect((day.hour, day.minute, day.second), (0, 0, 0));
      }
    });

    test('an empty day has every count 0', () {
      final d = month.days[5]; // 2026-11-06
      expect(d.day, DateTime(2026, 11, 6));
      expect(d.taskCount, 0);
      expect(d.dueCount, 0);
      expect(d.routineCount, 0);
      expect(d.scheduleCount, 0);
    });

    test('a multi-count day: every field (2026-11-21)', () {
      final d = month.days[20];
      expect(d.day, DateTime(2026, 11, 21));
      expect(d.taskCount, 2);
      expect(d.dueCount, 1);
      expect(d.routineCount, 0);
      expect(d.scheduleCount, 2);
    });

    test('planned, due-only, routine-only and done-task days', () {
      expect(month.days[2].taskCount, 2); // 03: two planned tasks
      expect(month.days[4].dueCount, 1); // 05: due only
      expect(month.days[4].taskCount, 0);
      expect(month.days[1].routineCount, 1); // 02: Monday routine
      expect(month.days[1].scheduleCount, 0);
      expect(month.days[9].taskCount, 0); // 10: only a done task planned
      expect(month.days[29].dueCount, 1); // 30
      expect(month.days[29].routineCount, 1);
    });

    test('toJson round-trips to the exact backend JSON', () {
      expect(jsonDecode(jsonEncode(month.toJson())), raw);
    });
  });

  group('GET /calendar/month 2024-02 (leap year)', () {
    test('29 days, the last is 2024-02-29 with its task', () {
      final raw = _read('calendar_month_2024_02.json');
      final month = CalendarMonth.fromJson(raw);
      expect((month.year, month.month), (2024, 2));
      expect(month.days, hasLength(29));
      expect(month.days.first.day, DateTime(2024, 2, 1));
      final last = month.days.last;
      expect(last.day, DateTime(2024, 2, 29));
      expect((last.taskCount, last.dueCount), (1, 1));
      expect(jsonDecode(jsonEncode(month.toJson())), raw);
    });
  });

  group('CalendarDayConverter', () {
    const converter = CalendarDayConverter();

    test('parses YYYY-MM-DD as local midnight and writes it back', () {
      final d = converter.fromJson('2026-03-29');
      expect(d, DateTime(2026, 3, 29));
      expect(d.isUtc, isFalse);
      expect(converter.toJson(d), '2026-03-29');
    });

    test('rejects a time, a zone, a short form and an impossible date', () {
      for (final bad in [
        '2026-11-21T00:00:00',
        '2026-11-21Z',
        '2026-11-21+03:00',
        '2026-1-2',
        '2026-02-30',
        '',
      ]) {
        expect(() => converter.fromJson(bad), throwsFormatException, reason: bad);
      }
    });
  });
}
