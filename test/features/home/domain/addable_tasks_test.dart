import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:varys/features/home/domain/addable_tasks.dart';
import 'package:varys/features/planning/domain/task.dart';

/// Base task from real backend JSON (test/fixtures/daily_plan_with_tasks.json).
Task _base() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  return Task.fromJson((json['tasks'] as List).first as Map<String, dynamic>);
}

void main() {
  final planDay = DateTime(2026, 11, 1);
  late Task base;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  setUp(() => base = _base());

  Task t(int id, {TaskStatus status = TaskStatus.todo, String? planned}) => base.copyWith(
        id: id,
        title: 'Görev $id',
        status: status,
        plannedDate: planned == null ? null : DateTime.parse(planned),
      );

  group('buildAddableTasks', () {
    test('excludes done tasks and tasks planned for the plan day', () {
      final result = buildAddableTasks([
        t(1, status: TaskStatus.done),
        t(2, status: TaskStatus.done, planned: '2026-11-17T00:00:00'),
        t(3, planned: '2026-11-01T00:00:00'),
        t(4),
        t(5, status: TaskStatus.inProgress),
      ], planDay);

      expect(result.map((a) => a.task.id), [4, 5]);
    });

    test('a planned_date with a time part on the plan day still counts as the same day', () {
      final result = buildAddableTasks([
        t(1, planned: '2026-11-01T13:30:00'),
        t(2, planned: '2026-11-01T23:59:59'),
        t(3, planned: '2026-11-02T00:00:00'),
      ], DateTime(2026, 11, 1, 18, 45));

      expect(result.map((a) => a.task.id), [3]);
    });

    test('unplanned first in input order, then other days by date with a Turkish day label', () {
      final result = buildAddableTasks([
        t(1, planned: '2026-11-17T09:00:00'),
        t(2),
        t(3, planned: '2026-10-30T00:00:00'),
        t(4, status: TaskStatus.inProgress),
      ], planDay);

      expect(result.map((a) => a.task.id), [2, 4, 3, 1]);
      expect(result.map((a) => a.dayLabel), [null, null, '30 Eki', '17 Kas']);
    });

    test('empty input gives empty output', () {
      expect(buildAddableTasks(const [], planDay), isEmpty);
    });
  });

  group('turkishLower', () {
    test('maps dotted İ to i and dotless I to ı', () {
      expect(turkishLower('İSTANBUL'), 'istanbul');
      expect(turkishLower('IRMAK'), 'ırmak');
      expect(turkishLower('ÇĞÖŞÜ'), 'çğöşü');
    });
  });

  group('matchesQuery', () {
    test('case-insensitive, Turkish-aware substring', () {
      expect(matchesQuery('İstanbul toplantısı', 'istanbul'), isTrue);
      expect(matchesQuery('istanbul toplantısı', 'İSTANBUL'), isTrue);
      expect(matchesQuery('Irmak kenarı', 'ırmak'), isTrue);
      expect(matchesQuery('Rapor', 'RAP'), isTrue);
      expect(matchesQuery('Irmak kenarı', 'irmak'), isFalse);
      expect(matchesQuery('Rapor', 'fatura'), isFalse);
    });

    test('empty or whitespace query matches everything; query is trimmed', () {
      expect(matchesQuery('Rapor', ''), isTrue);
      expect(matchesQuery('Rapor', '   '), isTrue);
      expect(matchesQuery('Rapor yaz', '  rapor '), isTrue);
    });
  });
}
