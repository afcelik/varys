import 'dart:async';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/projects/presentation/active_projects_notifier.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';

/// State for the TaskList page
class TaskListState {
  final AsyncValue<List<Task>> tasks;
  final TaskFilter currentFilter;

  const TaskListState({
    this.tasks = const AsyncValue.data([]),
    this.currentFilter = TaskFilter.all,
  });

  TaskListState copyWith({
    AsyncValue<List<Task>>? tasks,
    TaskFilter? currentFilter,
  }) {
    return TaskListState(
      tasks: tasks ?? this.tasks,
      currentFilter: currentFilter ?? this.currentFilter,
    );
  }
}

/// Notifier for managing task list state.
///
/// Only [build] may put the provider into an error state (initial load).
/// Mutations never replace the list with a full-page error: they return
/// `Either<Failure, void>` so the page can show a snackbar, and roll back
/// only the affected task on failure.
class TaskListNotifier extends AutoDisposeAsyncNotifier<TaskListState> {
  static const _unexpected = UnknownFailure('Beklenmeyen bir hata oluştu');

  /// Bumped on every build and on dispose; async work captured with an older
  /// value must not write state.
  int _generation = 0;

  /// Numbers list fetches (refresh, filter change, silent refresh); a silent
  /// refresh applies its result only if no newer fetch has started.
  int _refreshSeq = 0;

  @override
  Future<TaskListState> build() async {
    ++_generation;
    ref.onDispose(() => _generation++);
    final repository = await ref.watch(taskRepositoryProvider.future);
    final result = await repository.getTasksByFilter(TaskFilter.all);
    final tasks = result.fold((failure) => throw failure, (tasks) => tasks);
    return TaskListState(tasks: AsyncValue.data(tasks), currentFilter: TaskFilter.all);
  }

  /// Change the current filter and reload tasks.
  /// On failure the previous filter and list are kept.
  Future<Either<Failure, void>> changeFilter(TaskFilter filter) async {
    final previous = state.value;
    if (previous == null) return const Left(_unexpected);
    state = AsyncValue.data(previous.copyWith(currentFilter: filter));

    ++_refreshSeq;
    final result = await _fetch(filter);
    return result.fold(
      (failure) {
        final latest = state.value;
        if (latest != null) {
          state = AsyncValue.data(latest.copyWith(currentFilter: previous.currentFilter));
        }
        return Left(failure);
      },
      (tasks) {
        _setTasks(tasks);
        return const Right(null);
      },
    );
  }

