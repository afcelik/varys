import 'package:freezed_annotation/freezed_annotation.dart';

part 'routine.freezed.dart';
part 'routine.g.dart';

/// Recurrence type matching backend values.
enum RecurrenceType {
  @JsonValue('daily')
  daily,
  @JsonValue('weekly')
  weekly,
  @JsonValue('monthly')
  monthly,
  @JsonValue('interval')
  interval,
}

/// A routine as returned by `GET /routines` (backend RoutineRead).
///
/// [startDate] is a plain calendar date (`YYYY-MM-DD`); it is parsed as a
/// local date with no time zone conversion.
/// [daysOfWeek] uses Monday=0 ... Sunday=6.
@freezed
abstract class Routine with _$Routine {
  const factory Routine({
    required int id,
    required String title,
    String? description,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Routine;

  factory Routine.fromJson(Map<String, dynamic> json) => _$RoutineFromJson(json);
}

/// A routine scheduled on a given day, as returned by
/// `GET /routines/day/{YYYY-MM-DD}` (backend RoutineDayItem): every
/// RoutineRead field plus completion and streaks, in the same flat shape.
@freezed
abstract class RoutineDayItem with _$RoutineDayItem {
  const factory RoutineDayItem({
    required int id,
    required String title,
    String? description,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
    required DateTime createdAt,
    required DateTime updatedAt,
    required bool completed,
    required int currentStreak,
    required int longestStreak,
  }) = _RoutineDayItem;

  factory RoutineDayItem.fromJson(Map<String, dynamic> json) =>
      _$RoutineDayItemFromJson(json);
}
