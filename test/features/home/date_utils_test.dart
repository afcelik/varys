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

  group('plannedDateForApi', () {
    test('formats date as YYYY-MM-DDT00:00:00 (naive datetime)', () {
      final date = DateTime(2026, 11, 1);
      expect(plannedDateForApi(date), equals('2026-11-01T00:00:00'));
    });

    test('formats date with time component - time is zeroed', () {
      final date = DateTime(2026, 11, 1, 15, 30, 45);
      expect(plannedDateForApi(date), equals('2026-11-01T00:00:00'));
    });

    test('handles single digit month and day', () {
      final date = DateTime(2026, 1, 5);
      expect(plannedDateForApi(date), equals('2026-01-05T00:00:00'));
    });

    test('handles year boundary', () {
      final date = DateTime(2025, 12, 31);
      expect(plannedDateForApi(date), equals('2025-12-31T00:00:00'));
    });
  });

  group('dayOnly', () {
    test('extracts year/month/day from DateTime without timezone conversion', () {
      final dateTime = DateTime(2026, 11, 1, 15, 30, 45);
      final result = dayOnly(dateTime);
      expect(result.year, equals(2026));
      expect(result.month, equals(11));
      expect(result.day, equals(1));
      expect(result.hour, equals(0));
      expect(result.minute, equals(0));
      expect(result.second, equals(0));
    });

    test('returns correct day for 23:50 local time', () {
      // 23:50 on Nov 1 should still be Nov 1
      final dateTime = DateTime(2026, 11, 1, 23, 50);
      final result = dayOnly(dateTime);
      expect(result.day, equals(1));
      expect(result.month, equals(11));
      expect(result.year, equals(2026));
    });

    test('returns correct day for 00:10 local time', () {
      // 00:10 on Nov 1 should be Nov 1
      final dateTime = DateTime(2026, 11, 1, 0, 10);
      final result = dayOnly(dateTime);
      expect(result.day, equals(1));
      expect(result.month, equals(11));
      expect(result.year, equals(2026));
    });

    test('parses "2026-11-01T00:00:00" as November 1st', () {
      final dateTime = DateTime.parse('2026-11-01T00:00:00');
      final result = dayOnly(dateTime);
      expect(result.day, equals(1));
      expect(result.month, equals(11));
      expect(result.year, equals(2026));
    });

    test('parses datetime with time and extracts correct day', () {
      final dateTime = DateTime.parse('2026-11-01T15:30:00');
      final result = dayOnly(dateTime);
      expect(result.day, equals(1));
      expect(result.month, equals(11));
      expect(result.year, equals(2026));
    });
  });
}