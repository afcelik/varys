import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';

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

  @override
  Future<TaskListState> build() async {
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

  /// Create a task. The list is refreshed on success; on failure the list
  /// is left untouched and the failure is returned.
  Future<Either<Failure, void>> addTask(Task task) async {
    try {
      final repository = await ref.read(taskRepositoryProvider.future);
      final result = await repository.createTask(task);
      if (result.isLeft()) {
        return Left(result.fold((failure) => failure, (_) => _unexpected));
      }
      await refreshTasks(); // A refresh failure keeps the current list
      _syncHome();
      return const Right(null);
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('TaskListNotifier.addTask error: $e\n$stackTrace');
      return const Left(_unexpected);
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
    final result = await _fetch(filter);
    return result.fold(
      (failure) => Left(failure),
      (tasks) {
        _setTasks(tasks);
        return const Right(null);
      },
    );
  }

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
}

/// Riverpod provider for TaskListNotifier
final taskListNotifierProvider =
    AutoDisposeAsyncNotifierProvider<TaskListNotifier, TaskListState>(
  TaskListNotifier.new,
);
