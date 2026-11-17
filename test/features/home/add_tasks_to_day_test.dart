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
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

final _planDay = DateTime(2026, 11, 1);
final _nextDay = DateTime(2026, 11, 2);

/// Today is driven by the test; starts at [_initialToday].
DateTime _initialToday = _planDay;

class _TestToday extends TodayNotifier {
  @override
  DateTime build() => _initialToday;

  void set(DateTime day) => state = day;
}

Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
        as Map<String, dynamic>;

/// Plan built from real backend JSON (5 tasks planned for 2026-11-01).
DailyPlan _fixturePlan(DateTime day) {
  final json = _fixture();
  return DailyPlan(
    planDate: day,
    mainFocus: Task.fromJson(json['main_focus'] as Map<String, dynamic>),
    sideFocus: null,
    sayNoText: null,
    tasks: (json['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList(),
  );
}

/// A server task (real JSON shape) not yet in the plan, as returned by PATCH.
Task _serverTask(int id, DateTime day) {
  final json = Map<String, dynamic>.from((_fixture()['tasks'] as List).first as Map)
    ..['id'] = id
    ..['title'] = 'Planlamadan görev $id'
    ..['planned_date'] =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}T00:00:00';
  return Task.fromJson(json);
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    _initialToday = _planDay;
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    when(() => planRepo.getPlan(any()))
        .thenAnswer((inv) async => Right(_fixturePlan(inv.positionalArguments.first as DateTime)));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
  });

  Future<ProviderContainer> loadedContainer() async {
    final container = ProviderContainer(overrides: [
      todayProvider.overrideWith(_TestToday.new),
      dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
      taskRepositoryProvider.overrideWith((ref) async => taskRepo),
    ]);
    addTearDown(container.dispose);
    container.listen(dailyPlanProvider, (_, _) {});
    await container.read(dailyPlanProvider.future);
    return container;
  }

  List<int> planTaskIds(ProviderContainer c) =>
      c.read(dailyPlanProvider).value!.tasks.map((t) => t.id).toList();

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('all succeed: server tasks appended in order, day comes from the plan', () async {
    final container = await loadedContainer();
    for (final id in [10, 11]) {
      when(() => taskRepo.planForDay(id, any()))
          .thenAnswer((_) async => Right(_serverTask(id, _planDay)));
    }

    final result = await container.read(dailyPlanProvider.notifier).addTasksToDay([10, 11]);

    final r = result.fold((f) => fail('expected Right, got $f'), (r) => r);
    expect(r.succeeded, [10, 11]);
    expect(r.failed, isEmpty);
    expect(r.firstFailure, isNull);
    expect(planTaskIds(container), [1, 2, 3, 4, 5, 10, 11]);
    expect(container.read(dailyPlanProvider).value!.tasks.last.title, 'Planlamadan görev 11');
    verify(() => taskRepo.planForDay(10, _planDay)).called(1);
    verify(() => taskRepo.planForDay(11, _planDay)).called(1);
  });

  test('plan day is used even when todayProvider differs from the loaded plan', () async {
    _initialToday = DateTime(2026, 11, 5);
    // Plan repo returns a plan for 2026-11-01 regardless of the asked day.
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(_fixturePlan(_planDay)));
    final container = await loadedContainer();
    when(() => taskRepo.planForDay(any(), any()))
        .thenAnswer((_) async => Right(_serverTask(10, _planDay)));

    await container.read(dailyPlanProvider.notifier).addTasksToDay([10]);

    verify(() => taskRepo.planForDay(10, _planDay)).called(1);
    verifyNever(() => taskRepo.planForDay(any(), DateTime(2026, 11, 5)));
  });

  test('requests are sequential: the second starts only after the first finishes', () async {
    final container = await loadedContainer();
    final first = Completer<Either<Failure, Task>>();
    when(() => taskRepo.planForDay(10, any())).thenAnswer((_) => first.future);
    when(() => taskRepo.planForDay(11, any()))
        .thenAnswer((_) async => Right(_serverTask(11, _planDay)));

    final future = container.read(dailyPlanProvider.notifier).addTasksToDay([10, 11, 10]);
    await settle();
    verifyNever(() => taskRepo.planForDay(11, any()));

    first.complete(Right(_serverTask(10, _planDay)));
    final r = (await future).fold((f) => fail('$f'), (r) => r);

    expect(r.succeeded, [10, 11], reason: 'duplicate ids are sent once');
    verify(() => taskRepo.planForDay(10, any())).called(1);
  });

  test('partial failure: only successes are added, failures reported with the first failure',
      () async {
    final container = await loadedContainer();
    const notFound = ServerFailure('Kaynak bulunamadı.', statusCode: 404);
    when(() => taskRepo.planForDay(10, any()))
        .thenAnswer((_) async => Right(_serverTask(10, _planDay)));
    when(() => taskRepo.planForDay(11, any())).thenAnswer((_) async => const Left(notFound));
    when(() => taskRepo.planForDay(12, any())).thenThrow(StateError('boom'));

    final result = await container.read(dailyPlanProvider.notifier).addTasksToDay([10, 11, 12]);

    final r = result.fold((f) => fail('$f'), (r) => r);
    expect(r.succeeded, [10]);
    expect(r.failed, [11, 12]);
    expect(r.firstFailure, notFound);
    expect(planTaskIds(container), [1, 2, 3, 4, 5, 10]);
    expect(container.read(dailyPlanProvider).hasError, isFalse);
  });

  test('all fail: plan unchanged, Planning list NOT invalidated', () async {
    final container = await loadedContainer();
    container.listen(taskListNotifierProvider, (_, _) {});
    await container.read(taskListNotifierProvider.future);
    clearInteractions(taskRepo);
    const failure = NetworkFailure('offline');
    when(() => taskRepo.planForDay(any(), any())).thenAnswer((_) async => const Left(failure));
    final before = container.read(dailyPlanProvider).value;

    final result = await container.read(dailyPlanProvider.notifier).addTasksToDay([10, 11]);
    await settle();

    final r = result.fold((f) => fail('$f'), (r) => r);
    expect(r.succeeded, isEmpty);
    expect(r.failed, [10, 11]);
    expect(r.firstFailure, failure);
    expect(container.read(dailyPlanProvider).value, before);
    verifyNever(() => taskRepo.getTasksByFilter(any()));
  });

  test('plan not loaded: Left, no request', () async {
    final container = ProviderContainer(overrides: [
      todayProvider.overrideWith(_TestToday.new),
      dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
      taskRepositoryProvider.overrideWith((ref) async => taskRepo),
    ]);
    addTearDown(container.dispose);
    final pending = Completer<Either<Failure, DailyPlan>>();
    when(() => planRepo.getPlan(any())).thenAnswer((_) => pending.future);
    container.listen(dailyPlanProvider, (_, _) {});

    final result = await container.read(dailyPlanProvider.notifier).addTasksToDay([10]);

    expect(result.isLeft(), isTrue);
    result.fold((f) => expect(f.userMessage, DailyPlanNotifier.planNotLoadedMessage), (_) {});
    verifyNever(() => taskRepo.planForDay(any(), any()));
  });

  test('plan reloaded (same day) while a request is in flight: no crash, task ends up in plan',
      () async {
    final container = await loadedContainer();
    final pending = Completer<Either<Failure, Task>>();
    when(() => taskRepo.planForDay(10, any())).thenAnswer((_) => pending.future);

    final future = container.read(dailyPlanProvider.notifier).addTasksToDay([10]);
    await settle();
    container.invalidate(dailyPlanProvider);
    await container.read(dailyPlanProvider.future);

    pending.complete(Right(_serverTask(10, _planDay)));
    final r = (await future).fold((f) => fail('$f'), (r) => r);

    expect(r.succeeded, [10]);
    expect(container.read(dailyPlanProvider).hasError, isFalse);
    expect(planTaskIds(container), contains(10));
  });

  test('day changes while a request is in flight: success counted, NOT added to the new day',
      () async {
    final container = await loadedContainer();
    final pending = Completer<Either<Failure, Task>>();
    when(() => taskRepo.planForDay(10, any())).thenAnswer((_) => pending.future);
    when(() => planRepo.getPlan(_nextDay))
        .thenAnswer((_) async => Right(DailyPlan(planDate: _nextDay, tasks: const [])));

    final future = container.read(dailyPlanProvider.notifier).addTasksToDay([10]);
    await settle();
    (container.read(todayProvider.notifier) as _TestToday).set(_nextDay);
    final newPlan = await container.read(dailyPlanProvider.future);
    expect(newPlan.planDate, _nextDay);

    pending.complete(Right(_serverTask(10, _planDay)));
    final r = (await future).fold((f) => fail('$f'), (r) => r);

    expect(r.succeeded, [10], reason: 'the server did plan it for the old day');
    expect(r.failed, isEmpty);
    final state = container.read(dailyPlanProvider);
    expect(state.hasError, isFalse);
    expect(state.value!.planDate, _nextDay);
    expect(state.value!.tasks, isEmpty, reason: 'old-day result must not leak into the new day');
    verify(() => taskRepo.planForDay(10, _planDay)).called(1);
  });

  test('Planning list is invalidated exactly once per batch and there is no reload loop',
      () async {
    final container = await loadedContainer();
    container.listen(taskListNotifierProvider, (_, _) {});
    await container.read(taskListNotifierProvider.future);
    clearInteractions(taskRepo);
    clearInteractions(planRepo);
    for (final id in [10, 11, 12]) {
      when(() => taskRepo.planForDay(id, any())).thenAnswer((_) async {
        await Future<void>.delayed(Duration.zero);
        return Right(_serverTask(id, _planDay));
      });
    }

    await container.read(dailyPlanProvider.notifier).addTasksToDay([10, 11, 12]);
    await settle();
    await container.read(taskListNotifierProvider.future);
    await settle();

    verify(() => taskRepo.getTasksByFilter(any())).called(1);
    verifyNever(() => planRepo.getPlan(any()));
    expect(planTaskIds(container), [1, 2, 3, 4, 5, 10, 11, 12],
        reason: 'Home plan must not be reloaded by the Planning invalidation');
  });
}
