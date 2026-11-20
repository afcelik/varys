import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';
import 'package:varys/features/notes/presentation/notes_list_notifier.dart';
import 'package:varys/features/notes/presentation/today_note_notifier.dart';

import '../fake_note_repository.dart';

typedef _NoteResult = Either<Failure, Note>;
typedef _VoidResult = Either<Failure, void>;

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _draft = NoteDraft(title: 'Yeni not', tags: ['iş']);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeNoteRepository repo;
  late ProviderContainer container;
  late List<Note> base;

  NotesListNotifier notifier() => container.read(notesListProvider.notifier);
  NotesOverview overview() => container.read(notesListProvider).requireValue;
  List<int> ids() => overview().notes.map((n) => n.id).toList();
  int countOf(String tag) => overview().tags.firstWhere((t) => t.name == tag).noteCount;

  ProviderContainer makeContainer() => ProviderContainer(
    overrides: [
      todayProvider.overrideWith(_FixedToday.new),
      noteRepositoryProvider.overrideWith((ref) async => repo),
    ],
  );

  /// Parks every create/update/delete on a Completer the test completes.
  final creates = <(NoteDraft, Completer<_NoteResult>)>[];
  final updates = <(int, NoteChanges, Completer<_NoteResult>)>[];
  final deletes = <(int, Completer<_VoidResult>)>[];

  void parkMutations() {
    repo.onCreate = (draft) {
      final c = Completer<_NoteResult>();
      creates.add((draft, c));
      return c.future;
    };
    repo.onUpdate = (id, changes) {
      final c = Completer<_NoteResult>();
      updates.add((id, changes, c));
      return c.future;
    };
    repo.onDelete = (id) {
      final c = Completer<_VoidResult>();
      deletes.add((id, c));
      return c.future;
    };
  }

  Note created({int id = 100, List<String> tags = const ['iş']}) => createdNoteFixture().copyWith(
    id: id,
    title: 'Yeni not',
    body: null,
    isFavorite: false,
    tags: tags,
    updatedAt: DateTime(2026, 11, 20, 9),
  );

  setUp(() async {
    creates.clear();
    updates.clear();
    deletes.clear();
    base = notesFixture();
    repo = FakeNoteRepository(List.of(base));
    container = makeContainer();
    container.listen(notesListProvider, (_, _) {}); // open /notes page
    await _flush();
  });

  tearDown(() => container.dispose());

  /// Also keeps the Home "Günün Notu" card alive.
  Future<void> listenHomeCard() async {
    container.listen(todayNoteProvider, (_, _) {});
    await _flush();
  }

  test('build loads every note (no filters) and the tags in parallel', () {
    expect(ids(), [5, 4, 3, 2, 1]);
    final tagsFixture =
        (jsonDecode(File('test/fixtures/tags_list.json').readAsStringSync()) as List)
            .map((e) => TagCount.fromJson(e as Map<String, dynamic>))
            .toList();
    expect(overview().tags, tagsFixture);
    expect((repo.listCalls, repo.tagsCalls, repo.ofDayCalls), (1, 1, 0));
  });

  test('countTags recounts the real list exactly as the server counts and sorts it', () {
    final tagsFixture =
        (jsonDecode(File('test/fixtures/tags_list.json').readAsStringSync()) as List)
            .map((e) => TagCount.fromJson(e as Map<String, dynamic>))
            .toList();
    expect(countTags(base), tagsFixture);
    expect(countTags(const []), isEmpty);
  });

  test('build failure (notes or tags) -> AsyncError holding the Failure', () async {
    for (final setFailure in [
      (FakeNoteRepository r) => r.listFailure = _serverError,
      (FakeNoteRepository r) => r.tagsFailure = _serverError,
    ]) {
      repo = FakeNoteRepository();
      setFailure(repo);
      final c = makeContainer();
      addTearDown(c.dispose);
      c.listen(notesListProvider, (_, _) {});
      await _flush();
      expect(c.read(notesListProvider).error, _serverError);
    }
  });

  test('search, tag and favorite filter changes send no request', () async {
    await listenHomeCard();
    container.listen(notesFilterProvider, (_, _) {});
    final calls = (repo.listCalls, repo.tagsCalls, repo.ofDayCalls);
    final filter = container.read(notesFilterProvider.notifier);
    List<int> visible() => filterNotes(
      overview().notes,
      query: container.read(notesFilterProvider).query,
      tag: container.read(notesFilterProvider).tag,
      favoritesOnly: container.read(notesFilterProvider).favoritesOnly,
    ).map((n) => n.id).toList();

    filter.setQuery('İŞ'); // 'İş toplantısı' and 'Alışveriş listesi'
    await _flush();
    expect(visible(), [4, 1]);
    filter.setQuery('');
    filter.toggleTag('öğrenim');
    await _flush();
    expect(visible(), [3, 1]);
    filter.toggleFavorites();
    await _flush();
    expect(visible(), [1]);
    filter.toggleTag('öğrenim'); // tapping the selected tag again removes it
    await _flush();
    expect(container.read(notesFilterProvider).tag, isNull);
    filter.clear();
    await _flush();
    expect(visible(), [5, 4, 3, 2, 1]);

    expect((repo.listCalls, repo.tagsCalls, repo.ofDayCalls), calls);
  });

  group('createNote', () {
    setUp(parkMutations);

    test('not optimistic: nothing changes until the server answers', () async {
      final future = notifier().createNote(_draft);
      await _flush();
      expect(ids(), [5, 4, 3, 2, 1]);
      expect(creates.single.$1, _draft);

      creates.single.$2.complete(Right(created()));
      expect(await future, isA<Right<Failure, Note>>());
    });

    test('server result applied at once (top of the list), tag counts recounted', () async {
      repo.listGate = Completer<void>(); // hold the silent refresh
      final future = notifier().createNote(_draft);
      await _flush();
      repo.server = [...base, created()];
      creates.single.$2.complete(Right(created()));
      await future;

      expect(ids(), [100, 5, 4, 3, 2, 1], reason: 'applied before the refresh answers');
      expect(countOf('iş'), 2);
      repo.listGate!.complete();
    });

    test('success: Home card invalidated exactly once, one silent refresh, no loop', () async {
      await listenHomeCard();
      expect((repo.listCalls, repo.tagsCalls, repo.ofDayCalls), (1, 1, 1));

      final future = notifier().createNote(_draft);
      await _flush();
      repo.server = [...base, created()];
      creates.single.$2.complete(Right(created()));
      await future;
      await _flush();

      // One page refresh (notes + tags) and one card reload.
      expect((repo.listCalls, repo.tagsCalls, repo.ofDayCalls), (2, 2, 2));

      // Nothing keeps going on its own: no loop.
      await _flush();
      await _flush();
      expect((repo.listCalls, repo.tagsCalls, repo.ofDayCalls), (2, 2, 2));

      // Reloading the card (its "Tekrar dene") does not reload the page list.
      container.invalidate(todayNoteProvider);
      await _flush();
      expect((repo.listCalls, repo.tagsCalls, repo.ofDayCalls), (2, 2, 3));
    });

    test('silent refresh replaces locally recounted tag counts with the server values', () async {
      final future = notifier().createNote(_draft);
      await _flush();
      // The server counts differently (e.g. notes added elsewhere meanwhile).
      repo.server = [...base, created()];
      repo.tagsOverride = const [
        TagCount(name: 'iş', noteCount: 7),
        TagCount(name: 'öğrenim', noteCount: 4),
      ];
      repo.listGate = Completer<void>();
      creates.single.$2.complete(Right(created()));
      await future;

      expect(countOf('iş'), 2, reason: 'interim local count');
      expect(countOf('öğrenim'), 2);
      expect(overview().tags, hasLength(7));

      repo.listGate!.complete();
      await _flush();
      expect(overview().tags, repo.tagsOverride, reason: 'server value wins');
    });

    test('failure: Left, list unchanged, no refresh, card not invalidated', () async {
      await listenHomeCard();
      final future = notifier().createNote(_draft);
      await _flush();
      creates.single.$2.complete(const Left(_serverError));
      expect(await future, const Left<Failure, Note>(_serverError));
      await _flush();
      expect(ids(), [5, 4, 3, 2, 1]);
      expect((repo.listCalls, repo.tagsCalls, repo.ofDayCalls), (1, 1, 1));
    });
  });

  group('updateNote', () {
    setUp(parkMutations);

    test('sends only the changes; result replaces the row at once', () async {
      repo.listGate = Completer<void>();
      const changes = NoteChanges(body: PlanField.clear(), tags: PlanField.set(<String>[]));
      final future = notifier().updateNote(1, changes);
      await _flush();
      expect(updates.single.$1, 1);
      expect(updates.single.$2.toBody(), {'body': null, 'tags': <String>[]});

      final updated = base.last.copyWith(body: null, tags: const []);
      updates.single.$3.complete(Right(updated));
      await future;
      expect(overview().notes.last, updated);
      expect(overview().tags.any((t) => t.name == 'iş'), isFalse, reason: 'recounted');
      repo.listGate!.complete();
    });

    test('a pending older refresh cannot overwrite a newer result', () async {
      final answers = <Completer<Either<Failure, List<Note>>>>[];
      repo.onList = () {
        final c = Completer<Either<Failure, List<Note>>>();
        answers.add(c);
        return c.future;
      };
      final first = notifier().deleteNote(4);
      await _flush();
      deletes.single.$2.complete(const Right(null));
      await first;
      final renamed = base[0].copyWith(title: 'Sonraki');
      final second = notifier().updateNote(5, const NoteChanges(title: PlanField.set('Sonraki')));
      await _flush();
      updates.single.$3.complete(Right(renamed));
      await second;
      await _flush();
      expect(answers, hasLength(2));

      // The newer refresh answers first, then the stale one.
      answers[1].complete(Right([renamed, base[2], base[3], base[4]]));
      await _flush();
      answers[0].complete(Right(base));
      await _flush();
      expect(ids(), [5, 3, 2, 1]);
      expect(overview().notes.first.title, 'Sonraki');
    });

    test('empty changes: Right(null), no request, nothing invalidated', () async {
      await listenHomeCard();
      final result = await notifier().updateNote(1, const NoteChanges());
      expect(result, const Right<Failure, Note?>(null));
      await _flush();
      expect(updates, isEmpty);
      expect((repo.listCalls, repo.tagsCalls, repo.ofDayCalls), (1, 1, 1));
    });

    test('404 (deleted elsewhere): Left with fixed text; silent refresh drops the row', () async {
      final future = notifier().updateNote(4, const NoteChanges(title: PlanField.set('x')));
      await _flush();
      repo.server = base.where((n) => n.id != 4).toList();
      updates.single.$3.complete(const Left(FakeNoteRepository.notFound));
      final failure = (await future).fold((f) => f, (_) => fail('expected Left'));
      expect(failure.userMessage, 'Kaynak bulunamadı.');
      await _flush();
      expect(ids(), [5, 3, 2, 1]);
      expect(repo.listCalls, 2);
    });

    test('non-404 failure: no re-fetch, old list stays', () async {
      final future = notifier().updateNote(4, const NoteChanges(title: PlanField.set('x')));
      await _flush();
      updates.single.$3.complete(const Left(_serverError));
      expect(await future, const Left<Failure, Note?>(_serverError));
      await _flush();
      expect(ids(), [5, 4, 3, 2, 1]);
      expect(repo.listCalls, 1);
    });

    test(
      'toggleFavorite: PATCH is_favorite only, not optimistic; double tap → one PATCH',
      () async {
        final note = base.firstWhere((n) => n.id == 3);
        final a = notifier().toggleFavorite(note);
        final b = notifier().toggleFavorite(note);
        await _flush();
        expect(updates, hasLength(1));
        expect(updates.single.$2.toBody(), {'is_favorite': true});
        expect(notifier().isUpdating(3), isTrue);
        expect(overview().notes.firstWhere((n) => n.id == 3).isFavorite, isFalse);

        final fav = note.copyWith(isFavorite: true);
        updates.single.$3.complete(Right(fav));
        expect(await a, Right<Failure, Note?>(fav));
        expect(await b, Right<Failure, Note?>(fav));
        expect(notifier().isUpdating(3), isFalse);
        expect(overview().notes.firstWhere((n) => n.id == 3).isFavorite, isTrue);
      },
    );

    test('a different update of the same note while one is in flight is still sent', () async {
      final note = base.firstWhere((n) => n.id == 3);
      unawaited(notifier().toggleFavorite(note));
      unawaited(notifier().updateNote(3, const NoteChanges(title: PlanField.set('Yeni'))));
      await _flush();
      expect(updates.map((u) => u.$2.toBody()), [
        {'is_favorite': true},
        {'title': 'Yeni'},
      ]);
      for (final u in updates) {
        u.$3.complete(Right(note));
      }
      await _flush();
    });
  });

  group('deleteNote', () {
    setUp(parkMutations);

    test('success: row removed at once, counts recounted, card invalidated once', () async {
      await listenHomeCard();
      repo.listGate = Completer<void>();
      final future = notifier().deleteNote(1);
      await _flush();
      repo.server = base.where((n) => n.id != 1).toList();
      deletes.single.$2.complete(const Right(null));
      await future;
      expect(ids(), [5, 4, 3, 2]);
      expect(overview().tags.any((t) => t.name == 'iş'), isFalse);
      expect(countOf('öğrenim'), 1);
      await _flush();
      expect(repo.ofDayCalls, 2);
      repo.listGate!.complete();
      await _flush();
      expect(repo.ofDayCalls, 2);
    });

    test('double tap: one DELETE, both callers get the same result', () async {
      final a = notifier().deleteNote(2);
      final b = notifier().deleteNote(2);
      await _flush();
      expect(deletes, hasLength(1));
      expect(notifier().isDeleting(2), isTrue);
      deletes.single.$2.complete(const Right(null));
      expect(await a, const Right<Failure, void>(null));
      expect(await b, const Right<Failure, void>(null));
      expect(notifier().isDeleting(2), isFalse);
    });

    test('404: Left and a silent refresh', () async {
      final future = notifier().deleteNote(2);
      await _flush();
      repo.server = base.where((n) => n.id != 2).toList();
      deletes.single.$2.complete(const Left(FakeNoteRepository.notFound));
      expect((await future).isLeft(), isTrue);
      await _flush();
      expect(ids(), [5, 4, 3, 1]);
    });

    test('failure: old list stays', () async {
      final future = notifier().deleteNote(2);
      await _flush();
      deletes.single.$2.complete(const Left(_serverError));
      expect((await future).isLeft(), isTrue);
      await _flush();
      expect(ids(), [5, 4, 3, 2, 1]);
    });

    test('silent refresh failure keeps the list (no skeleton, no error)', () async {
      final future = notifier().deleteNote(2);
      await _flush();
      repo.listFailure = _serverError;
      deletes.single.$2.complete(const Right(null));
      await future;
      await _flush();
      final value = container.read(notesListProvider);
      expect(value.hasError, isFalse);
      expect(value.isLoading, isFalse);
      expect(ids(), [5, 4, 3, 1]);
    });
  });

  group('lifecycle', () {
    setUp(parkMutations);

    test('list invalidated while a mutation is in flight: no crash, no stale write', () async {
      final future = notifier().createNote(_draft);
      await _flush();
      container.invalidate(notesListProvider);
      await _flush();
      final callsAfterRebuild = repo.listCalls;
      creates.single.$2.complete(Right(created()));

      expect(await future, isA<Right<Failure, Note>>());
      await _flush();
      expect(ids(), [5, 4, 3, 2, 1]);
      expect(repo.listCalls, callsAfterRebuild);
    });

    test('session-end style invalidation of both providers mid-request: no exception', () async {
      await listenHomeCard();
      final future = notifier().deleteNote(1);
      await _flush();
      container.invalidate(notesListProvider);
      container.invalidate(todayNoteProvider);
      deletes.single.$2.complete(const Right(null));
      expect(await future, const Right<Failure, void>(null));
      await _flush();
      expect(container.read(notesListProvider).hasError, isFalse);
      expect(container.read(todayNoteProvider).hasError, isFalse);
    });

    test('container disposed while a mutation is in flight: completes without throwing', () async {
      final future = notifier().createNote(_draft);
      await _flush();
      container.dispose();
      creates.single.$2.complete(Right(created()));
      expect(await future, isA<Right<Failure, Note>>());
      container = ProviderContainer(); // for tearDown
    });

    test('no listener (form opened directly): request completes, no exception', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      final future = c.read(notesListProvider.notifier).createNote(_draft);
      await _flush();
      creates.single.$2.complete(Right(created()));
      expect(await future, isA<Right<Failure, Note>>());
      await _flush();
    });

    test('mutation during the first load restarts it instead of applying stale data', () async {
      final c = makeContainer();
      addTearDown(c.dispose);
      repo.listGate = Completer<void>();
      c.listen(notesListProvider, (_, _) {});
      await _flush();
      expect(c.read(notesListProvider).isLoading, isTrue);

      final future = c.read(notesListProvider.notifier).createNote(_draft);
      await _flush();
      repo.server = [...base, created()];
      creates.single.$2.complete(Right(created()));
      await future;
      repo.listGate!.complete();
      repo.listGate = null;
      await _flush();
      expect(c.read(notesListProvider).requireValue.notes.map((n) => n.id), [100, 5, 4, 3, 2, 1]);
    });
  });
}
