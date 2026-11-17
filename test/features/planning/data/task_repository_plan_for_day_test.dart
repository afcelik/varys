import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';

class _MockApiClient extends Mock implements ApiClient {}

/// A task JSON as the real backend returns it, planned for 2026-11-17.
Map<String, dynamic> _serverTaskJson() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  return Map<String, dynamic>.from((json['tasks'] as List).first as Map)
    ..['id'] = 7
    ..['planned_date'] = '2026-11-17T00:00:00';
}

DioException _error(DioExceptionType type, {int? status}) {
  final options = RequestOptions(path: '/tasks/7');
  return DioException(
    requestOptions: options,
    type: type,
    response: status == null
        ? null
        : Response(requestOptions: options, statusCode: status, data: {'detail': 'Task not found'}),
  );
}

void main() {
  late _MockApiClient api;
  late TaskRepositoryImpl repository;

  setUp(() {
    api = _MockApiClient();
    repository = TaskRepositoryImpl(api);
  });

  group('planForDay', () {
    test('PATCHes /tasks/{id} with ONLY planned_date as YYYY-MM-DDT00:00:00, no TZ suffix',
        () async {
      when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (inv) async => Response(
          requestOptions: RequestOptions(path: inv.positionalArguments.first as String),
          statusCode: 200,
          data: _serverTaskJson(),
        ),
      );

      // Time part and a UTC instant must not leak into the body.
      final result = await repository.planForDay(7, DateTime(2026, 11, 17, 23, 45));

      final captured =
          verify(() => api.patch<Map<String, dynamic>>(captureAny(), data: captureAny(named: 'data')))
              .captured;
      expect(captured[0], '/tasks/7');
      final body = captured[1] as Map<String, dynamic>;
      expect(body.keys.toSet(), {'planned_date'});
      final sent = body['planned_date'] as String;
      expect(sent, '2026-11-17T00:00:00');
      expect(sent, isNot(contains('Z')));
      expect(sent, isNot(contains('+')));
      expect(sent, isNot(contains('.')));

      final task = result.fold((f) => fail('expected Right, got $f'), (t) => t);
      expect(task.id, 7);
      expect(task.plannedDate, DateTime(2026, 11, 17));
      expect(task.status, TaskStatus.todo);
    });

    test('404 maps to the fixed Turkish message (backend detail not exposed)', () async {
      when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(_error(DioExceptionType.badResponse, status: 404));

      final result = await repository.planForDay(7, DateTime(2026, 11, 17));

      final failure = result.fold((f) => f, (_) => fail('expected Left'));
      expect(failure, isA<ServerFailure>());
      expect((failure as ServerFailure).statusCode, 404);
      expect(userMessage(failure), 'Kaynak bulunamadı.');
      expect(userMessage(failure), isNot(contains('not found')));
    });

    test('422 maps to the fixed Turkish message', () async {
      when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(_error(DioExceptionType.badResponse, status: 422));

      final result = await repository.planForDay(7, DateTime(2026, 11, 17));

      final failure = result.fold((f) => f, (_) => fail('expected Left'));
      expect(userMessage(failure), 'Gönderilen veriler geçersiz.');
    });

    test('connection error maps to NetworkFailure', () async {
      when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(_error(DioExceptionType.connectionError));

      final result = await repository.planForDay(7, DateTime(2026, 11, 17));

      final failure = result.fold((f) => f, (_) => fail('expected Left'));
      expect(failure, isA<NetworkFailure>());
      expect(userMessage(failure), 'Bağlantı hatası');
    });

    test('unexpected exception becomes UnknownFailure, never thrown', () async {
      when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')))
          .thenThrow(StateError('boom'));

      final result = await repository.planForDay(7, DateTime(2026, 11, 17));

      final failure = result.fold((f) => f, (_) => fail('expected Left'));
      expect(failure, isA<UnknownFailure>());
      expect(userMessage(failure), 'Beklenmeyen bir hata oluştu');
    });
  });
}
