// Pure calendar logic: Monday-first month grid, month arithmetic and bounds,
// Turkish names, and the client-side per-day task filters.

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/calendar/domain/calendar_grid.dart';
import 'package:varys/features/planning/domain/task.dart';

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

Task _task(
  int id, {
  DateTime? planned,
  DateTime? due,
  TaskStatus status = TaskStatus.todo,
  DateTime? deletedAt,
}) => Task(
  id: id,
  title: 'Görev $id',
  status: status,
  createdAt: _d(2026, 11, 1),
  updatedAt: _d(2026, 11, 1),
  deletedAt: deletedAt,
  plannedDate: planned,
  dueDate: due,
);

void main() {
  group('monthGrid', () {
    void expectWellFormed(List<GridCell> cells, int year, int month) {
      expect(cells.length % 7, 0);
      // Monday first: column i is weekday i+1 in every row.
      for (var i = 0; i < cells.length; i++) {
        expect(cells[i].day.weekday, DateTime.monday + i % 7, reason: '${cells[i]}');
        expect((cells[i].day.hour, cells[i].day.minute), (0, 0), reason: '${cells[i]}');
      }
      // Consecutive days, no gaps or repeats.
      for (var i = 1; i < cells.length; i++) {
        final prev = cells[i - 1].day;
        expect(cells[i].day, DateTime(prev.year, prev.month, prev.day + 1));
      }
      final inMonth = cells.where((c) => c.inMonth).map((c) => c.day).toList();
      final days = DateTime(year, month + 1, 0).day;
      expect(inMonth, [for (var d = 1; d <= days; d++) _d(year, month, d)]);
      // Leading/trailing cells belong to other months only.
      for (final c in cells.where((c) => !c.inMonth)) {
        expect(c.day.year == year && c.day.month == month, isFalse);
      }
      // No whole week of other-month days.
      expect(cells.take(7).any((c) => c.inMonth), isTrue);
      expect(cells.skip(cells.length - 7).any((c) => c.inMonth), isTrue);
    }

    test('2026-11 starts on a Sunday: 6 leading October days, 6 rows', () {
      final cells = monthGrid(2026, 11);
      expectWellFormed(cells, 2026, 11);
      expect(cells, hasLength(42));
      expect(cells.first, GridCell(_d(2026, 10, 26), inMonth: false));
      expect(cells[5], GridCell(_d(2026, 10, 31), inMonth: false));
      expect(cells[6], GridCell(_d(2026, 11, 1), inMonth: true));
      expect(cells[35], GridCell(_d(2026, 11, 30), inMonth: true));
      expect(cells[36], GridCell(_d(2026, 12, 1), inMonth: false));
      expect(cells.last, GridCell(_d(2026, 12, 6), inMonth: false));
    });

    test('2024-02 (leap year): 29 days, starts Thursday, 5 rows', () {
      final cells = monthGrid(2024, 2);
      expectWellFormed(cells, 2024, 2);
      expect(cells, hasLength(35));
      expect(cells.first.day, _d(2024, 1, 29));
      expect(cells[3], GridCell(_d(2024, 2, 1), inMonth: true));
      expect(cells[31], GridCell(_d(2024, 2, 29), inMonth: true));
      expect(cells[32], GridCell(_d(2024, 3, 1), inMonth: false));
      expect(cells.last.day, _d(2024, 3, 3));
    });

    test('a month starting on Monday has no leading days (2026-06)', () {
      final cells = monthGrid(2026, 6);
      expectWellFormed(cells, 2026, 6);
      expect(cells.first, GridCell(_d(2026, 6, 1), inMonth: true));
      expect(cells, hasLength(35));
      expect(cells.last.day, _d(2026, 7, 5));
    });

    test('28-day February starting on Monday fills exactly 4 rows (2027-02)', () {
      final cells = monthGrid(2027, 2);
      expectWellFormed(cells, 2027, 2);
      expect(cells, hasLength(28));
      expect(cells.every((c) => c.inMonth), isTrue);
    });

    test('a 31-day month starting on Sunday needs 6 rows (2026-03, DST month)', () {
      final cells = monthGrid(2026, 3);
      expectWellFormed(cells, 2026, 3);
      expect(cells, hasLength(42));
      expect(cells.last.day, _d(2026, 4, 5));
    });

    test('December -> January: trailing days are in the next year (2026-12)', () {
      final cells = monthGrid(2026, 12);
      expectWellFormed(cells, 2026, 12);
      expect(cells.first, GridCell(_d(2026, 11, 30), inMonth: false));
      expect(cells.last, GridCell(_d(2027, 1, 3), inMonth: false));
    });

    test('January: leading days are in the previous year (2027-01)', () {
      final cells = monthGrid(2027, 1);
      expectWellFormed(cells, 2027, 1);
      expect(cells.first, GridCell(_d(2026, 12, 28), inMonth: false));
      expect(cells[4], GridCell(_d(2027, 1, 1), inMonth: true));
    });

    test('bound months: leading 1999 and trailing 2101 days are out of bounds', () {
      final first = monthGrid(2000, 1);
      expectWellFormed(first, 2000, 1);
      expect(first.first.day, _d(1999, 12, 27));
      expect(isDayInBounds(first.first.day), isFalse);
      expect(isDayInBounds(_d(2000, 1, 1)), isTrue);
      final last = monthGrid(2100, 12);
      expectWellFormed(last, 2100, 12);
      expect(last.last.day, _d(2101, 1, 2));
      expect(isDayInBounds(last.last.day), isFalse);
      expect(isDayInBounds(_d(2100, 12, 31)), isTrue);
    });

    test('rejects a month outside 1..12', () {
      expect(() => monthGrid(2026, 0), throwsArgumentError);
      expect(() => monthGrid(2026, 13), throwsArgumentError);
    });
  });

  group('addMonths and bounds', () {
    test('moves forward and back across years', () {
      expect(addMonths(2026, 11, 1), (year: 2026, month: 12));
      expect(addMonths(2026, 12, 1), (year: 2027, month: 1));
      expect(addMonths(2027, 1, -1), (year: 2026, month: 12));
      expect(addMonths(2026, 11, -11), (year: 2025, month: 12));
      expect(addMonths(2026, 11, 14), (year: 2028, month: 1));
      expect(addMonths(2026, 11, 0), (year: 2026, month: 11));
    });

    test('reaches the bounds but never goes past them', () {
      expect(addMonths(2000, 2, -1), (year: 2000, month: 1));
      expect(addMonths(2000, 1, -1), isNull);
      expect(addMonths(2100, 11, 1), (year: 2100, month: 12));
      expect(addMonths(2100, 12, 1), isNull);
      expect(addMonths(2050, 6, 100 * 12), isNull);
    });

    test('isMonthInBounds', () {
      expect(isMonthInBounds(2000, 1), isTrue);
      expect(isMonthInBounds(2100, 12), isTrue);
      expect(isMonthInBounds(1999, 12), isFalse);
      expect(isMonthInBounds(2101, 1), isFalse);
      expect(isMonthInBounds(2026, 0), isFalse);
      expect(isMonthInBounds(2026, 13), isFalse);
    });
  });

  group('Turkish names', () {
    test('month title and all 12 month names', () {
      expect(monthTitle(2026, 11), 'Kasım 2026');
      expect(monthTitle(2024, 2), 'Şubat 2024');
      expect(turkishMonthNames, [
        'Ocak',
        'Şubat',
        'Mart',
        'Nisan',
        'Mayıs',
        'Haziran',
        'Temmuz',
        'Ağustos',
        'Eylül',
        'Ekim',
        'Kasım',
        'Aralık',
      ]);
    });

    test('weekday headers start on Monday', () {
      expect(weekdayShortNames, ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']);
    });
  });

  group('tasksForDay / dueTasksForDay', () {
    final day = _d(2026, 11, 21);
    final tasks = [
      _task(1, planned: _d(2026, 11, 21)),
      _task(2, planned: DateTime(2026, 11, 21, 15, 30), due: DateTime(2026, 11, 21, 23, 59)),
      _task(3, planned: _d(2026, 11, 21), status: TaskStatus.done),
      _task(4, planned: _d(2026, 11, 21), deletedAt: _d(2026, 11, 20)),
      _task(5, planned: _d(2026, 11, 22), due: _d(2026, 11, 21)),
      _task(6, planned: _d(2026, 10, 21), due: _d(2025, 11, 21)),
      _task(7),
      _task(8, planned: _d(2026, 11, 21), status: TaskStatus.inProgress),
      _task(9, due: _d(2026, 11, 21), status: TaskStatus.done),
      _task(10, due: _d(2026, 11, 21), deletedAt: _d(2026, 11, 1)),
    ];

    test('planned on the day: time ignored, done and deleted left out, order kept', () {
      expect(tasksForDay(tasks, day).map((t) => t.id), [1, 2, 8]);
    });

    test('due on the day: time ignored, done and deleted left out, order kept', () {
      expect(dueTasksForDay(tasks, day).map((t) => t.id), [2, 5]);
    });

    test('a day with nothing returns empty lists', () {
      expect(tasksForDay(tasks, _d(2026, 11, 23)), isEmpty);
      expect(dueTasksForDay(tasks, _d(2026, 11, 23)), isEmpty);
    });
  });
}