  /// Create a task. On success the server task is put at the top of the
  /// list at once (if it matches the current filter; the backend lists newest
  /// first), then the list is re-fetched silently (no loading state; only the
  /// newest fetch may write; a failed fetch keeps the list). Home's daily
  /// plan is invalidated; for a task linked to a project the project
  /// providers (progress, counts) are invalidated once each. On failure the
  /// list is left untouched and the failure is returned.
  ///
  /// The provider is kept alive while the request (and the silent refresh)
  /// runs, so a closed form or an unwatched Planning tab cannot dispose it
  /// mid-request.
  Future<Either<Failure, void>> addTask(Task task) async {
    final link = ref.keepAlive();
    var linkHandedOff = false;
    try {
      final generation = _generation;
      final repository = await ref.read(taskRepositoryProvider.future);
      final result = await repository.createTask(task);
      return result.fold(
        (failure) => Left(failure),
        (created) {
          if (generation == _generation) {
            _putCreated(created);
            linkHandedOff = true;
            unawaited(_silentRefresh(generation).whenComplete(link.close));
          }
          _syncHome();
          if (created.projectId != null) _syncProjects();
          return const Right(null);
        },
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('TaskListNotifier.addTask error: $e\n$stackTrace');
      return const Left(_unexpected);
    } finally {
      if (!linkHandedOff) link.close();
    }
  }

  /// Toggle task completion (optimistic). Rolls back only this task on failure.
  Future<Either<Failure, void>> toggleTaskCompletion(int taskId) async {
    final original = _findTask(taskId);
    if (original == null) return const Left(_unexpected);

    final newStatus = original.isCompleted ? TaskStatus.todo : TaskStatus.done;
    _replaceTask(original.copyWith(status: newStatus, updatedAt: DateTime.now()));

    try {
      final repository = await ref.read(taskRepositoryProvider.future);
      final result = await repository.updateTaskStatus(taskId, newStatus);
      return result.fold(
        (failure) {
          _replaceTask(original);
          return Left(failure);
        },
        (serverTask) {
          _replaceTask(serverTask);
          _syncHome();
          return const Right(null);
        },
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('TaskListNotifier.toggleTaskCompletion error: $e\n$stackTrace');
      _replaceTask(original);
      return const Left(_unexpected);
    }
  }

  /// Delete a task (optimistic). Re-inserts the task at its old position on failure.
  Future<Either<Failure, void>> deleteTask(int taskId) async {
    final current = state.value;
    final tasks = current?.tasks.value ?? const <Task>[];
    final index = tasks.indexWhere((t) => t.id == taskId);
    if (current == null || index == -1) return const Left(_unexpected);
    final original = tasks[index];

    _setTasks([...tasks]..removeAt(index));

    Either<Failure, void> restore(Failure failure) {
      final latest = state.value?.tasks.value ?? const <Task>[];
      if (!latest.any((t) => t.id == taskId)) {
        final position = index.clamp(0, latest.length);
        _setTasks([...latest]..insert(position, original));
      }
      return Left(failure);
    }

    try {
      final repository = await ref.read(taskRepositoryProvider.future);
      final result = await repository.deleteTask(taskId);
      return result.fold(
        restore,
        (_) {
          _syncHome();
          return const Right(null);
        },
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('TaskListNotifier.deleteTask error: $e\n$stackTrace');
      return restore(_unexpected);
    }
  }

  /// Refresh tasks with the current filter. On failure the current list is kept.
  Future<Either<Failure, void>> refreshTasks() async {
    final filter = state.value?.currentFilter ?? TaskFilter.all;
    ++_refreshSeq;
    final result = await _fetch(filter);
    return result.fold(
      (failure) => Left(failure),
      (tasks) {
        _setTasks(tasks);
        return const Right(null);
      },
    );
  }

  /// Re-fetches the current filter's list without a loading state. Errors
  /// are ignored (the current list stays). Applies only if it is still the
  /// newest fetch, the same build, and the filter has not changed. If the
  /// first load is still running it is restarted so it cannot return a list
  /// from before the create.
  Future<void> _silentRefresh(int generation) async {
    final current = state.value;
    if (current == null) {
      if (state.isLoading) ref.invalidateSelf();
      return;
    }
    final seq = ++_refreshSeq;
    final filter = current.currentFilter;
    final result = await _fetch(filter);
    if (seq != _refreshSeq || generation != _generation) return;
    if (state.value?.currentFilter != filter) return;
    result.fold((_) {}, _setTasks);
  }

  /// Puts [created] at the top (replacing a copy with the same id) when it
  /// belongs to the current filter.
  void _putCreated(Task created) {
    final current = state.value;
    final tasks = current?.tasks.value;
    if (current == null || tasks == null) return;
    if (!_matchesFilter(current.currentFilter, created)) return;
    _setTasks([created, ...tasks.where((t) => t.id != created.id)]);
  }

  static bool _matchesFilter(TaskFilter filter, Task task) => switch (filter) {
        TaskFilter.all => true,
        TaskFilter.inProgress => task.status == TaskStatus.todo || task.status == TaskStatus.inProgress,
        TaskFilter.completed => task.status == TaskStatus.done,
      };

  Future<Either<Failure, List<Task>>> _fetch(TaskFilter filter) async {
    try {
      final repository = await ref.read(taskRepositoryProvider.future);
      return await repository.getTasksByFilter(filter);
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('TaskListNotifier._fetch error: $e\n$stackTrace');
      return const Left(_unexpected);
    }
  }

  Task? _findTask(int taskId) {
    final tasks = state.value?.tasks.value ?? const <Task>[];
    for (final task in tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  /// Replace a task by id in the LATEST state (never a pre-await snapshot).
  void _replaceTask(Task task) {
    final tasks = state.value?.tasks.value;
    if (tasks == null || !tasks.any((t) => t.id == task.id)) return;
    _setTasks(tasks.map((t) => t.id == task.id ? task : t).toList());
  }

  void _setTasks(List<Task> tasks) {
    final current = state.value;
    if (current == null) return;
    state = AsyncValue.data(current.copyWith(tasks: AsyncValue.data(tasks)));
  }

  /// Home's daily plan (focus cards, daily tasks) must reflect task changes.
  void _syncHome() => ref.invalidate(dailyPlanProvider);

  /// A task linked to a project changes that project's progress and counts:
  /// the projects page list and the Home "Aktif Projeler" card. Neither
  /// invalidates this provider, so there is no loop.
  void _syncProjects() {
    ref.invalidate(projectsListProvider);
    ref.invalidate(activeProjectsProvider);
  }
}

/// Riverpod provider for TaskListNotifier
final taskListNotifierProvider =
    AutoDisposeAsyncNotifierProvider<TaskListNotifier, TaskListState>(
  TaskListNotifier.new,
);
