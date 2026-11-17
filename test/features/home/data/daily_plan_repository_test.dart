import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

DioException _badResponse(int status, Map<String, dynamic> body) {
  final options = RequestOptions(path: '/daily-plans/2026-11-01T00:00:00');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: body),
  );
}

void main() {
  late _MockApiClient api;
  late DailyPlanRepository repository;
  final day = DateTime(2026, 11, 1);

  setUp(() {
    api = _MockApiClient();
    repository = DailyPlanRepository(api);
  });

  test('PUT 422 with English backend detail maps to the fixed Turkish message', () async {
    when(() => api.put<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenThrow(
      _badResponse(422, {'detail': 'Main focus and side focus cannot be the same task'}),
    );

    final result = await repository.updatePlan(day, sideFocusTaskId: 3);

    final failure = result.fold((f) => f, (_) => fail('expected Left'));
    expect(failure, isA<ServerFailure>());
    expect((failure as ServerFailure).statusCode, 422);
    expect(failure.userMessage, DailyPlanRepository.planUpdateInvalidMessage);
    expect(failure.userMessage, isNot(contains('focus')));
    expect(failure.message, isNot(contains('cannot')));
  });

  test('PUT 422 with Turkish-looking detail is not passed through either', () async {
    when(() => api.put<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenThrow(
      _badResponse(422, {'detail': 'Görev zaten ana odak olarak atanmış'}),
    );

    final result = await repository.updatePlan(day, mainFocusTaskId: 3);

    final failure = result.fold((f) => f, (_) => fail('expected Left'));
    expect(failure.userMessage, DailyPlanRepository.planUpdateInvalidMessage);
  });

  test('GET 422 keeps the generic fixed message, never the detail', () async {
    when(() => api.get<Map<String, dynamic>>(any())).thenThrow(
      _badResponse(422, {'detail': 'Invalid date format'}),
    );

    final result = await repository.getPlan(day);

    final failure = result.fold((f) => f, (_) => fail('expected Left'));
    expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
  });
}
