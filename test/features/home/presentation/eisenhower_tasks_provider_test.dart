import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/presentation/providers/eisenhower_tasks_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

/// Real GET /tasks (ids 5 done, 4, 3, 2, 1).
List<Task> _all() =>
    (jsonDecode(File('test/fixtures/tasks_eisenhower.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .map(Task.fromJson)
        .toList();

List<int> _ids(List<Task> tasks) => tasks.map((t) => t.id).toList();

const _failure = ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _MockTaskRepository repo;
  late List<Task> all;

  setUpAll(() {
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(const PlanField<String>.unset());
    registerFallbackValue(const PlanField<int>.unset());
    registerFallbackValue(const PlanField<DateTime>.unset());
  });

  /// What the fake server answers for [filter] (like getTasksByFilter).
  List<Task> filtered(TaskFilter filter) => switch (filter) {
    TaskFilter.all => all,
    TaskFilter.inProgress => all.where((t) => t.status != TaskStatus.done).toList(),
    TaskFilter.completed => all.where((t) => t.status == TaskStatus.done).toList(),
  };

  setUp(() {
    repo = _MockTaskRepository();
    all = _all();
    when(
      () => repo.getTasksByFilter(any()),
    ).thenAnswer((inv) async => Right(filtered(inv.positionalArguments.first as TaskFilter)));
    when(() => repo.getTasks()).thenAnswer((_) async => Right(all));
  });

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [taskRepositoryProvider.overrideWith((ref) async => repo)],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// Listens like the card does and returns every emitted state.
  Future<List<AsyncValue<List<Task>>>> listen(ProviderContainer c) async {
    final states = <AsyncValue<List<Task>>>[];
    c.listen(eisenhowerTasksProvider, (_, next) => states.add(next), fireImmediately: true);
    await _settle();
    return states;
  }

  test('filter "Tümü": the Planning list itself, no extra request', () async {
    final c = makeContainer();
    await listen(c);

    expect(_ids(c.read(eisenhowerTasksProvider).requireValue), [5, 4, 3, 2, 1]);
    verifyNever(() => repo.getTasks());
    verify(() => repo.getTasksByFilter(TaskFilter.all)).called(1);
  });

  for (final filter in [TaskFilter.completed, TaskFilter.inProgress]) {
    test('filter "${filter.label}": same data, getTasks() once, old value kept', () async {
      final c = makeContainer();
      final states = await listen(c);
      states.clear();

      // The filtered fetch is slow (real network): the filter is already set
      // while the old list is still shown.
      final fetch = Completer<void>();
      when(() => repo.getTasksByFilter(filter)).thenAnswer((_) async {
        await fetch.future;
        return Right(filtered(filter));
      });
      final pending = c.read(taskListNotifierProvider.notifier).changeFilter(filter);
      await _settle();
      expect(c.read(taskListNotifierProvider).requireValue.currentFilter, filter);
      expect(_ids(c.read(eisenhowerTasksProvider).requireValue), [5, 4, 3, 2, 1]);
      verifyNever(() => repo.getTasks());
      fetch.complete();
      final changed = await pending;
      await _settle();

      expect(changed.isRight(), isTrue);
      expect(
        _ids(c.read(taskListNotifierProvider).requireValue.tasks.requireValue),
        isNot([5, 4, 3, 2, 1]),
        reason: 'Planning list is narrowed',
      );
      expect(_ids(c.read(eisenhowerTasksProvider).requireValue), [5, 4, 3, 2, 1]);
      verify(() => repo.getTasks()).called(1);
      expect(states, isNotEmpty);
      expect(states.every((s) => s.hasValue), isTrue, reason: 'never a state without a value');
      expect(states.any((s) => s.hasError), isFalse);

      // Back to "Tümü": the Planning list again, no further unfiltered request.
      await c.read(taskListNotifierProvider.notifier).changeFilter(TaskFilter.all);
      await _settle();
      expect(_ids(c.read(eisenhowerTasksProvider).requireValue), [5, 4, 3, 2, 1]);
      verifyNever(() => repo.getTasks());
    });
  }

  test('a slow older getTasks() answer does not overwrite the newer one', () async {
    final c = makeContainer();
    await listen(c);
    final slow = Completer<Either<Failure, List<Task>>>();
    final fast = Completer<Either<Failure, List<Task>>>();
    final answers = [slow, fast];
    when(() => repo.getTasks()).thenAnswer((_) => answers.removeAt(0).future);

    // 1st recompute (filter "Tamamlandı") waits on [slow].
    await c.read(taskListNotifierProvider.notifier).changeFilter(TaskFilter.completed);
    await _settle();
    // 2nd recompute (filter "Devam Ediyor") waits on [fast].
    await c.read(taskListNotifierProvider.notifier).changeFilter(TaskFilter.inProgress);
    await _settle();
    verify(() => repo.getTasks()).called(2);

    final newer = all.where((t) => t.id != 4).toList();
    fast.complete(Right(newer));
    await _settle();
    expect(_ids(c.read(eisenhowerTasksProvider).requireValue), [5, 3, 2, 1]);

    slow.complete(Right(all));
    await _settle();
    final afterSlow = _ids(c.read(eisenhowerTasksProvider).requireValue);
    expect(afterSlow, [5, 3, 2, 1], reason: 'the older answer is ignored');
  });

  test('Planning list loading: provider is loading (no empty list)', () async {
    final gate = Completer<Either<Failure, List<Task>>>();
    when(() => repo.getTasksByFilter(any())).thenAnswer((_) => gate.future);
    final c = makeContainer();
    final states = await listen(c);

    expect(states, isNotEmpty);
    expect(states.every((s) => s.isLoading && !s.hasValue), isTrue);
    verifyNever(() => repo.getTasks());

    gate.complete(Right(all));
    await _settle();
    expect(_ids(c.read(eisenhowerTasksProvider).requireValue), [5, 4, 3, 2, 1]);
  });

  test('Planning list failed: provider fails with the same error (no empty list)', () async {
    when(() => repo.getTasksByFilter(any())).thenAnswer((_) async => const Left(_failure));
    final c = makeContainer();
    final states = await listen(c);

    final last = c.read(eisenhowerTasksProvider);
    expect(last.hasError, isTrue);
    expect(last.hasValue, isFalse);
    expect(last.error, _failure);
    expect(states.any((s) => s.hasValue), isFalse);
    verifyNever(() => repo.getTasks());
  });

  test('getTasks() failing under a narrowed filter: error, then retry recovers', () async {
    final c = makeContainer();
    await listen(c);
    when(() => repo.getTasks()).thenAnswer((_) async => const Left(_failure));
    await c.read(taskListNotifierProvider.notifier).changeFilter(TaskFilter.completed);
    await _settle();
    expect(c.read(eisenhowerTasksProvider).error, _failure);

    when(() => repo.getTasks()).thenAnswer((_) async => Right(all));
    c.invalidate(eisenhowerTasksProvider);
    await _settle();
    expect(_ids(c.read(eisenhowerTasksProvider).requireValue), [5, 4, 3, 2, 1]);
  });

  test('a task edit in the Planning list recomputes the provider (flag change)', () async {
    final c = makeContainer();
    await listen(c);
    final task4 = all.firstWhere((t) => t.id == 4);
    final updated = task4.copyWith(isUrgent: true);
    when(
      () => repo.updateTask(
        any(),
        title: any(named: 'title'),
        description: any(named: 'description'),
        status: any(named: 'status'),
        plannedDate: any(named: 'plannedDate'),
        dueDate: any(named: 'dueDate'),
        projectId: any(named: 'projectId'),
        isImportant: any(named: 'isImportant'),
        isUrgent: any(named: 'isUrgent'),
      ),
    ).thenAnswer((_) async {
      // Consistent fake server: later GETs return the edited task too.
      all = [for (final t in all) t.id == 4 ? updated : t];
      return Right(updated);
    });

    await c
        .read(taskListNotifierProvider.notifier)
        .updateTask(task4, const TaskChanges(isUrgent: true));
    await _settle();

    final now = c.read(eisenhowerTasksProvider).requireValue;
    expect(now.firstWhere((t) => t.id == 4).isUrgent, isTrue);
  });
}
