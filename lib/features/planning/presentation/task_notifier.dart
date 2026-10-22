import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';

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

/// Notifier for managing task list state
class TaskListNotifier extends AutoDisposeAsyncNotifier<TaskListState> {
  TaskRepository get _repository => ref.read(taskRepositoryProvider);

  @override
  Future<TaskListState> build() async {
    final tasks = await _loadTasks(TaskFilter.all);
    return TaskListState(tasks: tasks, currentFilter: TaskFilter.all);
  }

  /// Load tasks based on filter
  Future<AsyncValue<List<Task>>> _loadTasks(TaskFilter filter) async {
    final result = await _repository.getTasksByFilter(filter);
    return result.fold(
      (failure) => AsyncValue.error(failure, StackTrace.current),
      (tasks) => AsyncValue.data(tasks),
    );
  }

  /// Change the current filter and reload tasks
  Future<void> changeFilter(TaskFilter filter) async {
    state = AsyncValue.data(state.value!.copyWith(currentFilter: filter));
    final tasks = await _loadTasks(filter);
    state = AsyncValue.data(
      state.value!.copyWith(tasks: tasks),
    );
  }

  /// Add a new task
  Future<void> addTask(Task task) async {
    state = AsyncValue.loading();
    try {
      final result = await _repository.createTask(task);
      await result.fold(
        (failure) async {
          state = AsyncValue.error(failure, StackTrace.current);
        },
        (createdTask) async {
          await refreshTasks();
        },
      );
    } catch (e, stack) {
      state = AsyncValue.error(e, stack);
    }
  }

  /// Toggle task completion
  Future<void> toggleTaskCompletion(String taskId) async {
    final currentTasks = state.value?.tasks.value ?? [];
    final taskIndex = currentTasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    final task = currentTasks[taskIndex];
    final updatedTask = task.copyWith(
      isCompleted: !task.isCompleted,
      updatedAt: DateTime.now(),
      completedAt: !task.isCompleted ? DateTime.now() : null,
    );

    // Optimistic update
    state = AsyncValue.data(
      state.value!.copyWith(
        tasks: AsyncValue.data([
          ...currentTasks.sublist(0, taskIndex),
          updatedTask,
          ...currentTasks.sublist(taskIndex + 1),
        ]),
      ),
    );

    try {
      final result = await _repository.toggleCompletion(taskId);
      await result.fold(
        (failure) async {
          // Revert on failure
          await refreshTasks();
        },
        (serverTask) async {
          // Update with server response
          state = AsyncValue.data(
            state.value!.copyWith(
              tasks: AsyncValue.data([
                ...currentTasks.sublist(0, taskIndex),
                serverTask,
                ...currentTasks.sublist(taskIndex + 1),
              ]),
            ),
          );
        },
      );
    } catch (e) {
      await refreshTasks();
    }
  }

  /// Delete a task
  Future<void> deleteTask(String taskId) async {
    final currentTasks = state.value?.tasks.value ?? [];
    final taskIndex = currentTasks.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;

    // Optimistic update - remove immediately
    state = AsyncValue.data(
      state.value!.copyWith(
        tasks: AsyncValue.data([
          ...currentTasks.sublist(0, taskIndex),
          ...currentTasks.sublist(taskIndex + 1),
        ]),
      ),
    );

    try {
      final result = await _repository.deleteTask(taskId);
      await result.fold(
        (failure) async {
          // Revert on failure
          await refreshTasks();
        },
        (_) async {
          // Already removed optimistically
        },
      );
    } catch (e) {
      await refreshTasks();
    }
  }

  /// Refresh tasks with current filter
  Future<void> refreshTasks() async {
    final filter = state.value?.currentFilter ?? TaskFilter.all;
    final tasks = await _loadTasks(filter);
    state = AsyncValue.data(
      state.value!.copyWith(tasks: tasks),
    );
  }
}

/// Riverpod provider for TaskListNotifier
final taskListNotifierProvider =
    AutoDisposeAsyncNotifierProvider<TaskListNotifier, TaskListState>(
  TaskListNotifier.new,
);