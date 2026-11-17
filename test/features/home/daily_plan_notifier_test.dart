import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/planning/domain/task.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

final _planDay = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _planDay;
}

/// Plan built from real backend JSON (main focus = id 3, no side focus).
DailyPlan _fixturePlan() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  return DailyPlan(
    planDate: _planDay,
    mainFocus: Task.fromJson(json['main_focus'] as Map<String, dynamic>),
    sideFocus: null,
    sayNoText: json['say_no_text'] as String?,
    tasks: (json['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList(),
  );
}

void main() {
  late _MockDailyPlanRepository repo;
  late DailyPlan plan;

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(const PlanField<int>.unset());
    registerFallbackValue(const PlanField<String>.unset());
  });

  setUp(() {
    repo = _MockDailyPlanRepository();
    plan = _fixturePlan();
    when(() => repo.getPlan(any())).thenAnswer((_) async => Right(plan));
  });

  void stubUpdate(Either<Failure, DailyPlan> result) {
    when(() => repo.updatePlan(
          any(),
          mainFocusTaskId: any(named: 'mainFocusTaskId'),
          sideFocusTaskId: any(named: 'sideFocusTaskId'),
          sayNoText: any(named: 'sayNoText'),
        )).thenAnswer((_) async => result);
  }

  void verifyNoUpdate() {
    verifyNever(() => repo.updatePlan(
          any(),
          mainFocusTaskId: any(named: 'mainFocusTaskId'),
          sideFocusTaskId: any(named: 'sideFocusTaskId'),
          sayNoText: any(named: 'sayNoText'),
        ));
  }

  Future<ProviderContainer> loadedContainer() async {
    final container = ProviderContainer(overrides: [
      todayProvider.overrideWith(_FixedToday.new),
      dailyPlanRepositoryProvider.overrideWith((ref) async => repo),
    ]);
    addTearDown(container.dispose);
    container.listen(dailyPlanProvider, (_, _) {});
    await container.read(dailyPlanProvider.future);
    return container;
  }

  group('DailyPlanNotifier.updatePlan', () {
    test('failure returns Left and keeps the old plan (no AsyncLoading, no AsyncError)', () async {
      final container = await loadedContainer();
      const failure = ServerFailure(DailyPlanRepository.planUpdateInvalidMessage, statusCode: 422);
      stubUpdate(const Left(failure));

      final states = <AsyncValue<DailyPlan>>[];
      container.listen(dailyPlanProvider, (_, next) => states.add(next));

      final result = await container.read(dailyPlanProvider.notifier).updatePlan(sideFocusTaskId: const PlanField.set(4));

      expect(result, const Left<Failure, DailyPlan>(failure));
      expect(states, isEmpty, reason: 'state must not change on failure');
      final state = container.read(dailyPlanProvider);
      expect(state.hasError, isFalse);
      expect(state.value, plan);
    });

    test('success returns Right and replaces state with the server plan', () async {
      final container = await loadedContainer();
      final updated = plan.copyWith(sideFocus: plan.tasks[3]);
      stubUpdate(Right(updated));

      final result = await container.read(dailyPlanProvider.notifier).updatePlan(sideFocusTaskId: const PlanField.set(4));

      expect(result, Right<Failure, DailyPlan>(updated));
      expect(container.read(dailyPlanProvider).value!.sideFocus!.id, 4);
      verify(() => repo.updatePlan(_planDay, sideFocusTaskId: const PlanField.set(4))).called(1);
    });

    test('all fields unset: no request, Right with the current plan, state unchanged', () async {
      final container = await loadedContainer();
      final states = <AsyncValue<DailyPlan>>[];
      container.listen(dailyPlanProvider, (_, next) => states.add(next));

      final result = await container.read(dailyPlanProvider.notifier).updatePlan();

      expect(result, Right<Failure, DailyPlan>(plan));
      expect(states, isEmpty);
      verifyNoUpdate();
    });
  });

  group('DailyPlanNotifier clear', () {
    test('clearMainFocus sends only main as clear and applies the server plan', () async {
      final container = await loadedContainer();
      stubUpdate(Right(plan.copyWith(mainFocus: null)));

      final result = await container.read(dailyPlanProvider.notifier).clearMainFocus();

      expect(result.isRight(), isTrue);
      verify(() => repo.updatePlan(
            _planDay,
            mainFocusTaskId: const PlanField.clear(),
            sideFocusTaskId: const PlanField.unset(),
            sayNoText: const PlanField.unset(),
          )).called(1);
      verify(() => repo.getPlan(any())).called(1); // initial load only, no extra GET
      expect(container.read(dailyPlanProvider).value!.mainFocus, isNull);
    });

    test('clearSideFocus sends only side as clear', () async {
      plan = plan.copyWith(sideFocus: plan.tasks[3]);
      final container = await loadedContainer();
      stubUpdate(Right(plan.copyWith(sideFocus: null)));

      await container.read(dailyPlanProvider.notifier).clearSideFocus();

      verify(() => repo.updatePlan(_planDay, sideFocusTaskId: const PlanField.clear())).called(1);
      expect(container.read(dailyPlanProvider).value!.sideFocus, isNull);
    });

    test('clearSayNoText sends only say-no as clear', () async {
      plan = plan.copyWith(sayNoText: 'Toplantılar');
      final container = await loadedContainer();
      stubUpdate(Right(plan.copyWith(sayNoText: null)));

      await container.read(dailyPlanProvider.notifier).clearSayNoText();

      verify(() => repo.updatePlan(_planDay, sayNoText: const PlanField.clear())).called(1);
      expect(container.read(dailyPlanProvider).value!.sayNoText, isNull);
    });

    test('clear failure keeps the old focus and returns Left', () async {
      final container = await loadedContainer();
      stubUpdate(const Left(NetworkFailure('timeout')));

      final result = await container.read(dailyPlanProvider.notifier).clearMainFocus();

      expect(result.isLeft(), isTrue);
      expect(container.read(dailyPlanProvider).value!.mainFocus!.id, 3);
    });
  });

  group('DailyPlanNotifier focus preflight', () {
    test('setSideFocus with the main focus task: no request, Turkish ValidationFailure', () async {
      final container = await loadedContainer();

      final result = await container.read(dailyPlanProvider.notifier).setSideFocus(plan.mainFocus!);

      final failure = result.fold((f) => f, (_) => fail('expected Left'));
      expect(failure, isA<ValidationFailure>());
      expect(failure.userMessage, 'Bu görev zaten ana odak.');
      verifyNoUpdate();
      expect(container.read(dailyPlanProvider).value, plan);
    });

    test('setMainFocus with the side focus task: no request, Turkish ValidationFailure', () async {
      final side = plan.tasks.first;
      plan = plan.copyWith(mainFocus: null, sideFocus: side);
      final container = await loadedContainer();

      final result = await container.read(dailyPlanProvider.notifier).setMainFocus(side);

      final failure = result.fold((f) => f, (_) => fail('expected Left'));
      expect(failure.userMessage, 'Bu görev zaten ikincil odak.');
      verifyNoUpdate();
    });

    test('plan not loaded yet: no request, "Plan henüz yüklenmedi." (no crash)', () async {
      final pending = Completer<Either<Failure, DailyPlan>>();
      when(() => repo.getPlan(any())).thenAnswer((_) => pending.future);
      final container = ProviderContainer(overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => repo),
      ]);
      addTearDown(container.dispose);
      container.listen(dailyPlanProvider, (_, _) {});
      expect(container.read(dailyPlanProvider).value, isNull);

      final notifier = container.read(dailyPlanProvider.notifier);
      final side = await notifier.setSideFocus(plan.tasks.first);
      final main = await notifier.setMainFocus(plan.tasks.first);

      for (final result in [side, main]) {
        final failure = result.fold((f) => f, (_) => fail('expected Left'));
        expect(failure, isA<ValidationFailure>());
        expect(failure.userMessage, 'Plan henüz yüklenmedi.');
      }
      verifyNoUpdate();
    });

    test('a different task passes preflight and is sent', () async {
      final container = await loadedContainer();
      stubUpdate(Right(plan.copyWith(sideFocus: plan.tasks[3])));

      final result = await container.read(dailyPlanProvider.notifier).setSideFocus(plan.tasks[3]);

      expect(result.isRight(), isTrue);
      verify(() => repo.updatePlan(_planDay, sideFocusTaskId: const PlanField.set(4))).called(1);
    });
  });
}
