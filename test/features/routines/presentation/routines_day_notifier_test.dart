import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routines_day_notifier.dart';

typedef _DayResult = Either<Failure, List<RoutineDayItem>>;
typedef _WriteResult = Either<Failure, void>;

/// Fake repository: every call is parked on a Completer so each test decides
/// when and in which order responses arrive. Returns real Left/Right values.
class _FakeRoutineRepository implements RoutineRepository {
  final gets = <(DateTime, Completer<_DayResult>)>[];
  final writes = <(String, int, DateTime, Completer<_WriteResult>)>[];

  // CRUD methods are not used by the day notifier.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<_DayResult> getRoutinesForDay(DateTime day) {
    final c = Completer<_DayResult>();
    gets.add((day, c));
    return c.future;
  }

  @override
  Future<_WriteResult> markDone(int routineId, DateTime day) => _write('done', routineId, day);

  @override
  Future<_WriteResult> undo(int routineId, DateTime day) => _write('undo', routineId, day);

  Future<_WriteResult> _write(String op, int id, DateTime day) {
    final c = Completer<_WriteResult>();
    writes.add((op, id, day, c));
    return c.future;
  }
}

final _day = DateTime(2026, 11, 16);
const _serverError = ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
    statusCode: 500);

class _TestToday extends TodayNotifier {
  @override
  DateTime build() => _day;

  void setDay(DateTime day) => state = day;
}

/// Real backend JSON (GET /routines/day/2026-11-16).
/// id 1 daily completed streak 3; ids 2, 3, 4 open, streak 0.
List<RoutineDayItem> _fixture() =>
    (jsonDecode(File('test/fixtures/routines_day.json').readAsStringSync()) as List<dynamic>)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();

