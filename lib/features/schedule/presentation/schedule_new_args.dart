import 'package:flutter/foundation.dart';

/// Optional `extra` of `/schedule/new` (e.g. from the calendar's
/// 'Bu güne blok ekle'): the form starts on [day] (date part only) and, when
/// [once] is true, with the one-time type selected. Without an extra the form
/// starts today with the daily type.
@immutable
class ScheduleNewArgs {
  const ScheduleNewArgs({required this.day, this.once = false});

  final DateTime day;
  final bool once;

  @override
  bool operator ==(Object other) =>
      other is ScheduleNewArgs &&
      other.day.year == day.year &&
      other.day.month == day.month &&
      other.day.day == day.day &&
      other.once == once;

  @override
  int get hashCode => Object.hash(day.year, day.month, day.day, once);

  @override
  String toString() => 'ScheduleNewArgs(day: $day, once: $once)';
}
