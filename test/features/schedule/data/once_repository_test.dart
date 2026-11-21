import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';

/// Repository request bodies and response parsing for the one-time ('once')
/// type, with responses from real backend JSON.

class _MockApiClient extends Mock implements ApiClient {}

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

Response<T> _ok<T>(String path, int status, T? data) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: status,
  data: data,
);

DioException _bad(String path, int status, {Object? body}) {
  final options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: body),
  );
}

T _right<T>(Either<Failure, T> result) =>
    result.fold((f) => fail('expected Right, got $f'), (r) => r);

Failure _left<T>(Either<Failure, T> result) => result.fold((f) => f, (_) => fail('expected Left'));

Map<String, dynamic> _encoded(Object? captured) {
  expect(captured, isNotNull);
  // Must survive real JSON encoding exactly as dio would send it.
  return jsonDecode(jsonEncode(captured)) as Map<String, dynamic>;
}

void main() {
  late _MockApiClient api;

  setUp(() => api = _MockApiClient());

  group('ScheduleRepositoryImpl', () {
    late ScheduleRepositoryImpl repository;

    setUp(() => repository = ScheduleRepositoryImpl(api));

    test("createBlock(once): 'once', the three fields explicit null, plain start_date", () async {
      when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async =>
            _ok('/schedule', 201, _read('schedule_created_once.json') as Map<String, dynamic>),
      );
      final result = await repository.createBlock(
        title: 'Doktor randevusu',
        description: 'Kardiyoloji, 3. kat',
        startTime: ScheduleTime.hm(14, 0),
        endTime: ScheduleTime.hm(15, 0),
        recurrenceType: RecurrenceType.once,
        startDate: DateTime(2026, 11, 25, 23, 59),
      );
      final body = _encoded(
        verify(
          () => api.post<Map<String, dynamic>>('/schedule', data: captureAny(named: 'data')),
        ).captured.single,
      );
      expect(body, {
        'title': 'Doktor randevusu',
        'description': 'Kardiyoloji, 3. kat',
        'start_time': '14:00',
        'end_time': '15:00',
        'recurrence_type': 'once',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': null,
        'start_date': '2026-11-25',
      });
      for (final key in ['days_of_week', 'day_of_month', 'interval_days']) {
        expect(body.containsKey(key), isTrue, reason: '$key must be an explicit null');
      }
      final created = _right(result);
      expect(created.recurrenceType, RecurrenceType.once);
      expect(created.startDate, DateTime(2026, 11, 25));
    });

    test('updateBlock monthly -> once: type + three explicit nulls, no start_date', () async {
      when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => _ok(
          '/schedule/3',
          200,
          _read('schedule_updated_monthly_to_once.json') as Map<String, dynamic>,
        ),
      );
      final monthly = (_read('schedule_list_with_once.json') as List)
          .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
          .firstWhere((b) => b.id == 3);
      final changes = computeScheduleChanges(
        monthly,
        title: monthly.title,
        description: monthly.description ?? '',
        startTime: monthly.startTime,
        endTime: monthly.endTime,
        recurrence: RecurrenceFormState.fromFields(
          type: RecurrenceType.once,
          dayOfMonth: monthly.dayOfMonth,
        ),
      );
      final result = await repository.updateBlock(3, changes);
      final body = _encoded(
        verify(
          () => api.patch<Map<String, dynamic>>('/schedule/3', data: captureAny(named: 'data')),
        ).captured.single,
      );
      expect(body, {
        'recurrence_type': 'once',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': null,
      });
      expect(body.containsKey('start_date'), isFalse);
      final updated = _right(result);
      expect(updated.recurrenceType, RecurrenceType.once);
      expect(updated.dayOfMonth, isNull);
    });

    test('getBlocks parses the real list containing a once block', () async {
      when(() => api.get<List<dynamic>>(any())).thenAnswer(
        (_) async => _ok('/schedule', 200, _read('schedule_list_with_once.json') as List),
      );
      final list = _right(await repository.getBlocks());
      expect(list.map((b) => b.recurrenceType), contains(RecurrenceType.once));
    });
  });

  group('RoutineRepositoryImpl', () {
    late RoutineRepositoryImpl repository;

    setUp(() => repository = RoutineRepositoryImpl(api));

    test('getRoutines parses the real list containing a once routine', () async {
      when(() => api.get<List<dynamic>>(any())).thenAnswer(
        (_) async => _ok('/routines', 200, _read('routines_list_with_once.json') as List),
      );
      final list = _right(await repository.getRoutines());
      expect(list.map((r) => r.recurrenceType), [RecurrenceType.daily, RecurrenceType.once]);
    });

    test('createRoutine(once): the three fields explicit null', () async {
      when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => _ok(
          '/routines',
          201,
          (_read('routines_list_with_once.json') as List).last as Map<String, dynamic>,
        ),
      );
      final result = await repository.createRoutine(
        title: 'Vergi beyannamesi',
        recurrenceType: RecurrenceType.once,
        startDate: DateTime(2026, 11, 25),
      );
      final body = _encoded(
        verify(
          () => api.post<Map<String, dynamic>>('/routines', data: captureAny(named: 'data')),
        ).captured.single,
      );
      expect(body['recurrence_type'], 'once');
      expect(body['start_date'], '2026-11-25');
      for (final key in ['days_of_week', 'day_of_month', 'interval_days']) {
        expect(body.containsKey(key), isTrue, reason: key);
        expect(body[key], isNull, reason: key);
      }
      expect(_right(result).recurrenceType, RecurrenceType.once);
    });

    test('422 (real once + interval_days body) -> fixed text, detail never leaks', () async {
      when(
        () => api.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(_bad('/routines', 422, body: _read('routine_create_once_interval_422.json')));
      final failure = _left(
        await repository.createRoutine(
          title: 'x',
          recurrenceType: RecurrenceType.once,
          intervalDays: 3,
          startDate: DateTime(2026, 11, 25),
        ),
      );
      expect((failure as ServerFailure).statusCode, 422);
      expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
      expect(failure.userMessage, isNot(contains('interval_days')));
      expect(failure.message, isNot(contains('interval_days')));
    });
  });
}
