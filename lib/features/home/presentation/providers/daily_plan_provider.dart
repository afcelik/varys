import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';

/// Notifier for daily plan state
class DailyPlanNotifier extends AutoDisposeAsyncNotifier<DailyPlan> {
  // Decreasing counter for temp id (-1, -2, -3)
  static int _tempIdCounter = 0;

  @override
  Future<DailyPlan> build() async {
    final today = ref.watch(todayProvider);
    final repository = await ref.watch(dailyPlanRepositoryProvider.future);
    final result = await repository.getPlan(today);
    return result.fold(
      (failure) => throw failure,
      (plan) => plan,
    );
  }

  static const String planNotLoadedMessage = 'Plan henüz yüklenmedi.';
  static const String alreadyMainFocusMessage = 'Bu görev zaten ana odak.';
  static const String alreadySideFocusMessage = 'Bu görev zaten ikincil odak.';

  /// Updates the daily plan with the given fields.
  /// Only non-null parameters are sent to the API.
  ///
  /// Never puts the provider into AsyncLoading/AsyncError: on failure the
  /// current plan stays on screen and the caller shows a snackbar.
  Future<Either<Failure, DailyPlan>> updatePlan({
    int? mainFocusTaskId,
    int? sideFocusTaskId,
    String? sayNoText,
  }) async {
    final today = ref.read(todayProvider);
    final repository = await ref.read(dailyPlanRepositoryProvider.future);

    final result = await repository.updatePlan(
      today,
      mainFocusTaskId: mainFocusTaskId,
      sideFocusTaskId: sideFocusTaskId,
      sayNoText: sayNoText,
    );

    return result.fold(
      (failure) {
        if (kDebugMode) {
          debugPrint('DailyPlanNotifier.updatePlan error: ${failure.runtimeType} - $failure');
        }
        return Left(failure);
      },
      (plan) {
        state = AsyncData(plan);
        return Right(plan);
      },
    );
  }

  /// Sets the main focus. Rejected client-side (no request) when the plan
  /// is not loaded or the task is already the side focus.
  Future<Either<Failure, DailyPlan>> setMainFocus(Task task) async {
    final plan = state.value;
    if (plan == null) return const Left(ValidationFailure(planNotLoadedMessage));
    if (plan.sideFocus?.id == task.id) {
      return const Left(ValidationFailure(alreadySideFocusMessage));
    }
    return updatePlan(mainFocusTaskId: task.id);
  }

  /// Sets the side focus. Rejected client-side (no request) when the plan
  /// is not loaded or the task is already the main focus.
  Future<Either<Failure, DailyPlan>> setSideFocus(Task task) async {
    final plan = state.value;
    if (plan == null) return const Left(ValidationFailure(planNotLoadedMessage));
    if (plan.mainFocus?.id == task.id) {
      return const Left(ValidationFailure(alreadyMainFocusMessage));
    }
    return updatePlan(sideFocusTaskId: task.id);
  }

  // NOTE: clearing is a known issue (see CLAUDE.md "Known issues"):
  // null fields are dropped from the PUT body, so these send `{}`.

  /// Clears the main focus
  Future<Either<Failure, DailyPlan>> clearMainFocus() =>
      updatePlan(mainFocusTaskId: null);

  /// Clears the side focus
  Future<Either<Failure, DailyPlan>> clearSideFocus() =>
      updatePlan(sideFocusTaskId: null);

  /// Clears the say no text
  Future<Either<Failure, DailyPlan>> clearSayNoText() =>
      updatePlan(sayNoText: null);

