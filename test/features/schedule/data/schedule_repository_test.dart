import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';

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

Failure _left<T>(Either<Failure, T> result) => result.fold((f) => f, (_) => fail('expected Left'));

T _right<T>(Either<Failure, T> result) =>
    result.fold((f) => fail('expected Right, got $f'), (r) => r);

ScheduleTime _t(String s) => ScheduleTime.parse(s);

void main() {
  late _MockApiClient api;
  late ScheduleRepositoryImpl repository;

  setUp(() {
    api = _MockApiClient();
    repository = ScheduleRepositoryImpl(api);
  });

  group('getBlocks', () {
    test('GETs /schedule and parses the real list', () async {
      when(
        () => api.get<List<dynamic>>(any()),
      ).thenAnswer((_) async => _ok('/schedule', 200, _read('schedule_list.json') as List));
      final list = _right(await repository.getBlocks());
      verify(() => api.get<List<dynamic>>('/schedule')).called(1);
      expect(list.map((b) => b.id), [6, 1, 2, 3, 7, 4, 5]);
    });

    test('500 -> fixed text, backend detail never leaks', () async {
      when(
        () => api.get<List<dynamic>>(any()),
      ).thenThrow(_bad('/schedule', 500, body: {'detail': 'Traceback secret'}));
      final failure = _left(await repository.getBlocks());
      expect((failure as ServerFailure).statusCode, 500);
      expect(failure.userMessage, 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.');
      expect(failure.message, isNot(contains('secret')));
    });

    test('malformed time in the body -> UnknownFailure with the fixed message', () async {
      final raw = (_read('schedule_list.json') as List).cast<Map<String, dynamic>>();
      final bad = [Map<String, dynamic>.from(raw.first)..['start_time'] = '08:30:00'];
      when(() => api.get<List<dynamic>>(any())).thenAnswer((_) async => _ok('/schedule', 200, bad));
      final failure = _left(await repository.getBlocks());
      expect(failure, isA<UnknownFailure>());
      expect(failure.userMessage, 'Beklenmeyen bir hata oluştu');
    });
  });

  group('getBlocksForDay', () {
    test('GETs /schedule/day/YYYY-MM-DD (time part never leaks)', () async {
      const path = '/schedule/day/2026-11-02';
      when(
        () => api.get<List<dynamic>>(any()),
      ).thenAnswer((_) async => _ok(path, 200, _read('schedule_day.json') as List));
      final list = _right(await repository.getBlocksForDay(DateTime(2026, 11, 2, 23, 59)));
      verify(() => api.get<List<dynamic>>(path)).called(1);
      expect(list.map((b) => b.id), [6, 1, 2, 3, 7, 5]);
    });

    test('empty day is success', () async {
      when(
        () => api.get<List<dynamic>>(any()),
      ).thenAnswer((_) async => _ok('/schedule/day/2000-01-01', 200, []));
      expect(_right(await repository.getBlocksForDay(DateTime(2000))), isEmpty);
      verify(() => api.get<List<dynamic>>('/schedule/day/2000-01-01')).called(1);
    });

    test('connection error -> NetworkFailure', () async {
      when(() => api.get<List<dynamic>>(any())).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/schedule/day/2026-11-02'),
          type: DioExceptionType.connectionError,
        ),
      );
      final failure = _left(await repository.getBlocksForDay(DateTime(2026, 11, 2)));
      expect(failure, isA<NetworkFailure>());
      expect(failure.userMessage, isNot(contains('Exception')));
    });
  });

  Map<String, dynamic> encoded(Object? captured) {
    expect(captured, isNotNull);
    // Must survive real JSON encoding exactly as dio would send it.
    return jsonDecode(jsonEncode(captured)) as Map<String, dynamic>;
  }

  group('createBlock', () {
    setUp(() {
      when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => _ok('/schedule', 201, _read('schedule_created.json') as Map<String, dynamic>),
      );
    });

    Map<String, dynamic> captured() => encoded(
      verify(
        () => api.post<Map<String, dynamic>>('/schedule', data: captureAny(named: 'data')),
      ).captured.single,
    );

    test('POSTs the full body: nine keys, unrelated fields null, HH:MM, plain date', () async {
      final result = await repository.createBlock(
        title: 'Öğle yemeği',
        description: 'Ofiste',
        startTime: _t('12:30'),
        endTime: _t('13:15'),
        recurrenceType: RecurrenceType.daily,
        startDate: DateTime(2026, 11, 2, 23, 59),
      );
      expect(captured(), {
        'title': 'Öğle yemeği',
        'description': 'Ofiste',
        'start_time': '12:30',
        'end_time': '13:15',
        'recurrence_type': 'daily',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': null,
        'start_date': '2026-11-02',
      });
      final created = _right(result);
      expect(created.id, 8);
      expect(created.startTime.hhmm, '12:30');
    });

    test(
      'every type: JSON-encodable, wire type string, sorted days, times without seconds',
      () async {
        final cases = {
          RecurrenceType.daily: (null, null, null),
          RecurrenceType.weekly: ([6, 1], null, null),
          RecurrenceType.monthly: (null, 31, null),
          RecurrenceType.interval: (null, null, 3),
        };
        for (final e in cases.entries) {
          clearInteractions(api);
          await repository.createBlock(
            title: 'B',
            startTime: _t('00:00'),
            endTime: _t('23:59'),
            recurrenceType: e.key,
            daysOfWeek: e.value.$1,
            dayOfMonth: e.value.$2,
            intervalDays: e.value.$3,
            startDate: DateTime(2000, 1, 1),
          );
          final raw =
              verify(
                    () => api.post<Map<String, dynamic>>(
                      '/schedule',
                      data: captureAny(named: 'data'),
                    ),
                  ).captured.single
                  as Map<String, dynamic>;
          expect(() => jsonEncode(raw), returnsNormally);
          expect(raw['recurrence_type'], e.key.apiValue);
          expect(raw['start_time'], '00:00');
          expect(raw['end_time'], '23:59');
          expect(raw['start_time'], matches(RegExp(r'^[0-9]{2}:[0-9]{2}$')));
          expect(raw['start_date'], '2000-01-01');
          expect(raw.containsKey('days_of_week'), isTrue);
          expect(raw.containsKey('day_of_month'), isTrue);
          expect(raw.containsKey('interval_days'), isTrue);
          if (e.key == RecurrenceType.weekly) expect(raw['days_of_week'], [1, 6]);
        }
      },
    );

    test('422 (pydantic list body) -> fixed text, detail never leaks', () async {
      when(
        () => api.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(_bad('/schedule', 422, body: _read('schedule_create_seconds_422.json')));
      final failure = _left(
        await repository.createBlock(
          title: 'S',
          startTime: _t('08:30'),
          endTime: _t('09:00'),
          recurrenceType: RecurrenceType.daily,
          startDate: DateTime(2026, 11, 2),
        ),
      );
      expect((failure as ServerFailure).statusCode, 422);
      expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
      expect(failure.message, isNot(contains('HH:MM')));
    });
  });

  group('updateBlock', () {
    setUp(() {
      when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async =>
            _ok('/schedule/1', 200, _read('schedule_updated_cleared.json') as Map<String, dynamic>),
      );
    });

    Map<String, dynamic> captured() => encoded(
      verify(
        () => api.patch<Map<String, dynamic>>('/schedule/1', data: captureAny(named: 'data')),
      ).captured.single,
    );

    test('PATCHes /schedule/{id} with only the set fields; unset keys absent', () async {
      final result = await repository.updateBlock(
        1,
        ScheduleChanges(title: const PlanField.set('Koşu'), endTime: PlanField.set(_t('07:30'))),
      );
      final body = captured();
      expect(body, {'title': 'Koşu', 'end_time': '07:30'});
      for (final key in [
        'description',
        'start_time',
        'recurrence_type',
        'days_of_week',
        'day_of_month',
        'interval_days',
      ]) {
        expect(body.containsKey(key), isFalse, reason: key);
      }
      expect(_right(result).id, 1);
    });

    test('cleared description: key present, value null; the result has it cleared', () async {
      final result = await repository.updateBlock(
        1,
        const ScheduleChanges(description: PlanField.clear()),
      );
      final body = captured();
      expect(body, {'description': null});
      expect(body.containsKey('description'), isTrue);
      expect(_right(result).description, isNull);
    });

    test('start_date is never in the body, whatever the form changed', () async {
      final original = ScheduleBlock.fromJson(
        (_read('schedule_list.json') as List).first as Map<String, dynamic>,
      );
      final changes = computeScheduleChanges(
        original,
        title: 'Yeni',
        description: '',
        startTime: _t('01:00'),
        endTime: _t('02:00'),
        recurrence: const RecurrenceFormState(type: RecurrenceType.weekly, days: {0}),
      );
      await repository.updateBlock(1, changes);
      final body = captured();
      expect(body.containsKey('start_date'), isFalse);
      expect(body, {
        'title': 'Yeni',
        'description': null,
        'start_time': '01:00',
        'end_time': '02:00',
        'recurrence_type': 'weekly',
        'days_of_week': [0],
        'day_of_month': null,
        'interval_days': null,
      });
    });

    test('times are HH:MM strings (no seconds); body JSON-encodable', () async {
      await repository.updateBlock(
        1,
        ScheduleChanges(startTime: PlanField.set(_t('00:00')), endTime: PlanField.set(_t('23:59'))),
      );
      final raw =
          verify(
                () =>
                    api.patch<Map<String, dynamic>>('/schedule/1', data: captureAny(named: 'data')),
              ).captured.single
              as Map<String, dynamic>;
      expect(() => jsonEncode(raw), returnsNormally);
      expect(raw, {'start_time': '00:00', 'end_time': '23:59'});
    });

    test('404 -> "Kaynak bulunamadı.", detail never leaks', () async {
      when(
        () => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(_bad('/schedule/1', 404, body: _read('schedule_update_404.json')));
      final failure = _left(
        await repository.updateBlock(1, const ScheduleChanges(title: PlanField.set('x'))),
      );
      expect((failure as ServerFailure).statusCode, 404);
      expect(failure.userMessage, 'Kaynak bulunamadı.');
      expect(failure.message, isNot(contains('Schedule block')));
    });

    test('422 merged-state error (plain detail) -> fixed text, detail never leaks', () async {
      when(
        () => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(_bad('/schedule/1', 422, body: _read('schedule_update_range_422.json')));
      final failure = _left(
        await repository.updateBlock(1, ScheduleChanges(endTime: PlanField.set(_t('06:00')))),
      );
      expect((failure as ServerFailure).statusCode, 422);
      expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
      expect(failure.message, isNot(contains('end_time')));
    });
  });

  group('deleteBlock', () {
    // Real DELETE /schedule/{id}: 204 with an empty body.
    const deleteStatus = 204;

    test('DELETEs /schedule/{id}; 204 with an empty body is success', () async {
      when(
        () => api.delete<dynamic>(any()),
      ).thenAnswer((_) async => _ok('/schedule/4', deleteStatus, null));
      final result = await repository.deleteBlock(4);
      verify(() => api.delete<dynamic>('/schedule/4')).called(1);
      expect(result.isRight(), isTrue);
    });

    test('404 -> "Kaynak bulunamadı."', () async {
      when(
        () => api.delete<dynamic>(any()),
      ).thenThrow(_bad('/schedule/4', 404, body: _read('schedule_update_404.json')));
      final failure = _left(await repository.deleteBlock(4));
      expect((failure as ServerFailure).statusCode, 404);
      expect(failure.userMessage, 'Kaynak bulunamadı.');
    });
  });
}
