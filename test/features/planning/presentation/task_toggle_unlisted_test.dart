// Toggling a task that is missing from the filter-narrowed Planning list
// (pages showing the unfiltered list pass it as `fallback`): the status is
// sent from the given task, nothing optimistic, the result is never added to
// a list it is not in, then a silent refresh, Home sync and (with a project)
// project sync once. Also pins the unchanged in-list behaviour.

import 'dart:async';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/presentation/active_projects_notifier.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';

import '../../projects/fake_project_repository.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

Task _task(int id, {int? projectId, TaskStatus status = TaskStatus.todo}) => Task(
  id: id,
  title: 'Görev $id',
  status: status,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  projectId: projectId,
);

bool _matches(TaskFilter filter, Task t) => switch (filter) {
  TaskFilter.all => true,
  TaskFilter.inProgress => t.status != TaskStatus.done,
  TaskFilter.completed => t.status == TaskStatus.done,
};

void main() {
  late _MockTaskRepository taskRepo;
  late _MockDailyPlanRepository planRepo;
  late FakeProjectRepository projectRepo;
  late ProviderContainer container;

  /// Server state: 1 todo (project 1), 2 todo, 3 done (project 1), 4 done.
  late List<Task> server;
  late List<TaskFilter> listCalls;
  late List<(int, TaskStatus)> statusCalls;

  /// Each list fetch takes the next gate (if any) and waits for it.
  late List<Completer<void>> listGates;

  /// Status changes wait for this gate when set.
  Completer<void>? statusGate;
  Failure? statusFailure;

  setUpAll(() {
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(TaskStatus.todo);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() async {
    server = [
      _task(1, projectId: 1),
      _task(2),
      _task(3, projectId: 1, status: TaskStatus.done),
      _task(4, status: TaskStatus.done),
    ];
    listCalls = [];
    statusCalls = [];
    listGates = [];
    statusGate = null;
    statusFailure = null;
    taskRepo = _MockTaskRepository();
    planRepo = _MockDailyPlanRepository();
    projectRepo = FakeProjectRepository();
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((inv) async {
      final filter = inv.positionalArguments[0] as TaskFilter;
      listCalls.add(filter);
      final gate = listGates.isEmpty ? null : listGates.removeAt(0);
      await gate?.future;
      return Right([
        for (final t in server)
          if (_matches(filter, t)) t,
      ]);
    });
    when(() => taskRepo.updateTaskStatus(any(), any())).thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as int;
      final status = inv.positionalArguments[1] as TaskStatus;
      statusCalls.add((id, status));
      await statusGate?.future;
      final failure = statusFailure;
      if (failure != null) return Left(failure);
      final updated = server.firstWhere((t) => t.id == id).copyWith(status: status);
      server = [for (final t in server) t.id == id ? updated : t];
      return Right(updated);
    });
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
    container = ProviderContainer(
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ],
    );
    container.listen(taskListNotifierProvider, (_, _) {});
    container.listen(projectsListProvider, (_, _) {});
    container.listen(activeProjectsProvider, (_, _) {});
    await container.read(taskListNotifierProvider.future);
    await container.read(projectsListProvider.future);
    await container.read(activeProjectsProvider.future);
    expect(projectRepo.listCalls, 1);
    expect(projectRepo.activeCalls, 1);
    listCalls.clear();
  });

  tearDown(() => container.dispose());

  TaskListNotifier tasks() => container.read(taskListNotifierProvider.notifier);
  TaskListState state() => container.read(taskListNotifierProvider).requireValue;
  List<int> shownIds() => [for (final t in state().tasks.requireValue) t.id];
  Task serverTask(int id) => server.firstWhere((t) => t.id == id);

  Future<void> settle() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await container.read(projectsListProvider.future);
    await container.read(activeProjectsProvider.future);
  }

  Future<void> narrow(TaskFilter filter) async {
    expect(await tasks().changeFilter(filter), const Right<Failure, void>(null));
    listCalls.clear();
  }

  group('task not in the list, passed as fallback', () {
    test('filter "Devam Ediyor": done task with a project reopened; status sent from the given '
        'task, Right, silent refresh, projects reloaded once each', () async {
      await narrow(TaskFilter.inProgress);
      expect(shownIds(), [1, 2]);

      final result = await tasks().toggleTaskCompletion(3, fallback: serverTask(3));
      expect(result, const Right<Failure, void>(null));
      await settle();

      expect(statusCalls, [(3, TaskStatus.todo)]);
      expect(listCalls, [TaskFilter.inProgress], reason: 'one silent refresh, same filter');
      expect(shownIds(), [1, 2, 3], reason: 'the list is what the refresh returned');
      expect(state().currentFilter, TaskFilter.inProgress);
      expect(projectRepo.listCalls, 2);
      expect(projectRepo.activeCalls, 2);
    });

    test('filter "Devam Ediyor": result matching the filter is NOT added before the refresh; '
        'no project, so projects are not reloaded', () async {
      await narrow(TaskFilter.inProgress);
      final refreshGate = Completer<void>();
      listGates.add(refreshGate);

      final result = await tasks().toggleTaskCompletion(4, fallback: serverTask(4));
      expect(result, const Right<Failure, void>(null));
      expect(statusCalls, [(4, TaskStatus.todo)]);
      expect(shownIds(), [1, 2], reason: 'never added; the refresh decides');
      await Future<void>.delayed(Duration.zero);
      expect(listCalls, [TaskFilter.inProgress], reason: 'silent refresh started');

      refreshGate.complete();
      await settle();
      expect(shownIds(), [1, 2, 4]);
      expect(projectRepo.listCalls, 1);
      expect(projectRepo.activeCalls, 1);
    });

    test('filter "Tamamlandı": todo task completed; NOT added before the refresh; projects '
        'reloaded once each', () async {
      await narrow(TaskFilter.completed);
      expect(shownIds(), [3, 4]);
      final refreshGate = Completer<void>();
      listGates.add(refreshGate);

      final result = await tasks().toggleTaskCompletion(1, fallback: serverTask(1));
      expect(result, const Right<Failure, void>(null));
      expect(statusCalls, [(1, TaskStatus.done)]);
      expect(shownIds(), [3, 4], reason: 'never added; the refresh decides');

      refreshGate.complete();
      await settle();
      expect(listCalls, [TaskFilter.completed]);
      expect(shownIds(), [1, 3, 4]);
      expect(state().currentFilter, TaskFilter.completed);
      expect(projectRepo.listCalls, 2);
      expect(projectRepo.activeCalls, 2);
    });

    test('failure: Left with the server failure (userMessage text), list and projects '
        'untouched, no refresh', () async {
      await narrow(TaskFilter.inProgress);
      final before = state().tasks.requireValue;
      statusFailure = _serverError;

      final result = await tasks().toggleTaskCompletion(3, fallback: serverTask(3));
      await settle();

      expect(result, const Left<Failure, void>(_serverError));
      expect(
        userMessage(result.fold((f) => f, (_) => fail('expected Left'))),
        _serverError.message,
      );
      expect(identical(state().tasks.requireValue, before), isTrue, reason: 'list not rewritten');
      expect(listCalls, isEmpty);
      expect(projectRepo.listCalls, 1);
      expect(projectRepo.activeCalls, 1);
    });

    test('double tap while the request runs: one request, both callers get Right', () async {
      await narrow(TaskFilter.inProgress);
      final gate = Completer<void>();
      statusGate = gate;

      final first = tasks().toggleTaskCompletion(3, fallback: serverTask(3));
      final second = tasks().toggleTaskCompletion(3, fallback: serverTask(3));
      await Future<void>.delayed(Duration.zero);
      expect(statusCalls, [(3, TaskStatus.todo)]);

      gate.complete();
      expect(await first, const Right<Failure, void>(null));
      expect(await second, const Right<Failure, void>(null));
      await settle();
      expect(statusCalls, [(3, TaskStatus.todo)], reason: 'still one request');
      expect(serverTask(3).status, TaskStatus.todo);
      expect(projectRepo.listCalls, 2, reason: 'projects reloaded once');
    });

    test('without a fallback the old result stays: Left(UnknownFailure), no request', () async {
      await narrow(TaskFilter.inProgress);
      final result = await tasks().toggleTaskCompletion(3);
      expect(result.fold((f) => f, (_) => null), isA<UnknownFailure>());
      expect(statusCalls, isEmpty);
      expect(shownIds(), [1, 2]);
    });

    test('filter changed while the request runs: the old result does not rewrite the new '
        'list; the new filter stays', () async {
      await narrow(TaskFilter.inProgress);
      final gate = Completer<void>();
      statusGate = gate;

      final toggle = tasks().toggleTaskCompletion(3, fallback: serverTask(3));
      await Future<void>.delayed(Duration.zero);
      await narrow(TaskFilter.completed);
      expect(shownIds(), [3, 4], reason: '3 is still done on the server');

      gate.complete();
      expect(await toggle, const Right<Failure, void>(null));
      expect(shownIds(), [4], reason: '3 now todo: removed from "Tamamlandı", nothing added');
      await settle();
      expect(state().currentFilter, TaskFilter.completed);
      expect(listCalls, [TaskFilter.completed], reason: 'the refresh uses the new filter');
      expect(shownIds(), [4]);
    });

    test('filter changed while the silent refresh runs: the stale refresh (old filter) '
        'answering last is ignored', () async {
      await narrow(TaskFilter.inProgress);
      final staleRefresh = Completer<void>();
      final filterFetch = Completer<void>();
      listGates.addAll([staleRefresh, filterFetch]);

      expect(
        await tasks().toggleTaskCompletion(4, fallback: serverTask(4)),
        const Right<Failure, void>(null),
      );
      final change = tasks().changeFilter(TaskFilter.completed);
      await Future<void>.delayed(Duration.zero);
      expect(listCalls, [TaskFilter.inProgress, TaskFilter.completed]);

      filterFetch.complete();
      expect(await change, const Right<Failure, void>(null));
      expect(shownIds(), [3]);

      staleRefresh.complete();
      await settle();
      expect(state().currentFilter, TaskFilter.completed);
      expect(shownIds(), [3], reason: 'the "Devam Ediyor" list [1, 2, 4] must not land');
    });
  });

  group('task in the list (unchanged behaviour)', () {
    test(
      'fallback given but the list copy wins: optimistic from the list, status from it',
      () async {
        final gate = Completer<void>();
        statusGate = gate;
        final staleCopy = serverTask(1).copyWith(status: TaskStatus.done);

        final toggle = tasks().toggleTaskCompletion(1, fallback: staleCopy);
        await Future<void>.delayed(Duration.zero);
        expect(statusCalls, [(1, TaskStatus.done)], reason: 'from the list (todo), not the copy');
        expect(
          state().tasks.requireValue.firstWhere((t) => t.id == 1).status,
          TaskStatus.done,
          reason: 'optimistic',
        );

        gate.complete();
        expect(await toggle, const Right<Failure, void>(null));
        await settle();
        expect(listCalls, isEmpty, reason: 'in-list path has no silent refresh');
        expect(projectRepo.listCalls, 2);
      },
    );

    test('pinned: two concurrent toggles send two requests (done, then todo); the last answer '
        'stays', () async {
      final gate = Completer<void>();
      statusGate = gate;

      final first = tasks().toggleTaskCompletion(1);
      final second = tasks().toggleTaskCompletion(1);
      await Future<void>.delayed(Duration.zero);
      expect(statusCalls, [(1, TaskStatus.done), (1, TaskStatus.todo)]);
      expect(
        state().tasks.requireValue.firstWhere((t) => t.id == 1).status,
        TaskStatus.todo,
        reason: 'second optimistic step flipped it back',
      );

      gate.complete();
      expect(await first, const Right<Failure, void>(null));
      expect(await second, const Right<Failure, void>(null));
      await settle();
      expect(serverTask(1).status, TaskStatus.todo);
      expect(state().tasks.requireValue.firstWhere((t) => t.id == 1).status, TaskStatus.todo);
      expect(projectRepo.listCalls, 2, reason: 'invalidated twice, reloaded once');
    });
  });
}
