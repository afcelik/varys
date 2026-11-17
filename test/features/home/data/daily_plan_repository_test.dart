import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/plan_field.dart';

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

    final result = await repository.updatePlan(day, sideFocusTaskId: const PlanField.set(3));

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

    final result = await repository.updatePlan(day, mainFocusTaskId: const PlanField.set(3));

    final failure = result.fold((f) => f, (_) => fail('expected Left'));
    expect(failure.userMessage, DailyPlanRepository.planUpdateInvalidMessage);
  });

  group('updatePlan PUT body', () {
    late Map<String, dynamic> fixture;

    setUp(() {
      fixture = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
          as Map<String, dynamic>;
    });

    /// Stubs PUT to answer with [responseJson] and returns a getter for the sent body.
    Map<String, dynamic> Function() capturePut(Map<String, dynamic> responseJson) {
      when(() => api.put<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: '/daily-plans/2026-11-01T00:00:00'),
          statusCode: 200,
          data: responseJson,
        ),
      );
      return () {
        final captured = verify(() => api.put<Map<String, dynamic>>(
              '/daily-plans/2026-11-01',
              data: captureAny(named: 'data'),
            )).captured;
        expect(captured, hasLength(1));
        return captured.single as Map<String, dynamic>;
      };
    }

    test('set main only sends just that field', () async {
      final body = capturePut(fixture);

      await repository.updatePlan(day, mainFocusTaskId: const PlanField.set(3));

      expect(body(), {'main_focus_task_id': 3});
    });

    test('clear main sends explicit null and parses the cleared response', () async {
      final body = capturePut({...fixture, 'main_focus_task_id': null, 'main_focus': null});

      final result = await repository.updatePlan(day, mainFocusTaskId: const PlanField.clear());

      final sent = body();
      expect(sent, {'main_focus_task_id': null});
      expect(sent.containsKey('main_focus_task_id'), isTrue);
      final plan = result.fold((f) => fail('expected Right, got $f'), (p) => p);
      expect(plan.mainFocus, isNull);
    });

    test('clear side sends {"side_focus_task_id": null}', () async {
      final body = capturePut(fixture);

      await repository.updatePlan(day, sideFocusTaskId: const PlanField.clear());

      expect(body(), {'side_focus_task_id': null});
    });

    test('clear say-no sends {"say_no_text": null}, not an empty string', () async {
      final body = capturePut(fixture);

      await repository.updatePlan(day, sayNoText: const PlanField.clear());

      final sent = body();
      expect(sent, {'say_no_text': null});
      expect(sent['say_no_text'], isNot(''));
    });

    test('mixed: set main + clear side, unset say-no is absent', () async {
      final body = capturePut(fixture);

      await repository.updatePlan(
        day,
        mainFocusTaskId: const PlanField.set(5),
        sideFocusTaskId: const PlanField.clear(),
      );

      final sent = body();
      expect(sent, {'main_focus_task_id': 5, 'side_focus_task_id': null});
      expect(sent.containsKey('say_no_text'), isFalse);
    });

    test('multiple clears: all three keys present with null', () async {
      final body = capturePut(fixture);

      await repository.updatePlan(
        day,
        mainFocusTaskId: const PlanField.clear(),
        sideFocusTaskId: const PlanField.clear(),
        sayNoText: const PlanField.clear(),
      );

      expect(body(), {'main_focus_task_id': null, 'side_focus_task_id': null, 'say_no_text': null});
    });

    test('set say-no + clear main sends both, side absent', () async {
      final body = capturePut(fixture);

      await repository.updatePlan(
        day,
        mainFocusTaskId: const PlanField.clear(),
        sayNoText: const PlanField.set('Toplantılar'),
      );

      expect(body(), {'main_focus_task_id': null, 'say_no_text': 'Toplantılar'});
    });

    test('buildUpdateBody with everything unset is empty', () {
      expect(DailyPlanRepository.buildUpdateBody(), isEmpty);
    });
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
