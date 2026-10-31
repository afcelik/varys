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