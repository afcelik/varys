import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';

/// Notifier for daily plan state
class DailyPlanNotifier extends AutoDisposeAsyncNotifier<DailyPlan> {
  @override
  Future<DailyPlan> build() async {
    final today = ref.watch(todayProvider);
    final repository = await ref.watch(dailyPlanRepositoryProvider.future);
    final result = await repository.getPlan(today);
    return result.fold(
      (failure) => throw Exception(failure.message),
      (plan) => plan,
    );
  }

  /// Updates the daily plan with the given fields.
  /// Only non-null parameters are sent to the API.
  /// To clear a field, explicitly pass null.
  Future<void> updatePlan({
    int? mainFocusTaskId,
    int? sideFocusTaskId,
    String? sayNoText,
  }) async {
    final today = ref.read(todayProvider);
    final repository = await ref.read(dailyPlanRepositoryProvider.future);

    // Set loading state
    state = const AsyncLoading();

    final result = await repository.updatePlan(
      today,
      mainFocusTaskId: mainFocusTaskId,
      sideFocusTaskId: sideFocusTaskId,
      sayNoText: sayNoText,
    );

    result.fold(
      (failure) {
        // On error, restore previous state and show error
        state = AsyncError(Exception(failure.message), StackTrace.current);
      },
      (plan) {
        // Update state with the returned plan from server
        state = AsyncData(plan);
      },
    );
  }

  /// Clears the main focus
  Future<void> clearMainFocus() async {
    await updatePlan(mainFocusTaskId: null);
  }

  /// Clears the side focus
  Future<void> clearSideFocus() async {
    await updatePlan(sideFocusTaskId: null);
  }

  /// Clears the say no text
  Future<void> clearSayNoText() async {
    await updatePlan(sayNoText: null);
  }
}

/// Provider for daily plan, keyed by date (auto-disposes when not watched)
final dailyPlanProvider = AutoDisposeAsyncNotifierProvider<DailyPlanNotifier, DailyPlan>(() {
  return DailyPlanNotifier();
});