import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:varys/features/home/data/date_utils.dart';

part 'calendar_month.freezed.dart';
part 'calendar_month.g.dart';

/// A plain calendar date `YYYY-MM-DD` <-> local midnight [DateTime].
///
/// No time zone conversion: the date parts are read as they are. A value with
/// a time or zone part is rejected (the backend sends a DATE here).
class CalendarDayConverter implements JsonConverter<DateTime, String> {
  const CalendarDayConverter();

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  @override
  DateTime fromJson(String json) {
    final match = _pattern.firstMatch(json);
    if (match == null) throw FormatException('Not a plain date', json);
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      throw FormatException('Invalid calendar date', json);
    }
    return date;
  }

  @override
  String toJson(DateTime object) => formatDateForApi(object);
}

/// Counts for one day of `GET /calendar/month` (backend CalendarDayRead).
///
/// [taskCount]: open tasks planned on this day; [dueCount]: open tasks due on
/// this day (done tasks are never counted); [routineCount] / [scheduleCount]:
/// routines and schedule blocks due on this day.
@freezed
abstract class CalendarDay with _$CalendarDay {
  const factory CalendarDay({
    @CalendarDayConverter() required DateTime day,
    required int taskCount,
    required int dueCount,
    required int routineCount,
    required int scheduleCount,
  }) = _CalendarDay;

  factory CalendarDay.fromJson(Map<String, dynamic> json) => _$CalendarDayFromJson(json);
}

/// Every day of one month in order (backend CalendarMonthRead).
@freezed
abstract class CalendarMonth with _$CalendarMonth {
  const factory CalendarMonth({
    required int year,
    required int month,
    required List<CalendarDay> days,
  }) = _CalendarMonth;

  factory CalendarMonth.fromJson(Map<String, dynamic> json) => _$CalendarMonthFromJson(json);
}
