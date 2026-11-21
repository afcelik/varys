import 'package:varys/features/planning/domain/task.dart';

/// Pure calendar logic: month grid, month arithmetic with bounds, Turkish
/// names and the client-side task filters for one day. No clock, no time zone
/// conversion: every day is a local-midnight [DateTime] of a plain date.

/// First and last month the calendar may show (the backend's
/// MIN_DAY 2000-01-01 .. MAX_DAY 2100-12-31).
const int calendarMinYear = 2000;
const int calendarMaxYear = 2100;

/// A month of a year.
typedef YearMonth = ({int year, int month});

/// Turkish month names, January first.
const List<String> turkishMonthNames = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

/// Weekday column headers, Monday first.
const List<String> weekdayShortNames = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

/// 'Kasım 2026'.
String monthTitle(int year, int month) => '${turkishMonthNames[month - 1]} $year';

/// One cell of the month grid. [inMonth] is false for the leading days of the
/// previous month and the trailing days of the next month (drawn faded).
class GridCell {
  const GridCell(this.day, {required this.inMonth});

  final DateTime day;
  final bool inMonth;

  @override
  bool operator ==(Object other) =>
      other is GridCell && other.day == day && other.inMonth == inMonth;

  @override
  int get hashCode => Object.hash(day, inMonth);

  @override
  String toString() => 'GridCell(${day.year}-${day.month}-${day.day}, inMonth: $inMonth)';
}

/// Cells of [month] in [year], Monday first, in rows of 7: the month's days
/// plus the previous month's days before the 1st and the next month's days
/// after the last day, filling whole weeks only (4 to 6 rows; no extra empty
/// week is added).
List<GridCell> monthGrid(int year, int month) {
  if (month < 1 || month > 12) throw ArgumentError.value(month, 'month', 'must be 1..12');
  final first = DateTime(year, month, 1);
  final daysInMonth = DateTime(year, month + 1, 0).day;
  final leading = first.weekday - DateTime.monday;
  final rows = ((leading + daysInMonth) / 7).ceil();
  return [
    for (var i = 0; i < rows * 7; i++) _cell(DateTime(year, month, 1 - leading + i), year, month),
  ];
}

GridCell _cell(DateTime day, int year, int month) =>
    GridCell(day, inMonth: day.year == year && day.month == month);

/// Whether [year]/[month] is inside 2000-01 .. 2100-12.
bool isMonthInBounds(int year, int month) =>
    month >= 1 && month <= 12 && year >= calendarMinYear && year <= calendarMaxYear;

/// Whether [day] is inside 2000-01-01 .. 2100-12-31.
bool isDayInBounds(DateTime day) => isMonthInBounds(day.year, day.month);

/// The month [delta] months after [year]/[month] (negative goes back), or
/// null when the result is outside 2000-01 .. 2100-12.
YearMonth? addMonths(int year, int month, int delta) {
  final index = year * 12 + (month - 1) + delta;
  final result = (year: index ~/ 12, month: index % 12 + 1);
  return isMonthInBounds(result.year, result.month) ? result : null;
}

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

bool _open(Task t) => t.status != TaskStatus.done && t.deletedAt == null;

/// Open (not done, not deleted) tasks whose planned date falls on [day].
/// Only the date part counts; a time component is ignored. Input order kept.
List<Task> tasksForDay(Iterable<Task> tasks, DateTime day) => [
  for (final t in tasks)
    if (_open(t) && t.plannedDate != null && _sameDay(t.plannedDate!, day)) t,
];

/// Open (not done, not deleted) tasks whose due date falls on [day].
/// Only the date part counts; a time component is ignored. Input order kept.
List<Task> dueTasksForDay(Iterable<Task> tasks, DateTime day) => [
  for (final t in tasks)
    if (_open(t) && t.dueDate != null && _sameDay(t.dueDate!, day)) t,
];
