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

  test('asks the server for the note of the local day (same pick as the server)', () async {
    await _flush();
    final note = container.read(todayNoteProvider).requireValue;
    // 2026-11-19 ordinal 739939; 739939 % 5 = 4 → the 5th note by id.
    expect(note!.id, 5);
    expect(repo.randomDays, [DateTime(2026, 11, 19)]);
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
    repo.randomFailure = _serverError;
    container.invalidate(todayNoteProvider);
    await _flush();
    expect(container.read(todayNoteProvider).error, _serverError);
  });

  test('a new day loads that day\'s note', () async {
    await _flush();
    (container.read(todayProvider.notifier) as _SettableToday).set(DateTime(2026, 11, 20));
    await _flush();
    expect(repo.randomDays, [DateTime(2026, 11, 19), DateTime(2026, 11, 20)]);
    // 739940 % 5 = 0 → the first note by id.
    expect(container.read(todayNoteProvider).requireValue!.id, 1);
  });

  test('refresh keeps the previous note while reloading', () async {
    await _flush();
    repo.randomGate = Completer<void>();
    container.invalidate(todayNoteProvider);
    await _flush();
    final value = container.read(todayNoteProvider);
    expect(value.isLoading, isTrue);
    expect(value.valueOrNull?.id, 5);
    repo.randomGate!.complete();
    await _flush();
  });

  test('superseded build never writes (invalidated mid-request)', () async {
    await _flush();
    final gate = Completer<void>();
    repo.randomGate = gate;
    container.invalidate(todayNoteProvider);
    await _flush();
    repo.randomGate = null;
    repo.server = [];
    container.invalidate(todayNoteProvider);
    await _flush();
    gate.complete();
    await _flush();
    expect(container.read(todayNoteProvider).requireValue, isNull);
  });
}
