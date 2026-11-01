import 'package:flutter_test/flutter_test.dart';
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
}