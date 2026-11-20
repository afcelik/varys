// MinuteTicker: minute-aligned rebuilds from an injected clock, the midnight
// switch of todayProvider, and timer cleanup. Time only moves with pump();
// pumpAndSettle is never used.

import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/minute_ticker.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';

import '../fake_schedule_repository.dart';

/// A settable clock; counts reads.
class _FakeClock {
  _FakeClock(this.value);

  DateTime value;
  int reads = 0;

  DateTime call() {
    reads++;
    return value;
  }
}

class _FixedToday extends TodayNotifier {
  _FixedToday(this.day);

  final DateTime day;

  @override
  DateTime build() => day;
}

final _monday = scheduleFixtureDay; // 2026-11-02
final _tuesday = DateTime(2026, 11, 3);

void main() {
  late _FakeClock clock;
  late FakeScheduleRepository repo;
  late ProviderContainer container;

  void makeContainer(DateTime start, {DateTime? today}) {
    clock = _FakeClock(start);
    repo = FakeScheduleRepository();
    container = ProviderContainer(
      overrides: [
        nowProvider.overrideWithValue(clock.call),
        todayProvider.overrideWith(
          () => _FixedToday(today ?? DateTime(start.year, start.month, start.day)),
        ),
        scheduleRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    addTearDown(container.dispose);
  }

  Future<void> pumpTicker(WidgetTester tester, Widget Function(BuildContext, DateTime) builder) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MinuteTicker(builder: builder),
        ),
      ),
    );
  }

  Widget clockText(BuildContext _, DateTime now) =>
      Text(ScheduleTime(minuteOfDay(now)).hhmm, key: const ValueKey('time'));

  String shown(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('time'))).data!;

  testWidgets('rebuilds exactly at the next minute boundary, then every minute', (tester) async {
    makeContainer(DateTime(2026, 11, 2, 8, 59, 30));
    await pumpTicker(tester, clockText);
    expect(shown(tester), '08:59');

    clock.value = DateTime(2026, 11, 2, 9, 0, 0);
    await tester.pump(const Duration(seconds: 29));
    expect(shown(tester), '08:59', reason: 'not before the boundary');
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), '09:00');

    clock.value = DateTime(2026, 11, 2, 9, 1, 0);
    await tester.pump(const Duration(seconds: 59));
    expect(shown(tester), '09:00');
    await tester.pump(const Duration(seconds: 1));
    expect(shown(tester), '09:01');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the "Şimdi" status moves when the minute advances', (tester) async {
    makeContainer(DateTime(2026, 11, 2, 8, 59, 0));
    final block = scheduleListFixture().firstWhere((b) => b.id == 2); // 08:30-09:00
    await pumpTicker(
      tester,
      (_, now) => Text(blockStatusAt(block, minuteOfDay(now)).name, key: const ValueKey('s')),
    );
    String status() => tester.widget<Text>(find.byKey(const ValueKey('s'))).data!;
    expect(status(), 'current');
    clock.value = DateTime(2026, 11, 2, 9, 0, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(status(), 'past', reason: 'end is excluded');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('23:59 -> 00:00: todayProvider moves to the new day; the day list makes one more '
      'request; the late old-day answer is not written; status uses the new day', (tester) async {
    makeContainer(DateTime(2026, 11, 2, 23, 59, 0));
    final answers = <DateTime, Completer<Either<Failure, List<ScheduleBlock>>>>{};
    repo.onDay = (day) {
      final c = Completer<Either<Failure, List<ScheduleBlock>>>();
      answers[day] = c;
      return c.future;
    };

    await pumpTicker(tester, (context, now) {
      return Consumer(
        builder: (context, ref, _) {
          final value = ref.watch(todayScheduleProvider);
          final text = !value.hasValue
              ? 'yükleniyor'
              : value.requireValue
                    .map((b) => '${b.id}:${blockStatusAt(b, minuteOfDay(now)).name}')
                    .join(' ');
          return Text(text, key: const ValueKey('day'));
        },
      );
    });
    String dayText() => tester.widget<Text>(find.byKey(const ValueKey('day'))).data!;

    expect(answers.keys, [_monday]);
    // The Monday answer is parked: it arrives only after midnight.

    clock.value = DateTime(2026, 11, 3, 0, 0, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(container.read(todayProvider), _tuesday);
    await tester.pump();
    expect(answers.keys, [_monday, _tuesday], reason: 'exactly one more request');

    answers[_tuesday]!.complete(
      Right([
        for (final b in repo.sorted)
          if (FakeScheduleRepository.isDue(b, _tuesday)) b,
      ]),
    );
    await tester.pump();
    await tester.pump();
    answers[_monday]!.complete(Right(scheduleDayFixture()));
    await tester.pump();
    await tester.pump();

    // Tuesday: no weekly block 2 (Mon/Wed/Fri) and no every-3-days block 5 (due on the
    // 2nd and 5th); at 00:00 only the 00:00-23:59 block is current.
    expect(dayText(), '6:current 1:upcoming 3:upcoming 7:upcoming');
    expect(repo.dayCalls, 2);

    // Later minutes on the same day do not switch again.
    clock.value = DateTime(2026, 11, 3, 0, 1, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(repo.dayCalls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a differing day at mount time is not synced (left to resume handling)', (
    tester,
  ) async {
    makeContainer(DateTime(2026, 11, 20, 10, 0, 0), today: _monday);
    await pumpTicker(tester, clockText);
    clock.value = DateTime(2026, 11, 20, 10, 1, 0);
    await tester.pump(const Duration(minutes: 1));
    clock.value = DateTime(2026, 11, 20, 10, 2, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(shown(tester), '10:02');
    expect(container.read(todayProvider), _monday);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dispose cancels the timer: no pending timer is left', (tester) async {
    makeContainer(DateTime(2026, 11, 2, 8, 59, 30));
    await pumpTicker(tester, clockText);
    await tester.pumpWidget(const SizedBox());
    // The test binding fails this test if a Timer is still pending here.
  });

  testWidgets('after dispose nothing reads the clock or rebuilds', (tester) async {
    makeContainer(DateTime(2026, 11, 2, 8, 59, 30));
    await pumpTicker(tester, clockText);
    await tester.pumpWidget(const SizedBox());
    final reads = clock.reads;
    await tester.pump(const Duration(minutes: 3));
    expect(clock.reads, reads);
    expect(tester.takeException(), isNull);
  });
}
