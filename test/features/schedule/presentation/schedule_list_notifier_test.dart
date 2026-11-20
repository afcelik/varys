import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';
import 'package:varys/features/schedule/presentation/schedule_list_notifier.dart';

import '../fake_schedule_repository.dart';

final _day = scheduleFixtureDay;

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ScheduleTime _t(String s) => ScheduleTime.parse(s);

void main() {
  late FakeScheduleRepository repo;
  late ProviderContainer container;

  ProviderContainer makeContainer() => ProviderContainer(
    overrides: [
      todayProvider.overrideWith(_FixedToday.new),
      scheduleRepositoryProvider.overrideWith((ref) async => repo),
    ],
  );

  setUp(() async {
    repo = FakeScheduleRepository();
    container = makeContainer();
    // An open /schedule page and the Home card.
    container.listen(scheduleBlocksProvider, (_, _) {});
    container.listen(todayScheduleProvider, (_, _) {});
    await _flush();
    expect((repo.listCalls, repo.dayCalls), (1, 1));
  });

  tearDown(() => container.dispose());

  ScheduleListNotifier notifier() => container.read(scheduleBlocksProvider.notifier);
  List<int> listIds() =>
      container.read(scheduleBlocksProvider).requireValue.map((b) => b.id).toList();

  Future<Either<Failure, ScheduleBlock>> create({String start = '07:30', String end = '08:00'}) =>
      notifier().createBlock(
        title: 'Yeni blok',
        startTime: _t(start),
        endTime: _t(end),
        recurrenceType: RecurrenceType.daily,
        startDate: _day,
      );

  test('loads GET /schedule in start time/id order', () {
    expect(listIds(), [6, 1, 2, 3, 7, 4, 5]);
  });

  group('create', () {
    test('server result applied at once, sorted; then one silent refresh', () async {
      repo.listGate = Completer<void>(); // park the refresh
      final created = (await create()).fold((f) => fail('$f'), (b) => b);
      expect(listIds(), [6, 1, created.id, 2, 3, 7, 4, 5]);
      expect(container.read(scheduleBlocksProvider).isLoading, isFalse, reason: 'no skeleton');
      await _flush();
      expect(repo.listCalls, 2);
      repo.listGate!.complete();
      await _flush();
      expect(listIds(), [6, 1, created.id, 2, 3, 7, 4, 5]);
    });

    test('the Home day list is invalidated exactly once; no loop', () async {
      await create();
      await _flush();
      expect(repo.dayCalls, 2);
      expect(
        container.read(todayScheduleProvider).requireValue.map((b) => b.title),
        contains('Yeni blok'),
      );
      for (var i = 0; i < 5; i++) {
        await _flush();
      }
      expect((repo.listCalls, repo.dayCalls), (2, 2), reason: 'counts stay put');
    });

    test('server error: Left, list and day untouched, nothing re-fetched', () async {
      repo.createFailure = const ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);
      final result = await create();
      expect(result.fold((f) => (f as ServerFailure).statusCode, (_) => null), 422);
      await _flush();
      expect(listIds(), [6, 1, 2, 3, 7, 4, 5]);
      expect((repo.listCalls, repo.dayCalls), (1, 1));
    });
  });

  group('update', () {
    test('empty changes send no request and return Right(null)', () async {
      final result = await notifier().updateBlock(1, const ScheduleChanges());
      expect(result.fold((f) => fail('$f'), (b) => b), isNull);
      expect(repo.updateCalls, isEmpty);
      await _flush();
      expect((repo.listCalls, repo.dayCalls), (1, 1));
    });

    test('result applied and re-sorted at once; one day invalidation', () async {
      repo.listGate = Completer<void>();
      final result = await notifier().updateBlock(
        5,
        ScheduleChanges(startTime: PlanField.set(_t('05:00')), endTime: PlanField.set(_t('05:30'))),
      );
      expect(result.isRight(), isTrue);
      expect(listIds(), [6, 5, 1, 2, 3, 7, 4]);
      await _flush();
      expect(repo.dayCalls, 2);
      repo.listGate!.complete();
      await _flush();
      expect((repo.listCalls, repo.dayCalls), (2, 2));
    });

    test('description cleared: the cleared value is applied', () async {
      await notifier().updateBlock(1, const ScheduleChanges(description: PlanField.clear()));
      expect(repo.updateCalls.single.$2, {'description': null});
      final b = container.read(scheduleBlocksProvider).requireValue.firstWhere((b) => b.id == 1);
      expect(b.description, isNull);
    });

    test('404: Left with the fixed message; silent refresh drops the stale row', () async {
      repo.server = repo.server.where((b) => b.id != 4).toList(); // deleted elsewhere
      final result = await notifier().updateBlock(
        4,
        const ScheduleChanges(title: PlanField.set('x')),
      );
      final failure = result.fold((f) => f, (_) => fail('expected Left'));
      expect(failure.userMessage, 'Kaynak bulunamadı.');
      expect(listIds(), contains(4), reason: 'not removed before the server says so');
      await _flush();
      expect(listIds(), isNot(contains(4)));
      expect(container.read(scheduleBlocksProvider).isLoading, isFalse);
      expect((repo.listCalls, repo.dayCalls), (2, 2));
    });

    test('422: Left, no refresh, list unchanged', () async {
      final result = await notifier().updateBlock(
        1,
        ScheduleChanges(endTime: PlanField.set(_t('06:00'))),
      );
      expect(result.fold((f) => (f as ServerFailure).statusCode, (_) => null), 422);
      await _flush();
      expect((repo.listCalls, repo.dayCalls), (1, 1));
      expect(listIds(), [6, 1, 2, 3, 7, 4, 5]);
    });
  });

  group('delete', () {
    test('removed at once; one day invalidation; one refresh', () async {
      final result = await notifier().deleteBlock(2);
      expect(result.isRight(), isTrue);
      expect(listIds(), [6, 1, 3, 7, 4, 5]);
      await _flush();
      expect((repo.listCalls, repo.dayCalls), (2, 2));
      expect(
        container.read(todayScheduleProvider).requireValue.map((b) => b.id),
        isNot(contains(2)),
      );
    });

    test('404 -> Left; refresh removes the row', () async {
      repo.server = repo.server.where((b) => b.id != 2).toList();
      final result = await notifier().deleteBlock(2);
      expect(result.fold((f) => (f as ServerFailure).statusCode, (_) => null), 404);
      await _flush();
      expect(listIds(), isNot(contains(2)));
    });
  });

  group('silent refresh', () {
    test('a failed refresh keeps the list (no error state)', () async {
      repo.listFailure = const NetworkFailure('Bağlantı hatası');
      await notifier().deleteBlock(2);
      await _flush();
      final v = container.read(scheduleBlocksProvider);
      expect(v.hasError, isFalse);
      expect(listIds(), [6, 1, 3, 7, 4, 5]);
    });

    test('newest wins: an older refresh answering late is ignored', () async {
      final refreshes = <Completer<Either<Failure, List<ScheduleBlock>>>>[];
      repo.onList = () {
        final c = Completer<Either<Failure, List<ScheduleBlock>>>();
        refreshes.add(c);
        return c.future;
      };
      await notifier().deleteBlock(2);
      await notifier().deleteBlock(3);
      await _flush();
      expect(refreshes, hasLength(2));
      refreshes[1].complete(Right(repo.sorted));
      await _flush();
      refreshes[0].complete(Right(scheduleListFixture())); // stale: still has 2 and 3
      await _flush();
      expect(listIds(), [6, 1, 7, 4, 5]);
    });

    test('first load still running: it is restarted, not overwritten by a stale list', () async {
      container.dispose();
      container = makeContainer();
      final loads = <Completer<Either<Failure, List<ScheduleBlock>>>>[];
      repo.onList = () {
        final c = Completer<Either<Failure, List<ScheduleBlock>>>();
        loads.add(c);
        return c.future;
      };
      container.listen(scheduleBlocksProvider, (_, _) {});
      await _flush();
      await notifier().deleteBlock(2);
      await _flush();
      expect(loads, hasLength(2), reason: 'first load restarted');
      loads[0].complete(Right(scheduleListFixture())); // from before the delete
      loads[1].complete(Right(repo.sorted));
      await _flush();
      expect(listIds(), [6, 1, 3, 7, 4, 5]);
    });
  });

  group('lifecycle', () {
    test('page closed mid-request: no throw; the mutation still finishes', () async {
      container.dispose();
      container = makeContainer();
      final sub = container.listen(scheduleBlocksProvider, (_, _) {});
      await _flush();
      repo.mutationGate = Completer<void>();
      final pending = create();
      sub.close();
      await _flush();
      repo.mutationGate!.complete();
      final result = await pending;
      expect(result.isRight(), isTrue);
      await _flush();
      expect(repo.server.map((b) => b.title), contains('Yeni blok'));
    });

    test('container disposed mid-request: completes without an uncaught error', () async {
      repo.mutationGate = Completer<void>();
      final pending = create();
      await _flush();
      container.dispose();
      repo.mutationGate!.complete();
      await expectLater(pending, completes);
      container = makeContainer(); // for tearDown
    });

    test('a list rebuild never invalidates the day list (no loop)', () async {
      container.invalidate(scheduleBlocksProvider);
      await _flush();
      expect((repo.listCalls, repo.dayCalls), (2, 1));
    });
  });
}
