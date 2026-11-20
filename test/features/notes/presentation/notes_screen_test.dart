import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/presentation/note_edit_screen.dart';
import 'package:varys/features/notes/presentation/notes_list_notifier.dart';
import 'package:varys/features/notes/presentation/notes_screen.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_note_repository.dart';

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

void main() {
  late FakeNoteRepository repo;
  late GoRouter router;
  late List<Note> fixture;

  setUp(() {
    fixture = notesFixture();
    repo = FakeNoteRepository();
  });

  /// /home stub → push /notes (real NotesScreen); the form routes open the
  /// real NoteEditScreen (create, or edit with the Note from extra).
  Future<void> pumpNotes(
    WidgetTester tester, {
    double width = 600,
    double height = 1200,
    double? textScale,
    bool settle = true,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.homePath,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.notesPath, builder: (_, _) => const NotesScreen()),
        GoRoute(path: AppRouter.notesNewPath, builder: (_, _) => const NoteEditScreen()),
        GoRoute(
          path: AppRouter.notesEditPath,
          builder: (_, state) => NoteEditScreen(note: state.extra! as Note),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      textScale: textScale,
      overrides: [noteRepositoryProvider.overrideWith((ref) async => repo)],
    );
    await tester.pumpAndSettle();
    router.push(AppRouter.notesPath);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Finder row(int id) => find.byKey(ValueKey('note-$id'));
  Finder star(int id) => find.byKey(ValueKey('note-favorite-$id'));
  Finder delete(int id) => find.byKey(ValueKey('note-delete-$id'));
  Finder tagChip(String name) => find.byKey(ValueKey('notes-chip-tag-$name'));
  final favoritesChip = find.byKey(const ValueKey('notes-chip-favorites'));
  final search = find.byKey(const ValueKey('notes-search'));
  final searchClear = find.byKey(const ValueKey('notes-search-clear'));

  /// Ids of the drawn note rows, top to bottom.
  List<int> visibleIds(WidgetTester tester) {
    final rowKey = RegExp(r'^note-(\d+)$');
    final rows = find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && rowKey.hasMatch(key.value);
    });
    final ids = [
      for (final e in rows.evaluate())
        (
          int.parse(rowKey.firstMatch((e.widget.key! as ValueKey<String>).value)!.group(1)!),
          tester.getTopLeft(find.byWidget(e.widget)).dy,
        ),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return [for (final (id, _) in ids) id];
  }

  void expectCreateForm(WidgetTester tester) {
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(tester.widget<NoteEditScreen>(find.byType(NoteEditScreen)).note, isNull);
    expect(find.text(NoteEditScreen.createTitle), findsOneWidget);
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(NotesScreen)));

  bool selected(WidgetTester tester, Finder chip) => tester.widget<FilterChip>(chip).selected;

  void expectTapTarget(WidgetTester tester, Finder f, String what) {
    final size = tester.getSize(f);
    expect(size.width, greaterThanOrEqualTo(48), reason: '$what width');
    expect(size.height, greaterThanOrEqualTo(48), reason: '$what height');
  }

  double oneLineHeight(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final oneLine = TextPainter(
      text: TextSpan(text: 'Ağ', style: (paragraph.text as TextSpan).style),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    final height = oneLine.height;
    oneLine.dispose();
    return height;
  }

  /// Lines the text at [finder] really draws (Step 29 method).
  int drawnLines(WidgetTester tester, Finder finder) =>
      (tester.getSize(finder).height / oneLineHeight(tester, finder)).round();

  group('states', () {
    testWidgets('list: every note newest first; title, body preview, tags, favorite star', (
      tester,
    ) async {
      await pumpNotes(tester);
      expect(find.text(NotesScreen.title), findsOneWidget);
      expect(visibleIds(tester), [5, 4, 3, 2, 1]);
      expect(find.byKey(const ValueKey('note-body-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('note-body-4')), findsNothing, reason: 'body null');
      expect(find.descendant(of: row(1), matching: find.text('öğrenim')), findsOneWidget);
      expect(find.descendant(of: star(1), matching: find.byIcon(Icons.star)), findsOneWidget);
      expect(
        find.descendant(of: star(3), matching: find.byIcon(Icons.star_border)),
        findsOneWidget,
      );
      expect(find.byType(ListView), findsWidgets);
      expect((repo.listCalls, repo.tagsCalls), (1, 1));
    });

    testWidgets('loading: skeleton (no list, no search)', (tester) async {
      repo.listGate = Completer<void>();
      addTearDown(() {
        if (!repo.listGate!.isCompleted) repo.listGate!.complete();
      });
      await pumpNotes(tester, settle: false);
      expect(find.byKey(const ValueKey('notes-skeleton')), findsOneWidget);
      expect(search, findsNothing);
      repo.listGate!.complete();
      await tester.pumpAndSettle();
      expect(visibleIds(tester), [5, 4, 3, 2, 1]);
    });

    testWidgets('error: userMessage + "Tekrar dene" reloads the list', (tester) async {
      repo.listFailure = _serverError;
      await pumpNotes(tester);
      expect(find.text(userMessage(_serverError)), findsOneWidget);
      final retry = find.byKey(const ValueKey('notes-retry'));
      expectTapTarget(tester, retry, 'Tekrar dene');

      repo.listFailure = null;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(visibleIds(tester), [5, 4, 3, 2, 1]);
      expect(find.text(userMessage(_serverError)), findsNothing);
    });

    testWidgets('refresh keeps the old list on screen (no skeleton)', (tester) async {
      await pumpNotes(tester);
      repo.listGate = Completer<void>();
      container(tester).invalidate(notesListProvider);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('notes-skeleton')), findsNothing);
      expect(visibleIds(tester), [5, 4, 3, 2, 1]);
      repo.listGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('no notes: "Henüz not yok" + "Not ekle" opens /notes/new', (tester) async {
      repo.server = [];
      await pumpNotes(tester);
      expect(find.text(NotesScreen.emptyText), findsOneWidget);
      final add = find.byKey(const ValueKey('notes-empty-add'));
      expectTapTarget(tester, add, 'Not ekle (empty)');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expectCreateForm(tester);
    });

    testWidgets('AppBar "Not ekle" (48x48, tooltip) opens /notes/new by push', (tester) async {
      await pumpNotes(tester);
      final add = find.byKey(const ValueKey('notes-add'));
      expectTapTarget(tester, add, 'Not ekle');
      expect(find.byTooltip(NotesScreen.addText), findsOneWidget);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expectCreateForm(tester);
      await tester.tap(find.byType(BackArrow));
      await tester.pumpAndSettle();
      expect(find.byType(NotesScreen), findsOneWidget);
    });

    testWidgets('BackArrow leaves /notes back to Home', (tester) async {
      await pumpNotes(tester);
      expect(find.byType(BackArrow), findsOneWidget);
      await tester.tap(find.byType(BackArrow));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('search and filters (client-side)', () {
    testWidgets('search narrows on every letter, Turkish-aware, no request', (tester) async {
      await pumpNotes(tester);
      await tester.enterText(search, 'İ');
      await tester.pump();
      await tester.enterText(search, 'İŞ');
      await tester.pump();
      expect(visibleIds(tester), [4, 1], reason: 'Alışveriş and İş toplantısı');
      await tester.enterText(search, 'bütçe');
      await tester.pump();
      expect(visibleIds(tester), [1], reason: 'matched in the body');
      await tester.enterText(search, 'ISPARTA');
      await tester.pump();
      expect(visibleIds(tester), [3], reason: 'matched in a tag');
      expect((repo.listCalls, repo.tagsCalls), (1, 1));
    });

    testWidgets('clear button (48x48) empties the search and shows every note', (tester) async {
      await pumpNotes(tester);
      expect(searchClear, findsNothing);
      await tester.enterText(search, 'plan');
      await tester.pump();
      expectTapTarget(tester, searchClear, 'Aramayı temizle');
      await tester.tap(searchClear);
      await tester.pump();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(visibleIds(tester), [5, 4, 3, 2, 1]);
    });

    testWidgets('no match: "Eşleşen not yok" + "Süzgeçleri temizle" resets search and chips', (
      tester,
    ) async {
      await pumpNotes(tester);
      await tester.tap(favoritesChip);
      await tester.pump();
      await tester.enterText(search, 'zzz');
      await tester.pump();
      expect(find.text(NotesScreen.noMatchText), findsOneWidget);
      final clear = find.byKey(const ValueKey('notes-clear-filters'));
      expectTapTarget(tester, clear, 'Süzgeçleri temizle');
      await tester.tap(clear);
      await tester.pump();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(selected(tester, favoritesChip), isFalse);
      expect(visibleIds(tester), [5, 4, 3, 2, 1]);
    });

    testWidgets('chips: Favoriler toggles; tag chip with count; selected tag tapped again '
        'is removed; no request', (tester) async {
      await pumpNotes(tester);
      expect(
        find.descendant(of: tagChip('öğrenim'), matching: find.text(' 2')),
        findsOneWidget,
        reason: 'count shown',
      );

      await tester.tap(favoritesChip);
      await tester.pump();
      expect(visibleIds(tester), [1]);
      await tester.tap(favoritesChip);
      await tester.pump();
      expect(visibleIds(tester), [5, 4, 3, 2, 1]);

      await tester.ensureVisible(tagChip('öğrenim'));
      await tester.tap(tagChip('öğrenim'));
      await tester.pump();
      expect(selected(tester, tagChip('öğrenim')), isTrue);
      expect(visibleIds(tester), [3, 1]);

      await tester.tap(tagChip('öğrenim'));
      await tester.pump();
      expect(selected(tester, tagChip('öğrenim')), isFalse);
      expect(visibleIds(tester), [5, 4, 3, 2, 1]);
      expect((repo.listCalls, repo.tagsCalls), (1, 1));
    });

    testWidgets('chip row scrolls sideways; every chip ≥48 high; end chips fully visible', (
      tester,
    ) async {
      await pumpNotes(tester, width: 360, textScale: 1.5);
      expect(tester.takeException(), isNull);
      final chips = [favoritesChip, for (final t in repo.serverTags) tagChip(t.name)];
      for (final chip in chips) {
        await tester.ensureVisible(chip);
        await tester.pump();
        final rect = tester.getRect(chip);
        expect(rect.height, greaterThanOrEqualTo(48), reason: '$chip height');
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$chip left edge visible');
        expect(rect.right, lessThanOrEqualTo(360), reason: '$chip right edge visible');
      }
    });

    testWidgets('search + tag filter survive opening a note and coming back', (tester) async {
      await pumpNotes(tester);
      await tester.enterText(search, 'satır');
      await tester.pump();
      await tester.ensureVisible(tagChip('öğrenim'));
      await tester.tap(tagChip('öğrenim'));
      await tester.pump();
      expect(visibleIds(tester), [3]);

      await tester.tap(find.byKey(const ValueKey('note-title-3')));
      await tester.pumpAndSettle();
      // The real edit form opened for note 3 (no "Sayfa bulunamadı").
      expect(find.byType(NoteEditScreen), findsOneWidget);
      expect(tester.widget<NoteEditScreen>(find.byType(NoteEditScreen)).note!.id, 3);
      expect(find.text(NoteEditScreen.editTitle), findsOneWidget);
      expect(find.text(AppRouter.errorTitle), findsNothing);
      expect(
        tester.widget<TextField>(find.byKey(const ValueKey('note-title-field'))).controller!.text,
        'Öğrenim planı',
      );

      await tester.tap(find.byType(BackArrow));
      await tester.pumpAndSettle();
      expect(find.byType(NotesScreen), findsOneWidget);
      expect(tester.widget<TextField>(search).controller!.text, 'satır');
      expect(selected(tester, tagChip('öğrenim')), isTrue);
      expect(visibleIds(tester), [3]);
      expect(repo.listCalls, 1, reason: 'no reload either');
    });
  });

  group('favorite star', () {
    testWidgets('tap: row disabled while waiting, star updates from the server answer', (
      tester,
    ) async {
      final pending = Completer<Either<Failure, Note>>();
      repo.onUpdate = (id, changes) => pending.future;
      await pumpNotes(tester);
      expectTapTarget(tester, star(3), 'favorite');

      await tester.tap(star(3));
      await tester.pump();
      expect(repo.updateCalls.single.$1, 3);
      expect(repo.updateCalls.single.$2, {'is_favorite': true});
      expect(tester.widget<IconButton>(star(3)).onPressed, isNull, reason: 'row disabled');
      expect(tester.widget<IconButton>(delete(3)).onPressed, isNull);
      expect(
        find.descendant(of: star(3), matching: find.byIcon(Icons.star_border)),
        findsOneWidget,
        reason: 'not optimistic',
      );
      expect(tester.widget<IconButton>(star(1)).onPressed, isNotNull, reason: 'other rows work');

      // The server stores the change and answers with it.
      final favorite = fixture.firstWhere((n) => n.id == 3).copyWith(isFavorite: true);
      repo.server = [for (final n in repo.server) n.id == 3 ? favorite : n];
      pending.complete(Right(favorite));
      await tester.pumpAndSettle();
      expect(find.descendant(of: star(3), matching: find.byIcon(Icons.star)), findsOneWidget);
      expect(tester.widget<IconButton>(star(3)).onPressed, isNotNull);
    });

    testWidgets('failure: star stays as it was, snackbar with userMessage', (tester) async {
      repo.onUpdate = (id, changes) async => const Left(_serverError);
      await pumpNotes(tester);
      await tester.tap(star(3));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: star(3), matching: find.byIcon(Icons.star_border)),
        findsOneWidget,
      );
      expect(find.text(userMessage(_serverError)), findsOneWidget);
      expect(tester.widget<IconButton>(star(3)).onPressed, isNotNull);
    });

    testWidgets('double tap sends one PATCH', (tester) async {
      final pending = Completer<Either<Failure, Note>>();
      repo.onUpdate = (id, changes) => pending.future;
      await pumpNotes(tester);
      await tester.tap(star(3));
      await tester.tap(star(3), warnIfMissed: false);
      await tester.pump();
      expect(repo.updateCalls, hasLength(1));
      pending.complete(Right(fixture.firstWhere((n) => n.id == 3).copyWith(isFavorite: true)));
      await tester.pumpAndSettle();
    });
  });

  group('delete', () {
    testWidgets('asks first ("Bu not silinsin mi?"); Vazgeç keeps the note', (tester) async {
      await pumpNotes(tester);
      expectTapTarget(tester, delete(4), 'delete');
      await tester.tap(delete(4));
      await tester.pumpAndSettle();
      expect(find.text(NotesScreen.deleteQuestion), findsOneWidget);
      await tester.tap(find.text(NotesScreen.deleteCancelText));
      await tester.pumpAndSettle();
      expect(repo.deleteIds, isEmpty);
      expect(visibleIds(tester), [5, 4, 3, 2, 1]);
    });

    testWidgets('Sil: one DELETE, row removed; a double tap still sends one', (tester) async {
      await pumpNotes(tester);
      await tester.tap(delete(4));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('note-delete-confirm'));
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.deleteIds, [4]);
      expect(visibleIds(tester), [5, 3, 2, 1]);
    });

    testWidgets('404 (deleted elsewhere): fixed message and the list is refreshed', (tester) async {
      await pumpNotes(tester);
      repo.server = repo.server.where((n) => n.id != 2).toList(); // gone on the server
      await tester.tap(delete(2));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('note-delete-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Kaynak bulunamadı.'), findsOneWidget);
      expect(visibleIds(tester), [5, 4, 3, 1]);
    });
  });

  group('rows at 360px x1.5', () {
    testWidgets('title and body preview drawn in at most 2 lines', (tester) async {
      await pumpNotes(tester, width: 360, textScale: 1.5);
      expect(tester.takeException(), isNull);
      final title2 = find.byKey(const ValueKey('note-title-2')); // 255, no spaces
      final body3 = find.byKey(const ValueKey('note-body-3')); // 60 lines
      await tester.ensureVisible(title2);
      await tester.pump();
      expect(drawnLines(tester, title2), NotesScreen.titleMaxLines);
      await tester.ensureVisible(body3);
      await tester.pump();
      expect(drawnLines(tester, body3), NotesScreen.bodyMaxLines);
      for (final id in [1, 3]) {
        final t = find.byKey(ValueKey('note-title-$id'));
        await tester.ensureVisible(t);
        await tester.pump();
        expect(drawnLines(tester, t), lessThanOrEqualTo(NotesScreen.titleMaxLines));
      }
    });

    testWidgets('255-character unbroken title with many tags: 3 chips and "+N"', (tester) async {
      final long = fixture.firstWhere((n) => n.id == 2);
      repo.server = [
        long.copyWith(tags: [for (var i = 0; i < 7; i++) 'çok uzun etiket adı numara $i']),
      ];
      await pumpNotes(tester, width: 360, textScale: 1.5);
      expect(tester.takeException(), isNull);
      final inRow = find.descendant(of: row(2), matching: find.text('+4'));
      expect(inRow, findsOneWidget);
      expect(
        find.descendant(of: row(2), matching: find.text('çok uzun etiket adı numara 3')),
        findsNothing,
      );
      expect(drawnLines(tester, find.byKey(const ValueKey('note-title-2'))), 2);
      expectTapTarget(tester, star(2), 'favorite');
      expectTapTarget(tester, delete(2), 'delete');
    });
  });
}
