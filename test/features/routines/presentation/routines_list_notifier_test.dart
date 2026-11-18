import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routines_day_notifier.dart';
import 'package:varys/features/routines/presentation/routines_list_notifier.dart';

typedef _ListResult = Either<Failure, List<Routine>>;
typedef _RoutineResult = Either<Failure, Routine>;
typedef _VoidResult = Either<Failure, void>;

/// Fake repository: every call is parked on a Completer so each test decides
/// when responses arrive. Returns real Left/Right values and counts calls.
class _FakeRoutineRepository implements RoutineRepository {
  final lists = <Completer<_ListResult>>[];
  final dayGets = <DateTime>[];
  final creates = <Completer<_RoutineResult>>[];
  final updates = <(int, Map<String, dynamic>, Completer<_RoutineResult>)>[];
  final deletes = <(int, Completer<_VoidResult>)>[];

  @override
  Future<_ListResult> getRoutines() {
    final c = Completer<_ListResult>();
    lists.add(c);
    return c.future;
  }

  @override
  Future<Either<Failure, List<RoutineDayItem>>> getRoutinesForDay(DateTime day) async {
    dayGets.add(day);
    return const Right([]);
  }

  @override
  Future<_RoutineResult> createRoutine({
    required String title,
    String? description,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
  }) {
    final c = Completer<_RoutineResult>();
    creates.add(c);
    return c.future;
  }

  @override
  Future<_RoutineResult> updateRoutine(int id, RoutineChanges changes) {
    final c = Completer<_RoutineResult>();
    updates.add((id, changes.toBody(), c));
    return c.future;
  }

  @override
  Future<_VoidResult> deleteRoutine(int id) {
    final c = Completer<_VoidResult>();
    deletes.add((id, c));
    return c.future;
  }

  @override
  Future<_VoidResult> markDone(int routineId, DateTime day) => throw UnimplementedError();

  @override
  Future<_VoidResult> undo(int routineId, DateTime day) => throw UnimplementedError();
}

final _day = DateTime(2026, 11, 16);
const _serverError =
    ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);
const _notFound = ServerFailure('Kaynak bulunamadı.', statusCode: 404);

class _TestToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

/// Real backend JSON (GET /routines): ids 1..4, one per recurrence type.
List<Routine> _fixture() =>
    (jsonDecode(File('test/fixtures/routines_list.json').readAsStringSync()) as List<dynamic>)
        .map((e) => Routine.fromJson(e as Map<String, dynamic>))
        .toList();

