import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';

class _MockApiClient extends Mock implements ApiClient {}

/// A task JSON as the real backend returns it (from the fixture).
Map<String, dynamic> _serverTaskJson() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  return Map<String, dynamic>.from((json['tasks'] as List).first as Map)..['id'] = 7;
}

Future<Response<Map<String, dynamic>>> _ok(Invocation inv) async => Response(
      requestOptions: RequestOptions(path: inv.positionalArguments.first as String),
      statusCode: 200,
      data: _serverTaskJson(),
    );

void _expectDayFormat(Object? sent, String day) {
  expect(sent, '${day}T00:00:00');
  final s = sent as String;
  expect(s, isNot(contains('Z')));
  expect(s, isNot(contains('+')));
  expect(s, isNot(contains('.')));
}

void main() {
  late _MockApiClient api;
  late TaskRepositoryImpl repository;

  setUp(() {
    api = _MockApiClient();
    repository = TaskRepositoryImpl(api);
    when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(_ok);
    when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(_ok);
  });

  Map<String, dynamic> patchedBody() {
    final captured =
        verify(() => api.patch<Map<String, dynamic>>(captureAny(), data: captureAny(named: 'data')))
            .captured;
    expect(captured[0], '/tasks/7');
    final body = captured[1] as Map<String, dynamic>;
    expect(() => jsonEncode(body), returnsNormally);
    return body;
  }

  Map<String, dynamic> postedBody() {
    final captured =
        verify(() => api.post<Map<String, dynamic>>(captureAny(), data: captureAny(named: 'data')))
            .captured;
    expect(captured[0], '/tasks');
    final body = captured[1] as Map<String, dynamic>;
    expect(() => jsonEncode(body), returnsNormally);
    return body;
  }

  group('updateTask body', () {
    test('clear planned_date → key present with explicit null, nothing else sent', () async {
      final result = await repository.updateTask(7, plannedDate: const PlanField.clear());

      final body = patchedBody();
      expect(body.keys.toSet(), {'planned_date'});
      expect(body.containsKey('planned_date'), isTrue);
      expect(body['planned_date'], isNull);
      expect(jsonEncode(body), '{"planned_date":null}');
      final task = result.fold((f) => fail('expected Right, got $f'), (t) => t);
      expect(task.id, 7);
    });

    test('clear due_date → key present with explicit null, nothing else sent', () async {
      await repository.updateTask(7, dueDate: const PlanField.clear());

      final body = patchedBody();
      expect(body.keys.toSet(), {'due_date'});
      expect(body['due_date'], isNull);
      expect(jsonEncode(body), '{"due_date":null}');
    });

    test('set dates → YYYY-MM-DDT00:00:00 even for a 23:45 input, no Z/+ suffix', () async {
      await repository.updateTask(
        7,
        plannedDate: PlanField.set(DateTime(2026, 11, 17, 23, 45)),
        dueDate: PlanField.set(DateTime(2026, 11, 20, 23, 45)),
      );

      final body = patchedBody();
      expect(body.keys.toSet(), {'planned_date', 'due_date'});
      _expectDayFormat(body['planned_date'], '2026-11-17');
      _expectDayFormat(body['due_date'], '2026-11-20');
    });

    test('unset fields → keys absent; only the changed field is sent', () async {
      await repository.updateTask(7, title: 'Yeni başlık');

      final body = patchedBody();
      expect(body, {'title': 'Yeni başlık'});
      expect(body.containsKey('planned_date'), isFalse);
      expect(body.containsKey('due_date'), isFalse);
      expect(body.containsKey('description'), isFalse);
      expect(body.containsKey('status'), isFalse);
    });

    test('mixed: title + clear due_date + set planned_date', () async {
      await repository.updateTask(
        7,
        title: 'Rapor',
        dueDate: const PlanField.clear(),
        plannedDate: PlanField.set(DateTime(2026, 11, 18)),
      );

      final body = patchedBody();
      expect(body.keys.toSet(), {'title', 'due_date', 'planned_date'});
      expect(body['title'], 'Rapor');
      expect(body['due_date'], isNull);
      _expectDayFormat(body['planned_date'], '2026-11-18');
    });

    test('status todo is sent (not dropped as a default)', () async {
      await repository.updateTask(7, status: TaskStatus.todo);

      expect(patchedBody(), {'status': 'todo'});
    });

    test('description clear → explicit null; set → value', () async {
      await repository.updateTask(7, description: const PlanField.clear());
      expect(patchedBody(), {'description': null});

      await repository.updateTask(7, description: const PlanField.set('Not'));
      expect(patchedBody(), {'description': 'Not'});
    });
  });

  group('createTask body', () {
    Task newTask({DateTime? planned, DateTime? due}) => Task(
          id: 0,
          title: 'Yeni iş',
          status: TaskStatus.todo,
          createdAt: DateTime(2026, 11, 17),
          updatedAt: DateTime(2026, 11, 17),
          plannedDate: planned,
          dueDate: due,
        );

    test('dates are sent as YYYY-MM-DDT00:00:00 (23:45 input included)', () async {
      final result = await repository.createTask(
        newTask(planned: DateTime(2026, 11, 17, 23, 45), due: DateTime(2026, 11, 21, 23, 45)),
      );

      final body = postedBody();
      expect(body.keys.toSet(), {'title', 'planned_date', 'due_date'});
      expect(body['title'], 'Yeni iş');
      _expectDayFormat(body['planned_date'], '2026-11-17');
      _expectDayFormat(body['due_date'], '2026-11-21');
      expect(result.isRight(), isTrue);
    });

    test('null dates → keys absent', () async {
      await repository.createTask(newTask());

      expect(postedBody(), {'title': 'Yeni iş'});
    });
  });
}
