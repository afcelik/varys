import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:varys/features/home/data/date_utils.dart';

void main() {
  // Initialize date formatting for Turkish locale
  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  group('formatDateForApi', () {
    test('formats date as YYYY-MM-DD', () {
      final date = DateTime(2026, 10, 30);
      expect(formatDateForApi(date), equals('2026-10-30'));
    });

    test('handles single digit month and day', () {
      final date = DateTime(2026, 1, 5);
      expect(formatDateForApi(date), equals('2026-01-05'));
    });

    test('handles year boundary', () {
      final date = DateTime(2025, 12, 31);
      expect(formatDateForApi(date), equals('2025-12-31'));
    });
  });

  group('formatDateForDisplay', () {
    test('formats date in Turkish locale (e.g., Cuma, 30 Ekim)', () {
      final date = DateTime(2026, 10, 30); // Friday, October 30, 2026
      final result = formatDateForDisplay(date);
      // In Turkish: "Cuma" = Friday, "Ekim" = October
      expect(result, contains('Cuma'));
      expect(result, contains('Ekim'));
      expect(result, contains('30'));
    });

    test('formats date in Turkish locale for Monday', () {
      final date = DateTime(2026, 11, 2); // Monday, November 2, 2026
      final result = formatDateForDisplay(date);
      // In Turkish: "Pazartesi" = Monday, "Kasım" = November
      expect(result, contains('Pazartesi'));
      expect(result, contains('Kasım'));
    });

    test('handles custom locale parameter', () {
      final date = DateTime(2026, 10, 30);
      final result = formatDateForDisplay(date, locale: 'en_US');
      expect(result, contains('Friday'));
      expect(result, contains('October'));
    });
  });
}