/// [base] with the given (completed, streak) per id.
List<RoutineDayItem> _with(List<RoutineDayItem> base, Map<int, (bool, int)> changes) => [
      for (final i in base)
        changes.containsKey(i.id)
            ? i.copyWith(completed: changes[i.id]!.$1, currentStreak: changes[i.id]!.$2)
            : i,
    ];

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakeRoutineRepository repo;
  late ProviderContainer container;
  late List<AsyncValue<List<RoutineDayItem>>> emitted;
  late List<RoutineDayItem> base;

  RoutinesDayNotifier notifier() => container.read(routinesForDayProvider(_day).notifier);
  List<RoutineDayItem> items() => container.read(routinesForDayProvider(_day)).requireValue;
  RoutineDayItem item(int id) => items().firstWhere((i) => i.id == id);

  setUp(() async {
    repo = _FakeRoutineRepository();
    base = _fixture();
    container = ProviderContainer(overrides: [
      todayProvider.overrideWith(_TestToday.new),
      routineRepositoryProvider.overrideWith((ref) async => repo),
    ]);
    emitted = [];
    container.listen(routinesForDayProvider(_day), (_, next) => emitted.add(next),
        fireImmediately: true);
  });

  tearDown(() => container.dispose());

  Future<void> loadInitial() async {
    await _flush();
    expect(repo.gets, hasLength(1));
    expect(repo.gets.single.$1, _day);
    repo.gets.single.$2.complete(Right(base));
    await _flush();
    expect(items(), base);
    emitted.clear();
  }

  test('initial load Left -> AsyncError whose userMessage is the fixed Turkish text', () async {
    await _flush();
    repo.gets.single.$2.complete(const Left(_serverError));
    await _flush();

    final value = container.read(routinesForDayProvider(_day));
    expect(value.hasError, isTrue);
    expect(userMessage(value.error!), 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.');
  });

  test('toggle before load sends nothing and returns ValidationFailure', () async {
    final result = await notifier().toggle(2);
    expect(result.fold((f) => f, (_) => null), isA<ValidationFailure>());
    expect(repo.writes, isEmpty);
  });

  test('optimistic toggle, then silent refresh updates the streak without loading', () async {
    await loadInitial();

    final pending = notifier().toggle(2);
    expect(item(2).completed, isTrue, reason: 'flipped before the request returns');
    await _flush();
    expect(repo.writes.single.$1, 'done');
    expect(repo.writes.single.$2, 2);
    expect(repo.writes.single.$3, _day);
    expect(notifier().isPending(2), isTrue);

    repo.writes.single.$4.complete(const Right(null));
    expect((await pending).isRight(), isTrue);
    expect(notifier().isPending(2), isFalse);
    await _flush();

    expect(repo.gets, hasLength(2), reason: 'silent refresh of the same day');
    expect(repo.gets.last.$1, _day);
    repo.gets.last.$2.complete(Right(_with(base, {2: (true, 1)})));
    await _flush();

    expect(item(2).completed, isTrue);
    expect(item(2).currentStreak, 1);
    expect(emitted.any((v) => v.isLoading), isFalse, reason: 'no skeleton flash');
    expect(emitted.every((v) => v.hasValue && !v.hasError), isTrue);
  });

  test('toggling a completed routine calls undo', () async {
    await loadInitial();

    final pending = notifier().toggle(1);
    expect(item(1).completed, isFalse);
    await _flush();
    expect(repo.writes.single.$1, 'undo');
    expect(repo.writes.single.$2, 1);
    repo.writes.single.$4.complete(const Right(null));
    expect((await pending).isRight(), isTrue);
  });

  test('failure rolls back ONLY that item: A fails while B keeps its change', () async {
    await loadInitial();

    final a = notifier().toggle(2);
    final b = notifier().toggle(3);
    await _flush();
    expect(item(2).completed, isTrue);
    expect(item(3).completed, isTrue);

    repo.writes[0].$4.complete(const Left(_serverError));
    final aResult = await a;
    expect(aResult.fold((f) => f, (_) => null), _serverError);
    expect(item(2).completed, isFalse, reason: 'A rolled back');
    expect(item(3).completed, isTrue, reason: 'B untouched while in flight');
    expect(repo.gets, hasLength(1), reason: 'no refresh after a failure');

    repo.writes[1].$4.complete(const Right(null));
    expect((await b).isRight(), isTrue);
    expect(item(3).completed, isTrue);
  });

  test('refresh failure keeps the optimistic state and shows no error', () async {
    await loadInitial();

    final pending = notifier().toggle(2);
    await _flush();
    repo.writes.single.$4.complete(const Right(null));
    expect((await pending).isRight(), isTrue);
    await _flush();
    repo.gets.last.$2.complete(const Left(_serverError));
    await _flush();

    final value = container.read(routinesForDayProvider(_day));
    expect(value.hasError, isFalse);
    expect(item(2).completed, isTrue);
  });

  test('stale refresh is ignored: A refresh returns after B refresh, B state kept', () async {
    await loadInitial();

    final a = notifier().toggle(2);
    await _flush();
    repo.writes[0].$4.complete(const Right(null));
    await a;
    await _flush();
    final refreshA = repo.gets.last.$2; // in flight

    final b = notifier().toggle(3);
    await _flush();
    repo.writes[1].$4.complete(const Right(null));
    await b;
    await _flush();
    final refreshB = repo.gets.last.$2;
    expect(identical(refreshA, refreshB), isFalse);

    refreshB.complete(Right(_with(base, {2: (true, 1), 3: (true, 1)})));
    await _flush();
    expect(item(3).completed, isTrue);
    expect(item(3).currentStreak, 1);

    // A's refresh arrives LAST with data from before B was saved.
    refreshA.complete(Right(_with(base, {2: (true, 1)})));
    await _flush();
    expect(item(3).completed, isTrue, reason: 'old response ignored');
    expect(item(3).currentStreak, 1);
  });

  test('refresh keeps the optimistic value of an item still in flight', () async {
    await loadInitial();

    final a = notifier().toggle(2);
    await _flush();
    final b = notifier().toggle(3); // stays in flight
    await _flush();
    repo.writes[0].$4.complete(const Right(null));
    await a;
    await _flush();

    // Server has not saved B yet: refresh says 3 is open.
    repo.gets.last.$2.complete(Right(_with(base, {2: (true, 1)})));
    await _flush();
    expect(item(2).currentStreak, 1);
    expect(item(3).completed, isTrue, reason: 'B optimistic value kept');

    repo.writes[1].$4.complete(const Right(null));
    await b;
  });

  test('double toggle while in flight sends a single request', () async {
    await loadInitial();

    final first = notifier().toggle(2);
    final second = notifier().toggle(2);
    expect((await second).isRight(), isTrue);
    await _flush();
    expect(repo.writes, hasLength(1));
    expect(item(2).completed, isTrue, reason: 'second call did not flip back');

    repo.writes.single.$4.complete(const Right(null));
    await first;
  });

  test('list reloaded while a toggle is in flight: no crash, no write into new list', () async {
    await loadInitial();

    final pending = notifier().toggle(2);
    await _flush();

    container.invalidate(routinesForDayProvider(_day));
    await _flush();
    // Reload says routine 2 is completed on the server.
    repo.gets.last.$2.complete(Right(_with(base, {2: (true, 1)})));
    await _flush();

    repo.writes.single.$4.complete(const Left(_serverError));
    final result = await pending;
    expect(result.isLeft(), isTrue);
    await _flush();

    expect(item(2).completed, isTrue, reason: 'stale rollback not applied');
    expect(item(2).currentStreak, 1);
    expect(repo.gets, hasLength(2), reason: 'no refresh from the stale toggle');
  });

  test('provider disposed while a toggle is in flight: completes without throwing', () async {
    await loadInitial();

    final pending = notifier().toggle(2);
    await _flush();
    container.dispose();

    repo.writes.single.$4.complete(const Right(null));
    expect((await pending).isRight(), isTrue);
    await _flush();
    expect(repo.gets, hasLength(1), reason: 'no refresh after dispose');

    // Recreate so tearDown can dispose safely.
    container = ProviderContainer();
  });

  test('day change in todayProvider loads the new day', () async {
    final todayValues = <AsyncValue<List<RoutineDayItem>>>[];
    container.listen(todayRoutinesProvider, (_, next) => todayValues.add(next),
        fireImmediately: true);
    await loadInitial();
    expect(container.read(todayRoutinesProvider).requireValue, base);

    final nextDay = DateTime(2026, 11, 17);
    (container.read(todayProvider.notifier) as _TestToday).setDay(nextDay);
    await _flush();

    expect(repo.gets.last.$1, nextDay);
    final nextItems = [base[0]];
    repo.gets.last.$2.complete(Right(nextItems));
    await _flush();
    expect(container.read(todayRoutinesProvider).requireValue, nextItems);
  });
}