/// Real POST /routines 201 body, given a new id.
Routine _created({int id = 5}) => Routine.fromJson(
    jsonDecode(File('test/fixtures/routine_created.json').readAsStringSync())
        as Map<String, dynamic>).copyWith(id: id, title: 'Yeni rutin');

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakeRoutineRepository repo;
  late ProviderContainer container;
  late List<Routine> base;

  RoutinesListNotifier notifier() => container.read(routinesListProvider.notifier);
  List<Routine> list() => container.read(routinesListProvider).requireValue;
  List<String> titles() => list().map((r) => r.title).toList();

  ProviderContainer makeContainer() => ProviderContainer(overrides: [
        todayProvider.overrideWith(_TestToday.new),
        routineRepositoryProvider.overrideWith((ref) async => repo),
      ]);

  setUp(() {
    repo = _FakeRoutineRepository();
    base = _fixture();
    container = makeContainer();
  });

  tearDown(() => container.dispose());

  /// List page + Home card are both alive (both providers listened).
  Future<void> loadBoth() async {
    container.listen(routinesListProvider, (_, _) {}, fireImmediately: true);
    container.listen(routinesForDayProvider(_day), (_, _) {}, fireImmediately: true);
    await _flush();
    repo.lists.single.complete(Right(base));
    await _flush();
    expect(list(), base);
    expect(repo.dayGets, hasLength(1));
  }

  Future<Either<Failure, Routine>> create() => notifier().createRoutine(
        title: 'Yeni rutin',
        recurrenceType: RecurrenceType.weekly,
        daysOfWeek: [0, 2, 4],
        startDate: _day,
      );

  test('build loads GET /routines', () async {
    await loadBoth();
    expect(titles(), ['Su iç', 'Spor', 'Fatura öde', 'Bitki sula']);
  });

  group('create', () {
    test('not optimistic: list unchanged until the server answers', () async {
      await loadBoth();
      final pending = create();
      await _flush();
      expect(repo.creates, hasLength(1));
      expect(list(), base, reason: 'nothing added before the response');
      expect(repo.dayGets, hasLength(1), reason: 'no invalidation before the response');

      repo.creates.single.complete(Right(_created()));
      final result = await pending;
      expect(result.fold((f) => fail('expected Right'), (r) => r.id), 5);
      expect(titles().last, 'Yeni rutin', reason: 'server result applied at once');
    });

    test('success: one silent refresh, Home day re-fetched exactly once, no loop', () async {
      await loadBoth();
      final emitted = <AsyncValue<List<Routine>>>[];
      container.listen(routinesListProvider, (_, next) => emitted.add(next));

      final pending = create();
      await _flush();
      repo.creates.single.complete(Right(_created()));
      await pending;
      await _flush();

      expect(repo.lists, hasLength(2), reason: 'build + one silent refresh');
      repo.lists.last.complete(Right([...base, _created()]));
      await _flush();
      await _flush();

      expect(repo.lists, hasLength(2), reason: 'no further list fetch (no loop)');
      expect(repo.dayGets, hasLength(2), reason: 'day routines invalidated exactly once');
      expect(emitted.where((v) => v.isLoading), isEmpty, reason: 'silent: no loading state');
      expect(list().map((r) => r.id), [1, 2, 3, 4, 5]);
    });

    test('failure: Left, old list stays, no refresh, Home not invalidated', () async {
      await loadBoth();
      final pending = create();
      await _flush();
      repo.creates.single.complete(const Left(_serverError));

      final failure = (await pending).fold((f) => f, (_) => fail('expected Left'));
      expect(failure, _serverError);
      await _flush();
      expect(list(), base);
      expect(repo.lists, hasLength(1));
      expect(repo.dayGets, hasLength(1));
    });
  });

  group('update', () {
    test('server result applied at once; a pending refresh does not show the old title',
        () async {
      await loadBoth();
      final pending = notifier()
          .updateRoutine(2, const RoutineChanges(title: PlanField.set('Koşu')));
      await _flush();
      expect(repo.updates.single.$2, {'title': 'Koşu'});
      expect(titles(), contains('Spor'), reason: 'not optimistic');

      final updated = base[1].copyWith(title: 'Koşu');
      repo.updates.single.$3.complete(Right(updated));
      expect((await pending).isRight(), isTrue);
      await _flush();

      // Refresh is parked: the list already shows the server result.
      expect(repo.lists, hasLength(2));
      expect(titles(), ['Su iç', 'Koşu', 'Fatura öde', 'Bitki sula']);
      expect(titles(), isNot(contains('Spor')));

      repo.lists.last.complete(Right([base[0], updated, base[2], base[3]]));
      await _flush();
      expect(titles(), ['Su iç', 'Koşu', 'Fatura öde', 'Bitki sula']);
      expect(repo.dayGets, hasLength(2));
    });

    test('empty changes: Right(null), no request, nothing invalidated', () async {
      await loadBoth();
      final result = await notifier().updateRoutine(2, const RoutineChanges());
      expect(result.fold((f) => fail('expected Right'), (r) => r), isNull);
      await _flush();
      expect(repo.updates, isEmpty);
      expect(repo.lists, hasLength(1));
      expect(repo.dayGets, hasLength(1));
    });

    test('404 (deleted elsewhere): Left with fixed text and a silent refresh drops the row',
        () async {
      await loadBoth();
      final pending = notifier()
          .updateRoutine(2, const RoutineChanges(title: PlanField.set('Koşu')));
      await _flush();
      repo.updates.single.$3.complete(const Left(_notFound));

      final failure = (await pending).fold((f) => f, (_) => fail('expected Left'));
      expect(failure.userMessage, 'Kaynak bulunamadı.');
      await _flush();
      expect(repo.lists, hasLength(2), reason: '404 triggers a re-fetch');
      expect(titles(), contains('Spor'), reason: 'unchanged until the re-fetch answers');

      repo.lists.last.complete(Right([base[0], base[2], base[3]]));
      await _flush();
      expect(list().map((r) => r.id), [1, 3, 4]);
      expect(repo.dayGets, hasLength(1), reason: 'failure does not invalidate Home');
    });

    test('non-404 failure: no re-fetch, old list stays', () async {
      await loadBoth();
      final pending = notifier()
          .updateRoutine(2, const RoutineChanges(title: PlanField.set('Koşu')));
      await _flush();
      repo.updates.single.$3.complete(const Left(_serverError));
      expect((await pending).isLeft(), isTrue);
      await _flush();
      expect(repo.lists, hasLength(1));
      expect(list(), base);
    });
  });

  group('delete', () {
    test('success: row removed at once, one refresh, Home invalidated once', () async {
      await loadBoth();
      final pending = notifier().deleteRoutine(3);
      await _flush();
      expect(list(), base, reason: 'not optimistic');
      repo.deletes.single.$2.complete(const Right(null));
      expect((await pending).isRight(), isTrue);
      await _flush();

      expect(list().map((r) => r.id), [1, 2, 4]);
      expect(repo.lists, hasLength(2));
      repo.lists.last.complete(Right([base[0], base[1], base[3]]));
      await _flush();
      expect(repo.lists, hasLength(2));
      expect(repo.dayGets, hasLength(2));
    });

    test('404: Left and a silent refresh', () async {
      await loadBoth();
      final pending = notifier().deleteRoutine(3);
      await _flush();
      repo.deletes.single.$2.complete(const Left(_notFound));
      expect((await pending).isLeft(), isTrue);
      await _flush();
      expect(repo.lists, hasLength(2));
      repo.lists.last.complete(Right([base[0], base[1], base[3]]));
      await _flush();
      expect(list().map((r) => r.id), [1, 2, 4]);
    });

    test('failure: old list stays', () async {
      await loadBoth();
      final pending = notifier().deleteRoutine(3);
      await _flush();
      repo.deletes.single.$2.complete(const Left(_serverError));
      expect((await pending).isLeft(), isTrue);
      await _flush();
      expect(list(), base);
      expect(repo.dayGets, hasLength(1));
    });
  });

  group('lifecycle', () {
    test('list invalidated while a mutation is in flight: no crash, no stale write',
        () async {
      await loadBoth();
      final pending = create();
      await _flush();

      container.invalidate(routinesListProvider);
      await _flush();
      repo.lists.last.complete(Right(base)); // reload answers first
      await _flush();

      repo.creates.single.complete(Right(_created()));
      expect((await pending).isRight(), isTrue);
      await _flush();
      expect(list(), base, reason: 'stale result not applied to the new list');
      expect(repo.lists, hasLength(2), reason: 'no refresh from the stale mutation');
    });

    test('container disposed while a mutation is in flight: completes without throwing',
        () async {
      await loadBoth();
      final pending = notifier().deleteRoutine(3);
      await _flush();
      container.dispose();

      repo.deletes.single.$2.complete(const Right(null));
      expect((await pending).isRight(), isTrue);
      await _flush();
      expect(repo.lists, hasLength(1));
      container = makeContainer(); // for tearDown
    });

    test('no listener (form opened directly): request completes, no exception', () async {
      // Nobody listens to routinesListProvider; only the notifier is read.
      final pending = create();
      await _flush();
      expect(repo.creates, hasLength(1));

      repo.creates.single.complete(Right(_created()));
      final result = await pending;
      expect(result.isRight(), isTrue);
      await _flush();
      for (final c in repo.lists) {
        if (!c.isCompleted) c.complete(Right(base));
      }
      await _flush();
      expect(repo.creates, hasLength(1));
    });
  });
}
