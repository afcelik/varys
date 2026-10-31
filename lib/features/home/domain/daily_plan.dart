import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:varys/features/planning/domain/task.dart';

part 'daily_plan.freezed.dart';
part 'daily_plan.g.dart';

/// DailyPlan entity representing a day's plan with focus tasks.
@freezed
abstract class DailyPlan with _$DailyPlan {
  const factory DailyPlan({
    required DateTime planDate,
    Task? mainFocus,
    Task? sideFocus,
    String? sayNoText,
    required List<Task> tasks,
  }) = _DailyPlan;

  factory DailyPlan.fromJson(Map<String, dynamic> json) => _$DailyPlanFromJson(json);
}

/// Request model for updating a daily plan.
/// All fields are optional - only explicitly set fields will be sent to the API.
/// To clear a field, explicitly set it to null.
@freezed
abstract class DailyPlanUpdate with _$DailyPlanUpdate {
  const factory DailyPlanUpdate({
    int? mainFocusTaskId,
    int? sideFocusTaskId,
    String? sayNoText,
  }) = _DailyPlanUpdate;

  factory DailyPlanUpdate.fromJson(Map<String, dynamic> json) => _$DailyPlanUpdateFromJson(json);
}