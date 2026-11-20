import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/presentation/today_note_notifier.dart';

import '../fake_note_repository.dart';

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

class _SettableToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 11, 19);

  void set(DateTime day) => state = day;
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNoteRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeNoteRepository();
    container = ProviderContainer(
      overrides: [
        todayProvider.overrideWith(_SettableToday.new),
        noteRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    container.listen(todayNoteProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  test('POSTs the local day once and shows the stored pick', () async {
    await _flush();
    final note = container.read(todayNoteProvider).requireValue;
    // Fake rule: smallest id not yet shown in the cycle → id 1.
    expect(note!.id, 1);
    expect(repo.ofDayDays, [DateTime(2026, 11, 19)]);
    expect(repo.ofDayCalls, 1);
  });

  test('refresh on the same day returns the same stored note (idempotent)', () async {
    await _flush();
    repo.server = [...repo.server, createdNoteFixture().copyWith(id: 0)];
    container.invalidate(todayNoteProvider);
    await _flush();
    expect(repo.ofDayCalls, 2);
    expect(
      container.read(todayNoteProvider).requireValue!.id,
      1,
      reason: 'a new note does not change a stored pick',
    );
  });

  test('deleted pick → the next request shows another note of the same day', () async {
    await _flush();
    repo.server = repo.server.where((n) => n.id != 1).toList();
    container.invalidate(todayNoteProvider);
    await _flush();
    final note = container.read(todayNoteProvider).requireValue!;
    expect(note.id, isNot(1));
    expect(repo.ofDayDays, [DateTime(2026, 11, 19), DateTime(2026, 11, 19)]);
  });

  test('no notes → null value (not an error)', () async {
    repo.server = [];
    container.invalidate(todayNoteProvider);
    await _flush();
    final value = container.read(todayNoteProvider);
    expect(value.hasError, isFalse);
    expect(value.requireValue, isNull);
  });

  test('failure → AsyncError holding the Failure', () async {
    repo.ofDayFailure = _serverError;
    container.invalidate(todayNoteProvider);
    await _flush();
    expect(container.read(todayNoteProvider).error, _serverError);
  });

  test('a new day sends exactly one more POST with the new day', () async {
    await _flush();
    (container.read(todayProvider.notifier) as _SettableToday).set(DateTime(2026, 11, 20));
    await _flush();
    expect(repo.ofDayDays, [DateTime(2026, 11, 19), DateTime(2026, 11, 20)]);
    expect(repo.ofDayCalls, 2);
    // Id 1 was shown on the 19th in this cycle → the 20th gets id 2.
    expect(container.read(todayNoteProvider).requireValue!.id, 2);
  });

  test('a stale answer for the old day never overwrites the new day', () async {
    await _flush();
    final oldDay = Completer<void>();
    repo.ofDayGate = oldDay;
    container.invalidate(todayNoteProvider); // 19th, parked
    await _flush();
    repo.ofDayGate = null;
    (container.read(todayProvider.notifier) as _SettableToday).set(DateTime(2026, 11, 20));
    await _flush();
    expect(container.read(todayNoteProvider).requireValue!.id, 2);
    oldDay.complete(); // the 19th answers last
    await _flush();
    final value = container.read(todayNoteProvider);
    expect(value.isLoading, isFalse);
    expect(value.requireValue!.id, 2, reason: 'the 19th answer must not be written');
    expect(repo.ofDayDays, [
      DateTime(2026, 11, 19),
      DateTime(2026, 11, 19),
      DateTime(2026, 11, 20),
    ]);
  });

  test('day changes while the repository is still loading → only the new day is POSTed', () async {
    // Own repository: the container from setUp already POSTs to `repo`.
    final ownRepo = FakeNoteRepository();
    final repoReady = Completer<FakeNoteRepository>();
    final local = ProviderContainer(
      overrides: [
        todayProvider.overrideWith(_SettableToday.new),
        noteRepositoryProvider.overrideWith((ref) => repoReady.future),
      ],
    );
    addTearDown(local.dispose);
    local.listen(todayNoteProvider, (_, _) {});
    await _flush(); // the 19th build waits for the repository
    (local.read(todayProvider.notifier) as _SettableToday).set(DateTime(2026, 11, 20));
    await _flush(); // the 20th build waits too
    repoReady.complete(ownRepo);
    await _flush();
    expect(ownRepo.ofDayDays, [DateTime(2026, 11, 20)], reason: 'no request for the stale day');
    expect(local.read(todayNoteProvider).requireValue!.id, 1);
  });

  test('disposing while a request is in flight does not throw', () async {
    final local = ProviderContainer(
      overrides: [
        todayProvider.overrideWith(_SettableToday.new),
        noteRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    repo.ofDayGate = Completer<void>();
    final sub = local.listen(todayNoteProvider, (_, _) {});
    await _flush();
    expect(local.read(todayNoteProvider).isLoading, isTrue);
    sub.close();
    local.dispose();
    repo.ofDayGate!.complete();
    await _flush();
    expect(repo.ofDayCalls, greaterThanOrEqualTo(1));
  });

  test('refresh keeps the previous note while reloading', () async {
    await _flush();
    repo.ofDayGate = Completer<void>();
    container.invalidate(todayNoteProvider);
    await _flush();
    final value = container.read(todayNoteProvider);
    expect(value.isLoading, isTrue);
    expect(value.valueOrNull?.id, 1);
    repo.ofDayGate!.complete();
    await _flush();
  });

  test('superseded build never writes (invalidated mid-request)', () async {
    await _flush();
    final gate = Completer<void>();
    repo.ofDayGate = gate;
    container.invalidate(todayNoteProvider);
    await _flush();
    repo.ofDayGate = null;
    repo.server = [];
    container.invalidate(todayNoteProvider);
    await _flush();
    gate.complete();
    await _flush();
    expect(container.read(todayNoteProvider).requireValue, isNull);
  });
}
