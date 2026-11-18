import 'package:intl/intl.dart';

/// Formats a [DateTime] as "YYYY-MM-DD" for API requests.
String formatDateForApi(DateTime date) {
  return DateFormat('yyyy-MM-dd').format(date);
}

/// Formats a [DateTime] for display in Turkish locale.
/// Example: "Cuma, 30 Ekim"
String formatDateForDisplay(DateTime date, {String locale = 'tr_TR'}) {
  return DateFormat('EEEE, d MMMM', locale).format(date);
}

/// Formats a local calendar day as "YYYY-MM-DDT00:00:00" for API requests.
/// Used for every task day in request bodies (planned_date AND due_date).
/// This is a naive datetime (no timezone suffix) representing the start of the day.
/// The backend filters tasks by date component only (func.date(planned_date)).
String plannedDateForApi(DateTime localDay) {
  final dateOnly = DateTime(localDay.year, localDay.month, localDay.day);
  return DateFormat('yyyy-MM-ddTHH:mm:ss').format(dateOnly);
}

/// Extracts the date component (year, month, day) from a [DateTime] without
/// any timezone conversion. Does NOT use .toLocal() or .toUtc().
/// Simply extracts year/month/day from the parsed DateTime.
/// Used when reading planned_date from API responses.
DateTime dayOnly(DateTime dateTime) {
  return DateTime(dateTime.year, dateTime.month, dateTime.day);
}