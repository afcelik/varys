import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:varys/features/routines/domain/routine.dart';

part 'schedule_block.freezed.dart';
part 'schedule_block.g.dart';

/// A time of day as minutes since midnight (0..1439). Pure value type: no
/// dependency on Flutter's `TimeOfDay`, no time zone.
@immutable
class ScheduleTime implements Comparable<ScheduleTime> {
  /// [minutes] must be in 0..1439.
  const ScheduleTime(this.minutes)
    : assert(minutes >= minMinutes && minutes <= maxMinutes, 'minutes out of range');

  const ScheduleTime.hm(int hour, int minute) : this(hour * 60 + minute);

  static const int minMinutes = 0;
  static const int maxMinutes = 23 * 60 + 59;

  final int minutes;

  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  /// Strict wire format: two-digit `HH:MM`, 00:00..23:59 (same as the backend).
  static final RegExp _hhmm = RegExp(r'^([01][0-9]|2[0-3]):([0-5][0-9])$');

  /// Parses a strict `HH:MM`; anything else (seconds, `24:00`, `7:05`) is null.
  static ScheduleTime? tryParse(String value) {
    final m = _hhmm.firstMatch(value);
    if (m == null) return null;
    return ScheduleTime.hm(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  /// Like [tryParse] but throws [FormatException].
  static ScheduleTime parse(String value) =>
      tryParse(value) ?? (throw FormatException('time must be HH:MM', value));

  /// `HH:MM`, zero-padded.
  String get hhmm => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  int compareTo(ScheduleTime other) => minutes.compareTo(other.minutes);

  bool operator <(ScheduleTime other) => minutes < other.minutes;
  bool operator <=(ScheduleTime other) => minutes <= other.minutes;

  @override
  bool operator ==(Object other) => other is ScheduleTime && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() => hhmm;
}

/// JSON `HH:MM` <-> [ScheduleTime].
class ScheduleTimeConverter implements JsonConverter<ScheduleTime, String> {
  const ScheduleTimeConverter();

  @override
  ScheduleTime fromJson(String json) => ScheduleTime.parse(json);

  @override
  String toJson(ScheduleTime object) => object.hhmm;
}

/// A schedule block as returned by `GET /schedule` (backend ScheduleRead).
///
/// [startDate] is a plain calendar date (`YYYY-MM-DD`), parsed as a local
/// date with no time zone conversion. [daysOfWeek] uses Monday=0 ... Sunday=6.
@freezed
abstract class ScheduleBlock with _$ScheduleBlock {
  const factory ScheduleBlock({
    required int id,
    required String title,
    String? description,
    @ScheduleTimeConverter() required ScheduleTime startTime,
    @ScheduleTimeConverter() required ScheduleTime endTime,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _ScheduleBlock;

  factory ScheduleBlock.fromJson(Map<String, dynamic> json) => _$ScheduleBlockFromJson(json);
}
