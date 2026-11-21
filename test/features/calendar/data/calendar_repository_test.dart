// CalendarRepositoryImpl: path and query, real backend JSON, and fixed error
// texts (backend detail never leaks).

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/calendar/data/calendar_repository_impl.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';

class _MockApiClient extends Mock implements ApiClient {}

Map<String, dynamic> _read(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

Response<T> _ok<T>(T? data) => Response<T>(
  requestOptions: RequestOptions(path: CalendarRepositoryImpl.monthPath),
  statusCode: 200,
  data: data,
);

DioException _bad(int status, {Object? body}) {
  final options = RequestOptions(path: CalendarRepositoryImpl.monthPath);
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: body),
  );
}

Failure _left<T>(Either<Failure, T> result) => result.fold((f) => f, (_) => fail('expected Left'));

T _right<T>(Either<Failure, T> result) =>
    result.fold((f) => fail('expected Right, got $f'), (r) => r);

void main() {
  late _MockApiClient api;
  late CalendarRepositoryImpl repository;

  setUp(() {
    api = _MockApiClient();
    repository = CalendarRepositoryImpl(api);
  });

  void stubGet(Future<Response<Map<String, dynamic>>> Function() answer) {
    when(
      () => api.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) => answer());
  }

  test('GETs /calendar/month with year and month as query, parses the real month', () async {
    stubGet(() async => _ok(_read('calendar_month_2026_11.json')));
    final month = _right(await repository.getMonth(2026, 11));
    verify(
      () => api.get<Map<String, dynamic>>(
        '/calendar/month',
        queryParameters: {'year': 2026, 'month': 11},
      ),
    ).called(1);
    expect((month.year, month.month, month.days.length), (2026, 11, 30));
    expect(month.days[20].day, DateTime(2026, 11, 21));
  });

  test('passes the requested month through (leap February)', () async {
    stubGet(() async => _ok(_read('calendar_month_2024_02.json')));
    final month = _right(await repository.getMonth(2024, 2));
    verify(
      () => api.get<Map<String, dynamic>>(
        '/calendar/month',
        queryParameters: {'year': 2024, 'month': 2},
      ),
    ).called(1);
    expect(month.days.last.day, DateTime(2024, 2, 29));
  });

  test('422 (real body) -> fixed text, backend detail never leaks', () async {
    final body = _read('calendar_month_422.json');
    when(
      () => api.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenThrow(_bad(422, body: body));
    final failure = _left(await repository.getMonth(2026, 13));
    expect(failure, isA<ServerFailure>());
    expect((failure as ServerFailure).statusCode, 422);
    expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
    expect(failure.message, isNot(contains('less than or equal')));
    expect(failure.message, isNot(contains('month')));
  });

  test('404 -> fixed text, detail never leaks', () async {
    when(
      () => api.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenThrow(_bad(404, body: {'detail': 'secret route detail'}));
    final failure = _left(await repository.getMonth(2026, 11));
    expect((failure as ServerFailure).statusCode, 404);
    expect(failure.userMessage, 'Kaynak bulunamadı.');
    expect(failure.message, isNot(contains('secret')));
  });

  test('500 -> fixed server text', () async {
    when(
      () => api.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenThrow(_bad(500, body: {'detail': 'Traceback secret'}));
    final failure = _left(await repository.getMonth(2026, 11));
    expect(failure.userMessage, 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.');
    expect((failure as ServerFailure).message, isNot(contains('secret')));
  });

  test('connection error -> NetworkFailure with the fixed text', () async {
    when(
      () => api.get<Map<String, dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: CalendarRepositoryImpl.monthPath),
        type: DioExceptionType.connectionError,
      ),
    );
    final failure = _left(await repository.getMonth(2026, 11));
    expect(failure, isA<NetworkFailure>());
    expect(failure.userMessage, 'Bağlantı hatası');
  });

  test('malformed day in the body -> UnknownFailure with the fixed text', () async {
    final raw = _read('calendar_month_2026_11.json');
    final days = (raw['days'] as List).cast<Map<String, dynamic>>();
    final bad = {
      ...raw,
      'days': [
        {...days.first, 'day': '2026-11-01T00:00:00Z'},
        ...days.skip(1),
      ],
    };
    stubGet(() async => _ok(bad));
    final failure = _left(await repository.getMonth(2026, 11));
    expect(failure, isA<UnknownFailure>());
    expect(failure.userMessage, 'Beklenmeyen bir hata oluştu');
  });

  test('a missing count field -> UnknownFailure (no silent zero)', () async {
    final raw = _read('calendar_month_2026_11.json');
    final days = (raw['days'] as List).cast<Map<String, dynamic>>();
    final bad = {
      ...raw,
      'days': [Map<String, dynamic>.from(days.first)..remove('due_count'), ...days.skip(1)],
    };
    stubGet(() async => _ok(bad));
    expect(_left(await repository.getMonth(2026, 11)), isA<UnknownFailure>());
    // The real JSON still parses (the stub above is the only difference).
    expect(CalendarMonth.fromJson(raw).days, hasLength(30));
  });
}
