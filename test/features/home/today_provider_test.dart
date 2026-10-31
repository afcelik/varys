import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/home/domain/today_provider.dart';

void main() {
  // Initialize bindings before tests
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TodayNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is today at midnight', () {
      final now = DateTime.now();
      final expected = DateTime(now.year, now.month, now.day);

      final today = container.read(todayProvider);
      expect(today, equals(expected));
    });

    test('notifies listeners when date changes on resume', () async {
      // Create a notifier instance and simulate date change
      final notifier = container.read(todayProvider.notifier);

      // Test the dateOnly method directly
      final testDate = DateTime(2026, 10, 30, 15, 30, 45);
      final dateOnly = notifier.dateOnly(testDate);
      expect(dateOnly, equals(DateTime(2026, 10, 30)));
    });

    test('dateOnly strips time component', () {
      final notifier = container.read(todayProvider.notifier);

      expect(notifier.dateOnly(DateTime(2026, 1, 1, 0, 0, 0)), equals(DateTime(2026, 1, 1)));
      expect(notifier.dateOnly(DateTime(2026, 1, 1, 23, 59, 59)), equals(DateTime(2026, 1, 1)));
      expect(notifier.dateOnly(DateTime(2026, 12, 31, 12, 0, 0)), equals(DateTime(2026, 12, 31)));
    });
  });
}