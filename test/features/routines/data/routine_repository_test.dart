import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';

class _MockApiClient extends Mock implements ApiClient {}

Response<T> _ok<T>(String path, int status, T? data) =>
    Response<T>(requestOptions: RequestOptions(path: path), statusCode: status, data: data);

DioException _bad(String path, int status, {Object? body}) {
  final options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: body),
  );
}

Failure _left<T>(Either<Failure, T> result) =>
    result.fold((f) => f, (_) => fail('expected Left'));

void main() {
  late _MockApiClient api;
  late RoutineRepositoryImpl repository;
  final day = DateTime(2026, 11, 16, 23, 59); // time part must not leak
  const dayPath = '/routines/day/2026-11-16';
  const logPath = '/routines/7/logs/2026-11-16';

  late List<dynamic> dayFixture;
  late Map<String, dynamic> logFixture;

  setUpAll(() {
    dayFixture =
        jsonDecode(File('test/fixtures/routines_day.json').readAsStringSync()) as List<dynamic>;
    logFixture = jsonDecode(File('test/fixtures/routine_log.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  setUp(() {
    api = _MockApiClient();
    repository = RoutineRepositoryImpl(api);
  });

  group('getRoutinesForDay', () {
    test('GETs /routines/day/YYYY-MM-DD and parses the real response', () async {
      when(() => api.get<List<dynamic>>(any()))
          .thenAnswer((_) async => _ok(dayPath, 200, dayFixture));

      final result = await repository.getRoutinesForDay(day);

      verify(() => api.get<List<dynamic>>(dayPath)).called(1);
      final items = result.fold((f) => fail('expected Right, got $f'), (r) => r);
      expect(items.map((i) => i.id), [1, 2, 3, 4]);
      expect(items.first.recurrenceType, RecurrenceType.daily);
      expect(items.first.currentStreak, 3);
    });

    test('empty list is success', () async {
      when(() => api.get<List<dynamic>>(any())).thenAnswer((_) async => _ok(dayPath, 200, []));
      final result = await repository.getRoutinesForDay(day);
      expect(result.fold((f) => fail('expected Right'), (r) => r), isEmpty);
    });

    test('malformed body maps to UnknownFailure with the fixed message', () async {
      when(() => api.get<List<dynamic>>(any())).thenAnswer((_) async => _ok(dayPath, 200, [
            {'id': 'not-an-int'}
          ]));
      final failure = _left(await repository.getRoutinesForDay(day));
      expect(failure, isA<UnknownFailure>());
      expect(failure.userMessage, 'Beklenmeyen bir hata oluştu');
    });
  });

  group('markDone', () {
    test('PUTs the log path; 201 is success', () async {
      when(() => api.put<dynamic>(any())).thenAnswer((_) async => _ok(logPath, 201, logFixture));
      final result = await repository.markDone(7, day);
      verify(() => api.put<dynamic>(logPath)).called(1);
      expect(result.isRight(), isTrue);
    });

    test('200 (already completed, idempotent) is success too', () async {
      when(() => api.put<dynamic>(any())).thenAnswer((_) async => _ok(logPath, 200, logFixture));
      expect((await repository.markDone(7, day)).isRight(), isTrue);
    });

    test('422 (not scheduled) maps to fixed Turkish text, backend detail never leaks', () async {
      when(() => api.put<dynamic>(any())).thenThrow(
          _bad(logPath, 422, body: {'detail': 'Routine 7 is not scheduled on 2026-11-16'}));
      final failure = _left(await repository.markDone(7, day));
      expect(failure, isA<ServerFailure>());
      expect((failure as ServerFailure).statusCode, 422);
      expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
      expect(failure.message, isNot(contains('scheduled')));
    });
  });

  group('undo', () {
    test('DELETEs the log path; 204 is success', () async {
      when(() => api.delete<dynamic>(any())).thenAnswer((_) async => _ok(logPath, 204, null));
      final result = await repository.undo(7, day);
      verify(() => api.delete<dynamic>(logPath)).called(1);
      expect(result.isRight(), isTrue);
    });

    test('404 maps to ServerFailure "Kaynak bulunamadı."', () async {
      when(() => api.delete<dynamic>(any()))
          .thenThrow(_bad(logPath, 404, body: {'detail': 'Routine 7 not found'}));
      final failure = _left(await repository.undo(7, day));
      expect((failure as ServerFailure).statusCode, 404);
      expect(failure.userMessage, 'Kaynak bulunamadı.');
    });
  });

  group('failure mapping', () {
    test('500 maps to the server error message', () async {
      when(() => api.get<List<dynamic>>(any())).thenThrow(_bad(dayPath, 500));
      final failure = _left(await repository.getRoutinesForDay(day));
      expect((failure as ServerFailure).statusCode, 500);
      expect(failure.userMessage, 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.');
    });

    test('401 maps to the session message', () async {
      when(() => api.put<dynamic>(any())).thenThrow(_bad(logPath, 401));
      final failure = _left(await repository.markDone(7, day));
      expect(failure.userMessage, 'Oturum süresi doldu. Lütfen tekrar giriş yapın.');
    });

    test('connection error maps to NetworkFailure', () async {
      when(() => api.delete<dynamic>(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: logPath),
        type: DioExceptionType.connectionError,
      ));
      final failure = _left(await repository.undo(7, day));
      expect(failure, isA<NetworkFailure>());
      expect(failure.userMessage, isNot(contains('Exception')));
    });
  });

  group('CRUD', () {
    late List<dynamic> listFixture;
    late Map<String, dynamic> createdFixture;

    setUpAll(() {
      listFixture = jsonDecode(File('test/fixtures/routines_list.json').readAsStringSync())
          as List<dynamic>;
      createdFixture = jsonDecode(File('test/fixtures/routine_created.json').readAsStringSync())
          as Map<String, dynamic>;
    });

    Map<String, dynamic> sentBody(Map<String, dynamic>? captured) {
      expect(captured, isNotNull);
      // Must survive real JSON encoding exactly as dio would send it.
      return jsonDecode(jsonEncode(captured)) as Map<String, dynamic>;
    }

    group('getRoutines', () {
      test('GETs /routines and parses the real list', () async {
        when(() => api.get<List<dynamic>>(any()))
            .thenAnswer((_) async => _ok('/routines', 200, listFixture));
        final result = await repository.getRoutines();
        verify(() => api.get<List<dynamic>>('/routines')).called(1);
        final list = result.fold((f) => fail('expected Right, got $f'), (r) => r);
        // routines_list.json predates 'once' (covered by routines_list_with_once.json).
        expect(list.map((r) => r.recurrenceType), [
          RecurrenceType.daily,
          RecurrenceType.weekly,
          RecurrenceType.monthly,
          RecurrenceType.interval,
        ]);
      });

      test('500 -> ServerFailure with fixed text', () async {
        when(() => api.get<List<dynamic>>(any())).thenThrow(
            _bad('/routines', 500, body: {'detail': 'Traceback secret'}));
        final failure = _left(await repository.getRoutines());
        expect((failure as ServerFailure).statusCode, 500);
        expect(failure.userMessage, 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.');
        expect(failure.message, isNot(contains('secret')));
      });
    });

    group('createRoutine', () {
      setUp(() {
        when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data')))
            .thenAnswer((_) async => _ok('/routines', 201, createdFixture));
      });

      Map<String, dynamic> captured() => sentBody(verify(() =>
              api.post<Map<String, dynamic>>('/routines', data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>);

      test('POSTs the full body: all seven keys, unrelated fields null, plain date', () async {
        final result = await repository.createRoutine(
          title: 'Spor',
          recurrenceType: RecurrenceType.weekly,
          daysOfWeek: [4, 0, 2],
          startDate: DateTime(2026, 11, 2, 23, 59),
        );
        expect(captured(), {
          'title': 'Spor',
          'description': null,
          'recurrence_type': 'weekly',
          'days_of_week': [0, 2, 4],
          'day_of_month': null,
          'interval_days': null,
          'start_date': '2026-11-02',
        });
        final created = result.fold((f) => fail('expected Right, got $f'), (r) => r);
        expect(created.id, 2);
        expect(created.daysOfWeek, [0, 2, 4]);
      });

      test('body is JSON-encodable for every type; type is the wire string', () async {
        final cases = {
          RecurrenceType.daily: (null, null, null),
          RecurrenceType.weekly: ([6, 1], null, null),
          RecurrenceType.monthly: (null, 31, null),
          RecurrenceType.interval: (null, null, 3),
        };
        for (final e in cases.entries) {
          clearInteractions(api);
          await repository.createRoutine(
            title: 'R',
            description: 'D',
            recurrenceType: e.key,
            daysOfWeek: e.value.$1,
            dayOfMonth: e.value.$2,
            intervalDays: e.value.$3,
            startDate: DateTime(2000, 1, 1),
          );
          final raw = verify(() => api.post<Map<String, dynamic>>('/routines',
              data: captureAny(named: 'data'))).captured.single as Map<String, dynamic>;
          expect(() => jsonEncode(raw), returnsNormally);
          expect(raw['recurrence_type'], e.key.apiValue);
          expect(raw['recurrence_type'], isA<String>());
          expect(raw['start_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
          expect(raw['start_date'], '2000-01-01');
          if (e.key == RecurrenceType.weekly) expect(raw['days_of_week'], [1, 6]);
        }
      });

      test('201 is success', () async {
        final result = await repository.createRoutine(
            title: 'S', recurrenceType: RecurrenceType.daily, startDate: DateTime(2026, 11, 2));
        expect(result.isRight(), isTrue);
      });

      test('422 -> fixed text, backend detail never leaks', () async {
        when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenThrow(
            _bad('/routines', 422, body: {'detail': 'days_of_week required for weekly'}));
        final failure = _left(await repository.createRoutine(
            title: 'S', recurrenceType: RecurrenceType.weekly, startDate: DateTime(2026)));
        expect((failure as ServerFailure).statusCode, 422);
        expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
        expect(failure.message, isNot(contains('days_of_week')));
      });
    });

    group('updateRoutine', () {
      setUp(() {
        when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')))
            .thenAnswer((_) async => _ok('/routines/2', 200, createdFixture));
      });

      Map<String, dynamic> captured() => sentBody(verify(() =>
              api.patch<Map<String, dynamic>>('/routines/2', data: captureAny(named: 'data')))
          .captured
          .single as Map<String, dynamic>);

      test('PATCHes /routines/{id} with only the set fields; unset keys absent', () async {
        final result =
            await repository.updateRoutine(2, const RoutineChanges(title: PlanField.set('Koşu')));
        expect(captured(), {'title': 'Koşu'});
        expect(result.fold((f) => fail('expected Right'), (r) => r.id), 2);
      });

      test('cleared description is sent as explicit null', () async {
        await repository.updateRoutine(2, const RoutineChanges(description: PlanField.clear()));
        final body = captured();
        expect(body, {'description': null});
        expect(body.containsKey('description'), isTrue);
      });

      test('weekly -> daily (from the form diff): days_of_week explicit null', () async {
        final weekly = Routine.fromJson(createdFixture);
        final changes = computeChanges(weekly,
            title: weekly.title,
            description: '',
            recurrence: RecurrenceFormState.fromRoutine(weekly)
                .copyWith(type: RecurrenceType.daily));
        await repository.updateRoutine(2, changes);
        final body = captured();
        expect(body, {
          'recurrence_type': 'daily',
          'days_of_week': null,
          'day_of_month': null,
          'interval_days': null,
        });
        expect(body.containsKey('title'), isFalse);
        expect(body.containsKey('description'), isFalse);
      });

      test('body is JSON-encodable; days sorted ints; type is a string', () async {
        await repository.updateRoutine(
            2,
            const RoutineChanges(
              recurrenceType: PlanField.set(RecurrenceType.weekly),
              daysOfWeek: PlanField.set([5, 1, 3]),
              dayOfMonth: PlanField.clear(),
              intervalDays: PlanField.clear(),
            ));
        final raw = verify(() => api.patch<Map<String, dynamic>>('/routines/2',
            data: captureAny(named: 'data'))).captured.single as Map<String, dynamic>;
        expect(() => jsonEncode(raw), returnsNormally);
        expect(raw['recurrence_type'], 'weekly');
        expect(raw['days_of_week'], [1, 3, 5]);
        expect(raw['days_of_week'], everyElement(isA<int>()));
      });

      test('404 -> "Kaynak bulunamadı.", detail never leaks', () async {
        when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')))
            .thenThrow(_bad('/routines/2', 404, body: {'detail': 'Routine 2 not found'}));
        final failure = _left(await repository.updateRoutine(
            2, const RoutineChanges(title: PlanField.set('x'))));
        expect((failure as ServerFailure).statusCode, 404);
        expect(failure.userMessage, 'Kaynak bulunamadı.');
        expect(failure.message, isNot(contains('Routine 2')));
      });

      test('422 -> fixed text', () async {
        when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')))
            .thenThrow(_bad('/routines/2', 422, body: {'detail': 'title cannot be null'}));
        final failure = _left(await repository.updateRoutine(
            2, const RoutineChanges(title: PlanField.set('x'))));
        expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
      });
    });

    group('deleteRoutine', () {
      test('DELETEs /routines/{id}; 204 is success', () async {
        when(() => api.delete<dynamic>(any())).thenAnswer((_) async => _ok('/routines/3', 204, null));
        final result = await repository.deleteRoutine(3);
        verify(() => api.delete<dynamic>('/routines/3')).called(1);
        expect(result.isRight(), isTrue);
      });

      test('404 -> "Kaynak bulunamadı."', () async {
        when(() => api.delete<dynamic>(any()))
            .thenThrow(_bad('/routines/3', 404, body: {'detail': 'Routine 3 not found'}));
        final failure = _left(await repository.deleteRoutine(3));
        expect((failure as ServerFailure).statusCode, 404);
        expect(failure.userMessage, 'Kaynak bulunamadı.');
      });

      test('timeout -> NetworkFailure with fixed text', () async {
        when(() => api.delete<dynamic>(any())).thenThrow(DioException(
          requestOptions: RequestOptions(path: '/routines/3'),
          type: DioExceptionType.receiveTimeout,
        ));
        final failure = _left(await repository.deleteRoutine(3));
        expect(failure, isA<NetworkFailure>());
        expect(failure.userMessage, 'Bağlantı hatası');
      });
    });
  });
}
