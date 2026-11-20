import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/planning/domain/eisenhower.dart';
import 'package:varys/features/planning/domain/task.dart';

/// Real GET /tasks: one open task per quadrant (ids 1-4) and a done
/// "Hemen yap" task (id 5).
List<Task> _fixtureTasks() =>
    (jsonDecode(File('test/fixtures/tasks_eisenhower.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .map(Task.fromJson)
        .toList();

Task _task(
  int id, {
  bool important = false,
  bool urgent = false,
  TaskStatus status = TaskStatus.todo,
  DateTime? createdAt,
  DateTime? deletedAt,
}) {
  final at = createdAt ?? DateTime(2026, 11, 20, 9);
  return Task(
    id: id,
    title: 'Görev $id',
    status: status,
    createdAt: at,
    updatedAt: at,
    deletedAt: deletedAt,
    isImportant: important,
    isUrgent: urgent,
  );
}

void main() {
  group('EisenhowerQuadrant labels', () {
    test('Turkish names and subtitles, in matrix order', () {
      expect(EisenhowerQuadrant.values.map((q) => q.title), [
        'Hemen yap',
        'Planla',
        'Devret ya da kısalt',
        'Ele ya da ertele',
      ]);
      expect(EisenhowerQuadrant.values.map((q) => q.subtitle), [
        'Önemli ve acil',
        'Önemli, acil değil',
        'Acil, önemli değil',
        'Ne önemli ne acil',
      ]);
    });

    test('path segments map back; unknown, empty and null give null', () {
      for (final q in EisenhowerQuadrant.values) {
        expect(EisenhowerQuadrant.fromPathSegment(q.pathSegment), q);
      }
      expect(EisenhowerQuadrant.values.map((q) => q.pathSegment).toSet(), hasLength(4));
      expect(EisenhowerQuadrant.fromPathSegment('doNow'), isNull);
      expect(EisenhowerQuadrant.fromPathSegment('DO-NOW'), isNull);
      expect(EisenhowerQuadrant.fromPathSegment(''), isNull);
      expect(EisenhowerQuadrant.fromPathSegment(null), isNull);
    });
  });

  group('quadrantOf', () {
    test('each flag pair gives its own quadrant', () {
      expect(quadrantOf(_task(1, important: true, urgent: true)), EisenhowerQuadrant.doNow);
      expect(quadrantOf(_task(2, important: true)), EisenhowerQuadrant.schedule);
      expect(quadrantOf(_task(3, urgent: true)), EisenhowerQuadrant.delegate);
      expect(quadrantOf(_task(4)), EisenhowerQuadrant.eliminate);
    });

    test('real backend tasks land in the expected quadrants', () {
      final byId = {for (final t in _fixtureTasks()) t.id: quadrantOf(t)};
      expect(byId, {
        1: EisenhowerQuadrant.doNow,
        2: EisenhowerQuadrant.schedule,
        3: EisenhowerQuadrant.delegate,
        4: EisenhowerQuadrant.eliminate,
        5: EisenhowerQuadrant.doNow,
      });
    });
  });

  group('groupByQuadrant', () {
    test('real backend list: one open task per quadrant, the done task left out', () {
      final groups = groupByQuadrant(_fixtureTasks());
      expect(groups.keys.toList(), EisenhowerQuadrant.values);
      expect(groups[EisenhowerQuadrant.doNow]!.map((t) => t.id), [1]);
      expect(groups[EisenhowerQuadrant.schedule]!.map((t) => t.id), [2]);
      expect(groups[EisenhowerQuadrant.delegate]!.map((t) => t.id), [3]);
      expect(groups[EisenhowerQuadrant.eliminate]!.map((t) => t.id), [4]);
    });

    test('done tasks are never counted; todo and in_progress are', () {
      final groups = groupByQuadrant([
        _task(1, important: true, urgent: true, status: TaskStatus.done),
        _task(2, important: true, urgent: true, status: TaskStatus.inProgress),
        _task(3, important: true, urgent: true),
        _task(4, status: TaskStatus.done),
      ]);
      expect(groups[EisenhowerQuadrant.doNow]!.map((t) => t.id), [3, 2]);
      expect(groups[EisenhowerQuadrant.eliminate], isEmpty);
    });

    test('deleted tasks are left out', () {
      final groups = groupByQuadrant([
        _task(1, urgent: true, deletedAt: DateTime(2026, 11, 20, 10)),
        _task(2, urgent: true),
      ]);
      expect(groups[EisenhowerQuadrant.delegate]!.map((t) => t.id), [2]);
    });

    test('newest first by createdAt; equal createdAt falls back to id descending', () {
      final groups = groupByQuadrant([
        _task(10, important: true, createdAt: DateTime(2026, 11, 18)),
        _task(11, important: true, createdAt: DateTime(2026, 11, 20)),
        _task(3, important: true, createdAt: DateTime(2026, 11, 19)),
        _task(7, important: true, createdAt: DateTime(2026, 11, 19)),
      ]);
      expect(groups[EisenhowerQuadrant.schedule]!.map((t) => t.id), [11, 7, 3, 10]);
    });

    test('empty input: all four quadrants present and empty', () {
      final groups = groupByQuadrant(const []);
      expect(groups.keys.toList(), EisenhowerQuadrant.values);
      for (final q in EisenhowerQuadrant.values) {
        expect(groups[q], isEmpty, reason: q.name);
      }
    });

    test('the input list is not reordered', () {
      final input = [
        _task(1, important: true, createdAt: DateTime(2026, 11, 1)),
        _task(2, important: true, createdAt: DateTime(2026, 11, 2)),
      ];
      groupByQuadrant(input);
      expect(input.map((t) => t.id), [1, 2]);
    });
  });
}
