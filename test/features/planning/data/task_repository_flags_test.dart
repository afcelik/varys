import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';

class _MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

/// Eisenhower flags in the create / PATCH bodies: create sends a flag only
/// when true; PATCH sends only the flags given (never null: backend 422).
void main() {
  late _MockApiClient api;
  late TaskRepositoryImpl repository;

  setUp(() {
    api = _MockApiClient();
    repository = TaskRepositoryImpl(api);
    when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
      (inv) async => Response(
        requestOptions: RequestOptions(path: '/tasks'),
        statusCode: 201,
        data: _fixture('task_created_flags.json'),
      ),
    );
    when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
      (inv) async => Response(
        requestOptions: RequestOptions(path: inv.positionalArguments.first as String),
        statusCode: 200,
        data: _fixture('task_update_flags.json'),
      ),
    );
  });

  Map<String, dynamic> postedBody() {
    final captured = verify(
      () => api.post<Map<String, dynamic>>(captureAny(), data: captureAny(named: 'data')),
    ).captured;
    expect(captured[0], '/tasks');
    return captured[1] as Map<String, dynamic>;
  }

  Map<String, dynamic> patchedBody() {
    final captured = verify(
      () => api.patch<Map<String, dynamic>>(captureAny(), data: captureAny(named: 'data')),
    ).captured;
    expect(captured[0], '/tasks/4');
    return captured[1] as Map<String, dynamic>;
  }

  group('createTask flags', () {
    test('both false → neither key in the body (backend default false)', () async {
      await repository.createTask(buildNewTask(title: 'Sunumu bitir', description: ''));

      final body = postedBody();
      expect(body.containsKey('is_important'), isFalse);
      expect(body.containsKey('is_urgent'), isFalse);
      expect(jsonEncode(body), '{"title":"Sunumu bitir"}');
    });

    test('both true → both keys true; the response task carries them', () async {
      final result = await repository.createTask(
        buildNewTask(title: 'Sunumu bitir', description: '', isImportant: true, isUrgent: true),
      );

      final body = postedBody();
      expect(body['is_important'], isTrue);
      expect(body['is_urgent'], isTrue);
      expect(jsonEncode(body), '{"title":"Sunumu bitir","is_important":true,"is_urgent":true}');
      final task = result.fold((f) => fail('expected Right, got $f'), (t) => t);
      expect((task.isImportant, task.isUrgent), (true, true));
    });

    test('only urgent true → only is_urgent sent', () async {
      await repository.createTask(
        buildNewTask(title: 'Kargo görevlisini ara', description: '', isUrgent: true),
      );

      final body = postedBody();
      expect(body.containsKey('is_important'), isFalse);
      expect(body['is_urgent'], isTrue);
    });
  });

  group('updateTask flags', () {
    test('only isUrgent given → body is exactly {is_urgent: true}', () async {
      final result = await repository.updateTask(4, isUrgent: true);

      final body = patchedBody();
      expect(jsonEncode(body), '{"is_urgent":true}');
      final task = result.fold((f) => fail('expected Right, got $f'), (t) => t);
      expect(task.isUrgent, isTrue);
    });

    test('isImportant false is sent as false (switching off), nothing else', () async {
      await repository.updateTask(4, isImportant: false);

      expect(jsonEncode(patchedBody()), '{"is_important":false}');
    });

    test('flags not given → no flag key, never an explicit null', () async {
      await repository.updateTask(4, title: 'Yeni başlık', dueDate: const PlanField.clear());

      final body = patchedBody();
      expect(body.containsKey('is_important'), isFalse);
      expect(body.containsKey('is_urgent'), isFalse);
      expect(jsonEncode(body), '{"title":"Yeni başlık","due_date":null}');
    });

    test('changes from the form: only the changed flag reaches the body', () async {
      final original = Task.fromJson(_fixture('task_created_plain.json'));
      final changes = computeTaskChanges(
        original,
        TaskFormValues(
          title: original.title,
          description: '',
          projectId: null,
          isImportant: false,
          isUrgent: true,
        ),
      );
      await repository.updateTask(
        4,
        title: changes.title,
        description: changes.description,
        projectId: changes.projectId,
        dueDate: changes.dueDate,
        plannedDate: changes.plannedDate,
        isImportant: changes.isImportant,
        isUrgent: changes.isUrgent,
      );

      expect(jsonEncode(patchedBody()), '{"is_urgent":true}');
    });
  });
}
