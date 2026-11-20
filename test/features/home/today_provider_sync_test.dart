// TodayNotifier.syncDate: moves todayProvider to the day of a given time,
// but only when the calendar day really changes (no notification otherwise).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/home/domain/today_provider.dart';

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 11, 2);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late List<DateTime> notified;

  setUp(() {
    container = ProviderContainer(overrides: [todayProvider.overrideWith(_FixedToday.new)]);
    notified = [];
    container.listen<DateTime>(todayProvider, (_, next) => notified.add(next));
  });

  tearDown(() => container.dispose());

  test('a later time on the same day: no change, no notification', () {
    final notifier = container.read(todayProvider.notifier);
    expect(notifier.syncDate(DateTime(2026, 11, 2, 23, 59, 59)), isFalse);
    expect(notifier.syncDate(DateTime(2026, 11, 2)), isFalse);
    expect(container.read(todayProvider), DateTime(2026, 11, 2));
    expect(notified, isEmpty);
  });

  test('midnight: moves to the new day (date only) and notifies once', () {
    final notifier = container.read(todayProvider.notifier);
    expect(notifier.syncDate(DateTime(2026, 11, 3, 0, 0, 5)), isTrue);
    expect(container.read(todayProvider), DateTime(2026, 11, 3));
    expect(notified, [DateTime(2026, 11, 3)]);
    expect(notifier.syncDate(DateTime(2026, 11, 3, 0, 1)), isFalse);
    expect(notified, hasLength(1));
  });

  test('month and year boundaries; an earlier day is also applied as is', () {
    final notifier = container.read(todayProvider.notifier);
    notifier.syncDate(DateTime(2026, 12, 31, 23, 59));
    notifier.syncDate(DateTime(2027, 1, 1, 0, 0));
    expect(container.read(todayProvider), DateTime(2027, 1, 1));
    notifier.syncDate(DateTime(2026, 12, 31, 12)); // device clock set back
    expect(container.read(todayProvider), DateTime(2026, 12, 31));
    expect(notified, [DateTime(2026, 12, 31), DateTime(2027, 1, 1), DateTime(2026, 12, 31)]);
  });
}
