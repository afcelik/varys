import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';

import '../fake_schedule_repository.dart';

/// ScheduleDayNotifier.quickAdd with the 'bugün' prefix: a one-time block on
/// the notifier's day; without it, the old daily block. The repository is the
/// server-like fake (real backend JSON, server is_due rules).

final _day = scheduleFixtureDay; // Monday 2026-11-02
final _nextDay = DateTime(2026, 11, 3);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

QuickAddOk _parsed(String input) => parseQuickAdd(input) as QuickAddOk;

void main() {
  late FakeScheduleRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeScheduleRepository();
    container = ProviderContainer(
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        scheduleRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
  });

  tearDown(() => container.dispose());

  ScheduleDayNotifier notifier(DateTime day) =>
      container.read(scheduleForDayProvider(day).notifier);

  List<ScheduleBlock> blocksOn(DateTime day) =>
      container.read(scheduleForDayProvider(day)).requireValue;

  test("'bugün 14:00-15:00 doktor': once on the notifier's day, the three fields null", () async {
    container.listen(scheduleForDayProvider(_day), (_, _) {});
    await _flush();

    final result = await notifier(_day).quickAdd(_parsed('bugün 14:00-15:00 doktor'));
    final created = result.fold((f) => fail('$f'), (b) => b!);

    final body = repo.createBodies.single;
    expect(body['title'], 'doktor');
    expect((body['start_time'], body['end_time']), ('14:00', '15:00'));
    expect(body['recurrence_type'], 'once');
    expect(body['start_date'], _day);
    expect(body['days_of_week'], isNull);
    expect(body['day_of_month'], isNull);
    expect(body['interval_days'], isNull);
    expect(created.recurrenceType, RecurrenceType.once);
    expect(created.startDate, _day);

    await _flush();
    expect(blocksOn(_day).map((b) => b.id), contains(created.id));
  });

  test('the once block is listed only on that day, not the next', () async {
    container.listen(scheduleForDayProvider(_day), (_, _) {});
    await _flush();
    final created = (await notifier(
      _day,
    ).quickAdd(_parsed('BUGÜN 14:00-15:00 doktor'))).fold((f) => fail('$f'), (b) => b!);

    container.listen(scheduleForDayProvider(_nextDay), (_, _) {});
    await _flush();
    expect(blocksOn(_day).map((b) => b.id), contains(created.id));
    expect(blocksOn(_nextDay).map((b) => b.id), isNot(contains(created.id)));
  });

  test('start_date is the family day, not today, for another day', () async {
    container.listen(scheduleForDayProvider(_nextDay), (_, _) {});
    await _flush();
    await notifier(_nextDay).quickAdd(_parsed('bugün 10:00-11:00 x'));
    expect(repo.createBodies.single['recurrence_type'], 'once');
    expect(repo.createBodies.single['start_date'], _nextDay);
  });

  test('without the prefix: daily, as before (also listed the next day)', () async {
    container.listen(scheduleForDayProvider(_day), (_, _) {});
    await _flush();
    final created = (await notifier(
      _day,
    ).quickAdd(_parsed('14:00-15:00 doktor'))).fold((f) => fail('$f'), (b) => b!);
    expect(repo.createBodies.single['recurrence_type'], 'daily');
    expect(repo.createBodies.single['start_date'], _day);

    container.listen(scheduleForDayProvider(_nextDay), (_, _) {});
    await _flush();
    expect(blocksOn(_nextDay).map((b) => b.id), contains(created.id));
  });
}
