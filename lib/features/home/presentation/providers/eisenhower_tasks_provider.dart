import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';

/// All tasks for the Eisenhower card and quadrant page, NOT narrowed by the
/// Planning filter.
///
/// Derived from [taskListNotifierProvider], so every list change there
/// (edit, toggle, delete, invalidate from Home or at session end) recomputes
/// it; it needs no entry of its own in `invalidateUserData`.
/// - Planning filter "Tümü": that same list, no request.
/// - Any other filter (the list is narrowed): one unfiltered `getTasks()`.
/// - Planning list still loading: this stays loading; Planning list failed:
///   this fails with the same error. Never an invented empty list.
///
/// Only the list (and whether it has loaded or failed) is watched, not the
/// filter: `changeFilter` first sets the filter, then the fetched list; the
/// filter step alone would only repeat the same request. The filter is read
/// when the list arrives.
///
/// On a recompute the previous value is kept (the card shows it, no
/// skeleton); a result from an older computation is ignored by Riverpod.
final eisenhowerTasksProvider = FutureProvider.autoDispose<List<Task>>((ref) async {
  ref.watch(
    taskListNotifierProvider.select(
      (s) => (
        pending: !s.hasValue && !s.hasError,
        failed: !s.hasValue && s.hasError,
        tasks: s.valueOrNull?.tasks,
      ),
    ),
  );
  // No list value yet: wait for the first load (or rethrow its error).
  final TaskListState state =
      ref.read(taskListNotifierProvider).valueOrNull ??
      await ref.read(taskListNotifierProvider.future);
  final tasks = state.tasks.valueOrNull;
  if (state.currentFilter == TaskFilter.all && tasks != null) return tasks;

  final repository = await ref.read(taskRepositoryProvider.future);
  final result = await repository.getTasks();
  return result.fold((failure) => throw failure, (tasks) => tasks);
});
