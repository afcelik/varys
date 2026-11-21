import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/projects/domain/project_tasks.dart';

Task _task(
  int id, {
  int? projectId = 7,
  TaskStatus status = TaskStatus.todo,
  DateTime? createdAt,
  DateTime? deletedAt,
}) {
  final at = createdAt ?? DateTime(2026, 11, id);
  return Task(
    id: id,
    title: 'Görev $id',
    status: status,
    createdAt: at,
    updatedAt: at,
    deletedAt: deletedAt,
    projectId: projectId,
  );
}

List<int> _ids(List<Task> tasks) => tasks.map((t) => t.id).toList();

void main() {
  group('projectTaskGroups', () {
    test('keeps only the tasks of the given project (other project and Projesiz left out)', () {
      final groups = projectTaskGroups([
        _task(1),
        _task(2, projectId: 8),
        _task(3, projectId: null),
        _task(4),
      ], 7);
      expect(_ids(groups.pending), [4, 1]);
      expect(groups.done, isEmpty);
    });

    test('done tasks go to done; todo and in progress stay pending', () {
      final groups = projectTaskGroups([
        _task(1, status: TaskStatus.done),
        _task(2, status: TaskStatus.inProgress),
        _task(3),
        _task(4, status: TaskStatus.done),
      ], 7);
      expect(_ids(groups.pending), [3, 2]);
      expect(_ids(groups.done), [4, 1]);
    });

    test('deleted tasks are left out of both groups', () {
      final groups = projectTaskGroups([
        _task(1, deletedAt: DateTime(2026, 11, 20)),
        _task(2, status: TaskStatus.done, deletedAt: DateTime(2026, 11, 20)),
        _task(3),
      ], 7);
      expect(_ids(groups.pending), [3]);
      expect(groups.done, isEmpty);
    });

    test('newest first by created_at, not by input order or id; equal times by id desc', () {
      final same = DateTime(2026, 11, 10, 9);
      final groups = projectTaskGroups([
        _task(9, createdAt: DateTime(2026, 11, 1)),
        _task(2, createdAt: DateTime(2026, 11, 15)),
        _task(5, createdAt: same),
        _task(6, createdAt: same),
      ], 7);
      expect(_ids(groups.pending), [2, 6, 5, 9]);
    });

    test('no task of the project: both groups empty; the input list is not changed', () {
      final input = [_task(2, projectId: 8), _task(1, projectId: 8)];
      final groups = projectTaskGroups(input, 7);
      expect(groups.pending, isEmpty);
      expect(groups.done, isEmpty);
      expect(_ids(input), [2, 1]);
    });
  });

  group('shortTrDay', () {
    test('"21 Kas" style, no locale data needed', () {
      expect(shortTrDay(DateTime(2026, 11, 21)), '21 Kas');
      expect(shortTrDay(DateTime(2026, 2, 3)), '3 Şub');
      expect(shortTrDay(DateTime(2026, 8, 30)), '30 Ağu');
    });

    test('same as intl tr "d MMM" for every month', () async {
      await initializeDateFormatting('tr_TR', null);
      final intl = DateFormat('d MMM', 'tr_TR');
      for (var month = 1; month <= 12; month++) {
        final day = DateTime(2026, month, 5);
        expect(shortTrDay(day), intl.format(day), reason: 'month $month');
      }
    });
  });
}
