import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
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
}