  /// Add a new task for today's plan (optimistic update with temporary negative ID)
  /// Returns Failure on error, null on success - widget shows snackbar
  Future<Either<Failure, void>> addTask(String title) async {
    final planDate = state.value?.planDate;
    if (planDate == null) return Left(const ServerFailure('Plan date not available'));

    final repository = await ref.read(taskRepositoryProvider.future);

    // Decreasing counter for temp id (-1, -2, -3)
    _tempIdCounter--;
    final tempId = _tempIdCounter;

    // Use plan's date, NOT todayProvider
    final plannedDateStr = plannedDateForApi(planDate);
    final plannedDateTime = DateTime.parse(plannedDateStr); // For Task model

    final now = DateTime.now();
    final tempTask = Task(
      id: tempId,
      title: title,
      description: null,
      status: TaskStatus.todo,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      plannedDate: plannedDateTime,
      dueDate: null,
    );

    // Optimistic update - add to tasks list
    final currentPlan = state.value!;
    state = AsyncData(currentPlan.copyWith(
      tasks: [tempTask, ...currentPlan.tasks],
    ));

    try {
      final result = await repository.createTask(tempTask);
      return result.fold(
        (failure) {
          // Rollback ONLY the failed task
          final latestState = state.value;
          if (latestState == null || latestState.planDate != planDate) {
            // Plan reloaded or day changed - silently leave result
            return Left(failure);
          }
          state = AsyncData(latestState.copyWith(
            tasks: latestState.tasks.where((t) => t.id != tempId).toList(),
          ));
          return Left(failure);
        },
        (serverTask) {
          // Reread state after await
          final latestState = state.value;
          if (latestState == null || latestState.planDate != planDate) {
            // Plan reloaded or day changed - silently leave result
            return const Right(null);
          }
          // Replace temp task with server task (real ID)
          state = AsyncData(latestState.copyWith(
            tasks: latestState.tasks.map((t) =>
              t.id == tempId ? serverTask : t
            ).toList(),
          ));

          // Invalidate planning screen provider (without reloading Home)
          ref.invalidate(taskListNotifierProvider);

          return const Right(null);
        },
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('addTask unexpected error: $e\n$stackTrace');
      // Reread state
      final latestState = state.value;
      if (latestState == null || latestState.planDate != planDate) {
        return Left(const UnknownFailure('Beklenmeyen bir hata oluştu'));
      }
      // Rollback ONLY the failed task
      state = AsyncData(latestState.copyWith(
        tasks: latestState.tasks.where((t) => t.id != tempId).toList(),
      ));
      return Left(const UnknownFailure('Beklenmeyen bir hata oluştu'));
    }
  }

  /// Toggle task status (optimistic update)
  /// Returns Failure on error, null on success - widget shows snackbar
  Future<Either<Failure, void>> toggleTaskStatus(int taskId, TaskStatus currentStatus) async {
    final repository = await ref.read(taskRepositoryProvider.future);
    final planDate = state.value?.planDate;
    if (planDate == null) return Left(const ServerFailure('Plan date not available'));

    final newStatus = currentStatus == TaskStatus.done ? TaskStatus.todo : TaskStatus.done;

    // Find current task for rollback (including focus tasks)
    final currentPlan = state.value!;
    final currentTask = currentPlan.tasks.firstWhere((t) => t.id == taskId);
    final currentMainFocus = currentPlan.mainFocus;
    final currentSideFocus = currentPlan.sideFocus;

    // Optimistic update - update ONLY this task and matching focus
    state = AsyncData(currentPlan.copyWith(
      tasks: currentPlan.tasks.map((t) =>
        t.id == taskId ? t.copyWith(status: newStatus, updatedAt: DateTime.now()) : t
      ).toList(),
      mainFocus: currentMainFocus?.id == taskId
          ? currentMainFocus!.copyWith(status: newStatus, updatedAt: DateTime.now())
          : currentMainFocus,
      sideFocus: currentSideFocus?.id == taskId
          ? currentSideFocus!.copyWith(status: newStatus, updatedAt: DateTime.now())
          : currentSideFocus,
    ));

    try {
      final result = await repository.updateTaskStatus(taskId, newStatus);
      return result.fold(
        (failure) {
          // Reread state after await
          final latestState = state.value;
          if (latestState == null || latestState.planDate != planDate) {
            // Plan reloaded or day changed - silently leave result
            return Left(failure);
          }
          // Rollback ONLY this task (and focus if matched)
          state = AsyncData(latestState.copyWith(
            tasks: latestState.tasks.map((t) =>
              t.id == taskId ? currentTask : t
            ).toList(),
            mainFocus: latestState.mainFocus?.id == taskId ? currentTask : latestState.mainFocus,
            sideFocus: latestState.sideFocus?.id == taskId ? currentTask : latestState.sideFocus,
          ));
          return Left(failure);
        },
        (serverTask) {
          // Reread state after await
          final latestState = state.value;
          if (latestState == null || latestState.planDate != planDate) {
            // Plan reloaded or day changed - silently leave result
            return const Right(null);
          }
          // Update with server response (may have updatedAt changes)
          state = AsyncData(latestState.copyWith(
            tasks: latestState.tasks.map((t) =>
              t.id == taskId ? serverTask : t
            ).toList(),
            mainFocus: latestState.mainFocus?.id == taskId ? serverTask : latestState.mainFocus,
            sideFocus: latestState.sideFocus?.id == taskId ? serverTask : latestState.sideFocus,
          ));

          // Invalidate planning screen provider
          ref.invalidate(taskListNotifierProvider);

          return const Right(null);
        },
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('toggleTaskStatus unexpected error: $e\n$stackTrace');
      // Reread state
      final latestState = state.value;
      if (latestState == null || latestState.planDate != planDate) {
        return Left(const UnknownFailure('Beklenmeyen bir hata oluştu'));
      }
      // Rollback ONLY this task
      state = AsyncData(latestState.copyWith(
        tasks: latestState.tasks.map((t) =>
          t.id == taskId ? currentTask : t
        ).toList(),
        mainFocus: latestState.mainFocus?.id == taskId ? currentTask : latestState.mainFocus,
        sideFocus: latestState.sideFocus?.id == taskId ? currentTask : latestState.sideFocus,
      ));
      return Left(const UnknownFailure('Beklenmeyen bir hata oluştu'));
    }
  }
}

/// Provider for daily plan, keyed by date (auto-disposes when not watched)
final dailyPlanProvider = AutoDisposeAsyncNotifierProvider<DailyPlanNotifier, DailyPlan>(() {
  return DailyPlanNotifier();
});