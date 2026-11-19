import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/planning/domain/task.dart';

void main() {
  group('Task Contract Tests - Real Backend JSON', () {
    // This is the ACTUAL JSON response from GET /tasks endpoint
    // Backend returns: id as int, dates as ISO8601 strings, status enum, nullable description
    const actualTaskJsonTodo = {
      'id': 1,
      'title': 'Test Task',
      'description': null,
      'status': 'todo',
      'created_at': '2026-01-15T10:30:00',
      'updated_at': '2026-01-15T10:30:00',
      'deleted_at': null,
      'planned_date': '2026-01-15T09:00:00',
      'due_date': '2026-01-15T18:00:00',
    };

    // Task with in_progress status and description
    const actualTaskJsonInProgress = {
      'id': 2,
      'title': 'In Progress Task',
      'description': 'This task is being worked on',
      'status': 'in_progress',
      'created_at': '2026-01-15T11:00:00',
      'updated_at': '2026-01-15T11:00:00',
      'deleted_at': null,
      'planned_date': null,
      'due_date': null,
    };

    // Task with done status
    const actualTaskJsonDone = {
      'id': 3,
      'title': 'Completed Task',
      'description': 'This task is done',
      'status': 'done',
      'created_at': '2026-01-10T08:00:00',
      'updated_at': '2026-01-12T15:00:00',
      'deleted_at': null,
      'planned_date': '2026-01-15T10:00:00',
      'due_date': '2026-01-15T20:00:00',
    };

    // Task with deleted_at populated
    const actualTaskJsonWithDeletedAt = {
      'id': 4,
      'title': 'Deleted Task',
      'description': 'This task was deleted',
      'status': 'todo',
      'created_at': '2026-01-01T08:00:00',
      'updated_at': '2026-01-05T12:00:00',
      'deleted_at': '2026-01-10T10:00:00',
      'planned_date': null,
      'due_date': null,
    };

    test('parses backend JSON with todo status and null description', () {
      final task = Task.fromJson(actualTaskJsonTodo);

      expect(task.id, equals(1));
      expect(task.title, equals('Test Task'));
      expect(task.description, isNull);
      expect(task.status, equals(TaskStatus.todo));
      expect(task.isCompleted, isFalse);
      expect(task.createdAt, equals(DateTime.parse('2026-01-15T10:30:00')));
      expect(task.updatedAt, equals(DateTime.parse('2026-01-15T10:30:00')));
      expect(task.deletedAt, isNull);
      expect(task.plannedDate, equals(DateTime.parse('2026-01-15T09:00:00')));
      expect(task.dueDate, equals(DateTime.parse('2026-01-15T18:00:00')));
    });

    test('parses backend JSON with in_progress status', () {
      final task = Task.fromJson(actualTaskJsonInProgress);

      expect(task.id, equals(2));
      expect(task.title, equals('In Progress Task'));
      expect(task.description, equals('This task is being worked on'));
      expect(task.status, equals(TaskStatus.inProgress));
      expect(task.isCompleted, isFalse);
      expect(task.createdAt, equals(DateTime.parse('2026-01-15T11:00:00')));
      expect(task.updatedAt, equals(DateTime.parse('2026-01-15T11:00:00')));
      expect(task.deletedAt, isNull);
      expect(task.plannedDate, isNull);
      expect(task.dueDate, isNull);
    });

    test('parses backend JSON with done status', () {
      final task = Task.fromJson(actualTaskJsonDone);

      expect(task.id, equals(3));
      expect(task.title, equals('Completed Task'));
      expect(task.description, equals('This task is done'));
      expect(task.status, equals(TaskStatus.done));
      expect(task.isCompleted, isTrue);
      expect(task.createdAt, equals(DateTime.parse('2026-01-10T08:00:00')));
      expect(task.updatedAt, equals(DateTime.parse('2026-01-12T15:00:00')));
      expect(task.deletedAt, isNull);
      expect(task.plannedDate, equals(DateTime.parse('2026-01-15T10:00:00')));
      expect(task.dueDate, equals(DateTime.parse('2026-01-15T20:00:00')));
    });

    test('parses backend JSON with deleted_at populated', () {
      final task = Task.fromJson(actualTaskJsonWithDeletedAt);

      expect(task.id, equals(4));
      expect(task.deletedAt, equals(DateTime.parse('2026-01-10T10:00:00')));
    });

    test('serializes to JSON with snake_case keys', () {
      final task = Task.fromJson(actualTaskJsonTodo);
      final json = task.toJson();

      expect(json['id'], equals(1));
      expect(json['title'], equals('Test Task'));
      expect(json['description'], isNull);
      expect(json['status'], equals('todo'));
      expect(json['created_at'], equals('2026-01-15T10:30:00.000'));
      expect(json['updated_at'], equals('2026-01-15T10:30:00.000'));
      expect(json['deleted_at'], isNull);
      expect(json['planned_date'], equals('2026-01-15T09:00:00.000'));
      expect(json['due_date'], equals('2026-01-15T18:00:00.000'));
    });

    test('serializes null dates as null in JSON', () {
      final task = Task.fromJson(actualTaskJsonInProgress);
      final json = task.toJson();

      expect(json['planned_date'], isNull);
      expect(json['due_date'], isNull);
      expect(json['deleted_at'], isNull);
    });

    test('Task list from actual backend array response', () {
      const actualTasksArray = [
        actualTaskJsonTodo,
        actualTaskJsonInProgress,
        actualTaskJsonDone,
      ];

      final tasks = actualTasksArray
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();

      expect(tasks.length, equals(3));
      expect(tasks[0].id, equals(1));
      expect(tasks[1].id, equals(2));
      expect(tasks[2].id, equals(3));
      expect(tasks[0].status, equals(TaskStatus.todo));
      expect(tasks[1].status, equals(TaskStatus.inProgress));
      expect(tasks[2].status, equals(TaskStatus.done));
    });

    test('TaskStatus enum serializes correctly via json_serializable', () {
      final todoTask = Task.fromJson(actualTaskJsonTodo);
      final inProgressTask = Task.fromJson(actualTaskJsonInProgress);
      final doneTask = Task.fromJson(actualTaskJsonDone);

      // Check that toJson() uses the correct string values (snake_case)
      expect(todoTask.toJson()['status'], equals('todo'));
      expect(inProgressTask.toJson()['status'], equals('in_progress'));
      expect(doneTask.toJson()['status'], equals('done'));
    });

    test('isCompleted extension works correctly for all statuses', () {
      final todoTask = Task.fromJson(actualTaskJsonTodo);
      final inProgressTask = Task.fromJson(actualTaskJsonInProgress);
      final doneTask = Task.fromJson(actualTaskJsonDone);

      expect(todoTask.isCompleted, isFalse);
      expect(inProgressTask.isCompleted, isFalse);
      expect(doneTask.isCompleted, isTrue);
    });
  });

  // Assumption under test: a timezone suffix (Z, +03:00) is read as a
  // WALL-CLOCK day, NOT as an instant. The backend sends no suffix today;
  // this is a defensive measure so the day never shifts.
  group('Task dates keep the calendar day (no timezone conversion)', () {
    Map<String, dynamic> withDates(String value) => {
          'id': 1,
          'title': 'Test Task',
          'description': null,
          'status': 'todo',
          'created_at': '2026-11-17T10:30:00',
          'updated_at': '2026-11-17T10:30:00',
          'deleted_at': null,
          'planned_date': value,
          'due_date': value,
        };

    for (final raw in const [
      '2026-11-17',
      '2026-11-17T00:00:00',
      '2026-11-17T00:00:00Z',
      '2026-11-17T00:00:00+03:00',
    ]) {
      test('"$raw" parses to 2026-11-17 for planned_date and due_date', () {
        final task = Task.fromJson(withDates(raw));
        for (final d in [task.plannedDate!, task.dueDate!]) {
          expect(dayOnly(d), DateTime(2026, 11, 17));
          expect(d.isUtc, isFalse, reason: 'must be naive local, not an instant');
          expect(d, DateTime(2026, 11, 17));
        }
      });
    }

    test('late-evening suffix values do not roll over to another day', () {
      final plus = Task.fromJson(withDates('2026-11-17T23:30:00+03:00'));
      final minus = Task.fromJson(withDates('2026-11-17T01:00:00-05:00'));
      expect(plus.plannedDate, DateTime(2026, 11, 17, 23, 30));
      expect(minus.dueDate, DateTime(2026, 11, 17, 1));
    });

    test('real backend fixture still parses with day-only planned_date', () {
      final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
          as Map<String, dynamic>;
      final tasks = (json['tasks'] as List)
          .map((t) => Task.fromJson(t as Map<String, dynamic>))
          .toList();
      expect(tasks, isNotEmpty);
      for (final t in tasks) {
        expect(t.plannedDate, DateTime(2026, 11, 1));
        expect(t.dueDate, isNull);
      }
    });
  });

  // GET /tasks now carries project_id (int or null); fixture from the real
  // backend (test/fixtures/tasks_with_project.json).
  group('Task project_id (real backend GET /tasks)', () {
    late List<Task> tasks;
    late List<Map<String, dynamic>> raw;

    setUpAll(() {
      raw = (jsonDecode(File('test/fixtures/tasks_with_project.json').readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
      tasks = raw.map(Task.fromJson).toList();
    });

    test('every task in the real response carries the project_id key', () {
      expect(raw, isNotEmpty);
      for (final json in raw) {
        expect(json.containsKey('project_id'), isTrue, reason: 'task ${json['id']}');
      }
    });

    test('linked task parses projectId; unlinked task parses null', () {
      final linked = tasks.firstWhere((t) => t.id == 2);
      expect(linked.title, 'Kutuları topla');
      expect(linked.projectId, 1);
      expect(linked.status, TaskStatus.todo);

      final unlinked = tasks.firstWhere((t) => t.id == 7);
      expect(unlinked.title, 'Projesiz görev');
      expect(unlinked.projectId, isNull);
      expect(unlinked.dueDate, DateTime(2026, 11, 25));
    });

    test('projectId matches the raw project_id for every task', () {
      for (var i = 0; i < raw.length; i++) {
        expect(tasks[i].projectId, raw[i]['project_id'], reason: 'task ${raw[i]['id']}');
      }
      expect(tasks.where((t) => t.projectId != null).map((t) => t.projectId).toSet(), {1, 5});
    });

    test('round-trip toJson -> fromJson keeps a set projectId', () {
      final linked = tasks.firstWhere((t) => t.id == 1);
      expect(linked.projectId, 1);
      final json = linked.toJson();
      expect(json['project_id'], 1);
      final back = Task.fromJson(json);
      expect(back, linked);
      expect(back.projectId, 1);
    });

    test('round-trip toJson -> fromJson keeps a null projectId as explicit null', () {
      final unlinked = tasks.firstWhere((t) => t.id == 7);
      final json = unlinked.toJson();
      expect(json.containsKey('project_id'), isTrue);
      expect(json['project_id'], isNull);
      final back = Task.fromJson(json);
      expect(back, unlinked);
      expect(back.projectId, isNull);
    });

    test('older payload without the project_id key parses projectId as null', () {
      // daily_plan_with_tasks.json predates project_id (see report note).
      final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
          as Map<String, dynamic>;
      final first = (json['tasks'] as List).first as Map<String, dynamic>;
      expect(first.containsKey('project_id'), isFalse);
      expect(Task.fromJson(first).projectId, isNull);
    });
  });
}
