import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';
import 'package:varys/features/schedule/presentation/schedule_list_notifier.dart';

import '../fake_schedule_repository.dart';

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

  List<int> ids(AsyncValue<List<ScheduleBlock>> v) => v.requireValue.map((b) => b.id).toList();

  group('loading a day', () {
    test('requests the given day and orders by start time, then id', () async {
      container.listen(scheduleForDayProvider(_day), (_, _) {});
      await _flush();
      expect(repo.dayRequests, [_day]);
      expect(ids(container.read(scheduleForDayProvider(_day))), [6, 1, 2, 3, 7, 5]);
    });

    test('client sorts even if the server answers out of order', () async {
      repo.onDay = (_) async => Right(scheduleDayFixture().reversed.toList());
      container.listen(scheduleForDayProvider(_day), (_, _) {});
      await _flush();
      expect(ids(container.read(scheduleForDayProvider(_day))), [6, 1, 2, 3, 7, 5]);
    });

    test('error becomes the provider error (the Failure itself)', () async {
      const failure = ServerFailure(
        'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
        statusCode: 500,
      );
      repo.dayFailure = failure;
      container.listen(scheduleForDayProvider(_day), (_, _) {});
      await _flush();
      expect(container.read(scheduleForDayProvider(_day)).error, failure);
    });

    test('todayScheduleProvider follows todayProvider', () async {
      container.listen(todayScheduleProvider, (_, _) {});
      await _flush();
      expect(repo.dayRequests, [_day]);
      expect(ids(container.read(todayScheduleProvider)), [6, 1, 2, 3, 7, 5]);
    });
  });

  group('day change (midnight / resume)', () {
    test('exactly one more request, for the new day', () async {
      container.listen(todayScheduleProvider, (_, _) {});
      await _flush();
      container.read(todayProvider.notifier).syncDate(DateTime(2026, 11, 3, 0, 0));
      await _flush();
      expect(repo.dayRequests, [_day, _nextDay]);
      // Tuesday: the weekly Mon/Wed/Fri block (2) is not scheduled.
      expect(ids(container.read(todayScheduleProvider)), [6, 1, 3, 7]);
      await _flush();
      expect(repo.dayCalls, 2, reason: 'no extra requests after the switch');
    });

    test('a late answer for the old day is never written into the new day', () async {
      final answers = <DateTime, Completer<Either<Failure, List<ScheduleBlock>>>>{};
      repo.onDay = (day) {
        final c = Completer<Either<Failure, List<ScheduleBlock>>>();
        answers[day] = c;
        return c.future;
      };
      container.listen(todayScheduleProvider, (_, _) {});
      await _flush();
      container.read(todayProvider.notifier).syncDate(DateTime(2026, 11, 3, 0, 0));
      await _flush();
      expect(answers.keys, [_day, _nextDay]);

      final newDayBlocks = [scheduleDayFixture().first];
      answers[_nextDay]!.complete(Right(newDayBlocks));
      await _flush();
      answers[_day]!.complete(Right(scheduleDayFixture()));
      await _flush();

      expect(container.read(todayScheduleProvider).requireValue, newDayBlocks);
      expect(repo.dayCalls, 2);
    });

    test('syncDate with the same day (later time) does not reload', () async {
      container.listen(todayScheduleProvider, (_, _) {});
      await _flush();
      container.read(todayProvider.notifier).syncDate(DateTime(2026, 11, 2, 23, 59));
      await _flush();
      expect(repo.dayCalls, 1);
    });
  });

  test('invalidate keeps the old content while reloading (no skeleton flash)', () async {
    container.listen(scheduleForDayProvider(_day), (_, _) {});
    await _flush();
    repo.dayGate = Completer<void>();
    container.invalidate(scheduleForDayProvider(_day));
    await _flush();
    final v = container.read(scheduleForDayProvider(_day));
    expect(v.isLoading, isTrue);
    expect(v.hasValue, isTrue);
    expect(ids(v), [6, 1, 2, 3, 7, 5]);
    repo.dayGate!.complete();
    await _flush();
    expect(container.read(scheduleForDayProvider(_day)).isLoading, isFalse);
    expect(repo.dayCalls, 2);
  });

  group('quickAdd', () {
    ScheduleDayNotifier notifier() => container.read(scheduleForDayProvider(_day).notifier);

    setUp(() async {
      container.listen(scheduleForDayProvider(_day), (_, _) {});
      await _flush();
    });

    test(
      'creates a daily block starting on this day; server result applied at once, in order',
      () async {
        repo.dayGate = Completer<void>(); // park the silent refresh
        final result = await notifier().quickAdd(_parsed('08:30-09:00 kahvaltı'));
        final created = result.fold((f) => fail('$f'), (b) => b!);

        expect(repo.createBodies, hasLength(1));
        final body = repo.createBodies.single;
        expect(body['title'], 'kahvaltı');
        expect((body['start_time'], body['end_time']), ('08:30', '09:00'));
        expect(body['recurrence_type'], 'daily');
        expect(body['start_date'], _day);

        await _flush();
        // Before the refresh answers: inserted after the 08:30 block 2 (lower id).
        expect(ids(container.read(scheduleForDayProvider(_day))), [6, 1, 2, created.id, 3, 7, 5]);
        expect(repo.dayCalls, 2, reason: 'one silent refresh');
        repo.dayGate!.complete();
        await _flush();
        expect(ids(container.read(scheduleForDayProvider(_day))), [6, 1, 2, created.id, 3, 7, 5]);
        expect(container.read(scheduleForDayProvider(_day)).isLoading, isFalse);
      },
    );

    test('a second call while the first is in flight sends nothing', () async {
      repo.mutationGate = Completer<void>();
      final first = notifier().quickAdd(_parsed('08:30-09:00 kahvaltı'));
      final second = await notifier().quickAdd(_parsed('08:30-09:00 kahvaltı'));
      expect(second.fold((f) => fail('$f'), (b) => b), isNull);
      expect(notifier().isQuickAdding, isTrue);
      repo.mutationGate!.complete();
      await first;
      expect(repo.createBodies, hasLength(1));
      expect(notifier().isQuickAdding, isFalse);
    });

    test('server error: Left, list unchanged, no refresh', () async {
      const failure = ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);
      repo.createFailure = failure;
      final before = container.read(scheduleForDayProvider(_day)).requireValue;
      final result = await notifier().quickAdd(_parsed('08:30-09:00 kahvaltı'));
      expect(result.fold((f) => f, (_) => fail('expected Left')), failure);
      await _flush();
      expect(container.read(scheduleForDayProvider(_day)).requireValue, before);
      expect(repo.dayCalls, 1);
    });

    test('newest refresh wins: an older refresh answering late is ignored', () async {
      final refreshes = <Completer<Either<Failure, List<ScheduleBlock>>>>[];
      repo.onDay = (_) {
        final c = Completer<Either<Failure, List<ScheduleBlock>>>();
        refreshes.add(c);
        return c.future;
      };
      await notifier().quickAdd(_parsed('08:30-09:00 a'));
      await notifier().quickAdd(_parsed('10:00-11:00 b'));
      await _flush();
      expect(refreshes, hasLength(2));
      final newest = [...repo.sorted.where((b) => FakeScheduleRepository.isDue(b, _day))];
      refreshes[1].complete(Right(newest));
      await _flush();
      refreshes[0].complete(Right([scheduleDayFixture().first]));
      await _flush();
      expect(container.read(scheduleForDayProvider(_day)).requireValue, sortBlocks(newest));
    });

    test('a failed refresh keeps the list', () async {
      repo.dayFailure = const NetworkFailure('Bağlantı hatası');
      final created = (await notifier().quickAdd(
        _parsed('08:30-09:00 kahvaltı'),
      )).fold((f) => fail('$f'), (b) => b!);
      await _flush();
      final v = container.read(scheduleForDayProvider(_day));
      expect(v.hasError, isFalse);
      expect(v.requireValue.map((b) => b.id), contains(created.id));
    });

    test('invalidates the /schedule list only when it exists', () async {
      await notifier().quickAdd(_parsed('08:30-09:00 a'));
      await _flush();
      expect(repo.listCalls, 0, reason: 'the list is not created from Home');

      container.listen(scheduleBlocksProvider, (_, _) {});
      await _flush();
      expect(repo.listCalls, 1);
      await notifier().quickAdd(_parsed('10:00-11:00 b'));
      await _flush();
      expect(repo.listCalls, 2, reason: 'one reload of the open list');
      await _flush();
      expect(repo.dayCalls, 3, reason: 'initial + one refresh per quick add, no loop');
    });

    test('closing the card while the request runs does not throw; state not written', () async {
      container.dispose();
      container = ProviderContainer(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          scheduleRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
      final sub = container.listen(scheduleForDayProvider(_day), (_, _) {});
      await _flush();
      repo.mutationGate = Completer<void>();
      final pending = container
          .read(scheduleForDayProvider(_day).notifier)
          .quickAdd(_parsed('08:30-09:00 kahvaltı'));
      sub.close(); // card gone; keepAlive holds the provider while in flight
      await _flush();
      repo.mutationGate!.complete();
      final result = await pending;
      expect(result.isRight(), isTrue);
      await _flush();
      expect(repo.createBodies, hasLength(1));
    });

    test('container disposed mid-request: no uncaught error', () async {
      repo.mutationGate = Completer<void>();
      final pending = notifier().quickAdd(_parsed('08:30-09:00 kahvaltı'));
      await _flush();
      container.dispose();
      repo.mutationGate!.complete();
      await expectLater(pending, completes);
      container = ProviderContainer(); // for tearDown
    });
  });
}
