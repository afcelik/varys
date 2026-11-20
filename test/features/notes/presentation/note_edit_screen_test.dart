import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/domain/markdown_format.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';
import 'package:varys/features/notes/presentation/note_edit_screen.dart';
import 'package:varys/features/notes/presentation/notes_screen.dart';
import 'package:varys/features/notes/presentation/widgets/markdown_toolbar.dart';
import 'package:varys/features/notes/presentation/widgets/note_markdown.dart';
import 'package:varys/features/notes/presentation/widgets/tag_input.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_note_repository.dart';

typedef _NoteResult = Either<Failure, Note>;

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

  final titleField = find.byKey(const ValueKey('note-title-field'));
  final bodyField = find.byKey(const ValueKey('note-body-field'));
  final tagField = find.byKey(const ValueKey('note-tag-input'));
  final saveButton = find.byKey(const ValueKey('note-save'));
  final favoriteSwitch = find.byKey(const ValueKey('note-favorite-switch'));
  final suggestionsBox = find.byKey(const ValueKey('note-tag-suggestions'));
  Finder removeChip(String tag) => find.byKey(ValueKey('note-tag-remove-$tag'));
  Finder suggestion(String name) => find.byKey(ValueKey('note-tag-suggestion-$name'));

  Future<void> pumpRouter(WidgetTester tester, {Size size = const Size(600, 1400)}) async {
    tester.view.physicalSize = size;
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
      overrides: [noteRepositoryProvider.overrideWith((ref) async => repo)],
    );
    await tester.pumpAndSettle();
  }

  /// /home → /notes → /notes/new (the list page stays below).
  Future<void> openCreate(WidgetTester tester, {Size size = const Size(600, 1400)}) async {
    await pumpRouter(tester, size: size);
    router.push(AppRouter.notesPath);
    await tester.pumpAndSettle();
    router.push(AppRouter.notesNewPath);
    await tester.pumpAndSettle();
    expect(find.text(NoteEditScreen.createTitle), findsOneWidget);
  }

  /// /home → /notes → /notes/edit with [note].
  Future<void> openEdit(WidgetTester tester, Note note) async {
    await pumpRouter(tester);
    router.push(AppRouter.notesPath);
    await tester.pumpAndSettle();
    router.push(AppRouter.notesEditPath, extra: note);
    await tester.pumpAndSettle();
    expect(find.text(NoteEditScreen.editTitle), findsOneWidget);
  }

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton).onPressed != null;

  String text(WidgetTester tester, Finder field) =>
      tester.widget<TextField>(field).controller!.text;

  /// Tags shown as chips in the form, in order.
  List<String> chips(WidgetTester tester) {
    const prefix = 'note-tag-chip-';
    final found = find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith(prefix);
    });
    return [
      for (final e in found.evaluate())
        (e.widget.key! as ValueKey<String>).value.substring(prefix.length),
    ];
  }

  Future<void> typeTag(WidgetTester tester, String value, {bool enter = false}) async {
    await tester.enterText(tagField, value);
    if (enter) await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
  }

  void expectTapTarget(WidgetTester tester, Finder f, String what) {
    final size = tester.getSize(f);
    expect(size.width, greaterThanOrEqualTo(48), reason: '$what width');
    expect(size.height, greaterThanOrEqualTo(48), reason: '$what height');
  }

  group('validation and Kaydet', () {
    testWidgets('empty or blank title: Kaydet disabled, "Başlık gerekli"', (tester) async {
      await openCreate(tester);
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(titleField, '   ');
      await tester.pumpAndSettle();
      expect(find.text(noteTitleRequiredMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(titleField, 'Not');
      await tester.pumpAndSettle();
      expect(find.text(noteTitleRequiredMessage), findsNothing);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('title 255 code points ok, 256 rejected', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, '🎯' * 255);
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await tester.enterText(titleField, 'a' * 256);
      await tester.pumpAndSettle();
      expect(find.text(noteTitleTooLongMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('body counter counts code points; over 20000 is rejected', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'Not');
      await tester.enterText(bodyField, '🎯🎯 ab');
      await tester.pumpAndSettle();
      expect(find.text('5 / 20000'), findsOneWidget);
      await tester.enterText(bodyField, 'a' * 20001);
      await tester.pumpAndSettle();
      expect(find.text(noteBodyTooLongMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(bodyField, 'a' * 20000);
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('create: POST body with trimmed title, null blank body, tags, favorite; then '
        'the page closes and the new note is on the list', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, '  Yeni fikir  ');
      await tester.enterText(bodyField, '   ');
      await typeTag(tester, 'İş', enter: true);
      await tester.ensureVisible(favoriteSwitch);
      await tester.tap(favoriteSwitch);
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(repo.createBodies.single, {
        'title': 'Yeni fikir',
        'body': null,
        'tags': ['iş'],
        'is_favorite': true,
      });
      expect(find.byType(NoteEditScreen), findsNothing);
      expect(find.byType(NotesScreen), findsOneWidget);
      expect(find.text('Yeni fikir'), findsOneWidget);
    });

    testWidgets('server error: form stays open with the values, Turkish snackbar', (tester) async {
      repo.onCreate = (_) async => const Left(_serverError);
      await openCreate(tester);
      await tester.enterText(titleField, 'Kalsın');
      await tester.enterText(bodyField, 'Gövde');
      await typeTag(tester, 'ev', enter: true);
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditScreen), findsOneWidget);
      expect(find.text(userMessage(_serverError)), findsOneWidget);
      expect(text(tester, titleField), 'Kalsın');
      expect(text(tester, bodyField), 'Gövde');
      expect(chips(tester), ['ev']);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('while saving: Kaydet disabled, a double tap sends one POST', (tester) async {
      final pending = Completer<_NoteResult>();
      repo.onCreate = (_) => pending.future;
      await openCreate(tester);
      await tester.enterText(titleField, 'Bir kez');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      expect(repo.createBodies, hasLength(1));
      expect(saveEnabled(tester), isFalse);
      pending.complete(Right(createdNoteFixture().copyWith(id: 100, title: 'Bir kez')));
      await tester.pumpAndSettle();
    });
  });

  group('tags', () {
    testWidgets("Enter adds; uppercase 'İş' and decomposed İ both show 'iş'", (tester) async {
      await openCreate(tester);
      await typeTag(tester, 'İş', enter: true);
      expect(chips(tester), ['iş']);
      expect(text(tester, tagField), isEmpty);
      await tester.tap(removeChip('iş'));
      await tester.pumpAndSettle();

      const decomposed = 'I\u0307ş';
      expect(decomposed.runes.toList(), [0x49, 0x307, 0x15F]);
      await typeTag(tester, decomposed, enter: true);
      expect(chips(tester), ['iş']);
      expect(chips(tester).single.runes.toList(), [0x69, 0x15F]);
    });

    testWidgets('a typed comma adds the tag; the field keeps typing', (tester) async {
      await openCreate(tester);
      await typeTag(tester, 'Öğrenim');
      expect(chips(tester), isEmpty, reason: 'not added before comma or Enter');
      await typeTag(tester, 'Öğrenim,');
      expect(chips(tester), ['öğrenim']);
      expect(text(tester, tagField), isEmpty);
    });

    testWidgets("pasted 'iş, öğrenim, proje' → three tags; duplicates merged", (tester) async {
      await openCreate(tester);
      await typeTag(tester, 'iş, öğrenim, proje');
      expect(chips(tester), ['iş', 'öğrenim', 'proje']);
      expect(text(tester, tagField), isEmpty);
      await typeTag(tester, 'İŞ, ev, ÖĞRENİM, ev');
      expect(chips(tester), ['iş', 'öğrenim', 'proje', 'ev']);
      expect(find.text(tagEmptyMessage), findsNothing);
    });

    testWidgets('parts over 40 characters or empty are skipped with a message', (tester) async {
      await openCreate(tester);
      await typeTag(tester, 'iş, ${'a' * 41}, ev');
      expect(chips(tester), ['iş', 'ev']);
      expect(find.text(tagTooLongMessage), findsOneWidget);
      await typeTag(tester, 'kitap,,proje');
      expect(chips(tester), ['iş', 'ev', 'kitap', 'proje']);
      expect(find.text(tagEmptyMessage), findsOneWidget);
    });

    testWidgets('20 tags max: the rest is not added, message shown, field disabled', (
      tester,
    ) async {
      await openCreate(tester);
      await typeTag(tester, [for (var i = 0; i < 22; i++) 't$i'].join(', '));
      expect(chips(tester), hasLength(20));
      expect(chips(tester).last, 't19');
      expect(find.text(tagLimitMessage), findsOneWidget);
      expect(tester.widget<TextField>(tagField).enabled, isFalse);
      expect(suggestionsBox, findsNothing, reason: 'no suggestions when full');

      await tester.ensureVisible(removeChip('t3'));
      await tester.tap(removeChip('t3'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(tagField).enabled, isTrue);
    });

    testWidgets('chip × is 48x48 and removes the tag', (tester) async {
      await openCreate(tester);
      await typeTag(tester, 'iş, ev, kitap');
      expectTapTarget(tester, removeChip('ev'), 'remove chip');
      expect(tester.widget<IconButton>(removeChip('ev')).tooltip, TagInput.removeTooltip);
      await tester.tap(removeChip('ev'));
      await tester.pumpAndSettle();
      expect(chips(tester), ['iş', 'kitap']);
    });

    testWidgets('suggestions from /tags: only tags not added yet; a tap adds; typing filters', (
      tester,
    ) async {
      await openCreate(tester);
      expect(suggestion('öğrenim'), findsOneWidget);
      expect(suggestion('kitap'), findsOneWidget);
      expectTapTarget(tester, suggestion('kitap'), 'suggestion');

      await tester.tap(suggestion('kitap'));
      await tester.pumpAndSettle();
      expect(chips(tester), ['kitap']);
      expect(suggestion('kitap'), findsNothing, reason: 'already added');

      await tester.enterText(tagField, 'Öğ');
      await tester.pumpAndSettle();
      expect(suggestion('öğrenim'), findsOneWidget);
      expect(suggestion('iş'), findsNothing);
      expect(repo.tagsCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('/tags fails: no suggestions, no error shown, the form still saves', (
      tester,
    ) async {
      repo.tagsFailure = _serverError;
      await pumpRouter(tester);
      router.go(AppRouter.notesNewPath); // opened directly: no list page below
      await tester.pumpAndSettle();
      expect(suggestionsBox, findsNothing);
      expect(find.text(userMessage(_serverError)), findsNothing);

      await tester.enterText(titleField, 'Öneri yok');
      await typeTag(tester, 'ev', enter: true);
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.createBodies.single['tags'], ['ev']);
      expect(tester.takeException(), isNull);
    });
  });

  group('edit', () {
    testWidgets('fields come filled from the Note', (tester) async {
      final note = fixture.firstWhere((n) => n.id == 1);
      await openEdit(tester, note);
      expect(text(tester, titleField), note.title);
      expect(text(tester, bodyField), note.body);
      expect(chips(tester), ['iş', 'öğrenim']);
      expect(tester.widget<SwitchListTile>(favoriteSwitch).value, isTrue);
    });

    testWidgets('nothing changed: Kaydet disabled, no request', (tester) async {
      await openEdit(tester, fixture.firstWhere((n) => n.id == 1));
      expect(saveEnabled(tester), isFalse);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.updateCalls, isEmpty);
    });

    testWidgets('only the body cleared → PATCH {body: null}', (tester) async {
      await openEdit(tester, fixture.firstWhere((n) => n.id == 1));
      await tester.enterText(bodyField, '');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.updateCalls.single.$1, 1);
      expect(repo.updateCalls.single.$2, {'body': null});
      expect(find.byType(NoteEditScreen), findsNothing);
    });

    testWidgets('tag order changed (remove and re-add): not a change, Kaydet stays disabled', (
      tester,
    ) async {
      await openEdit(tester, fixture.firstWhere((n) => n.id == 1));
      await tester.tap(removeChip('iş'));
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue, reason: 'a tag removed is a change');
      await typeTag(tester, 'İş', enter: true);
      expect(chips(tester), ['öğrenim', 'iş']);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('all tags removed → PATCH {tags: []}', (tester) async {
      await openEdit(tester, fixture.firstWhere((n) => n.id == 1));
      await tester.tap(removeChip('iş'));
      await tester.pumpAndSettle();
      await tester.tap(removeChip('öğrenim'));
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.updateCalls.single.$2, {'tags': <String>[]});
    });

    testWidgets('404 (deleted elsewhere): message, form open, list refreshed silently', (
      tester,
    ) async {
      final note = fixture.firstWhere((n) => n.id == 4);
      await openEdit(tester, note);
      final listCalls = repo.listCalls;
      repo.server = repo.server.where((n) => n.id != 4).toList();
      await tester.enterText(titleField, 'Yeni ad');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.text('Kaynak bulunamadı.'), findsOneWidget);
      expect(find.byType(NoteEditScreen), findsOneWidget);
      expect(text(tester, titleField), 'Yeni ad');
      expect(repo.listCalls, listCalls + 1);
    });
  });

  group('keyboard open (narrow screen)', () {
    testWidgets('360px x1.5 with a 300px keyboard: Kaydet above the keyboard and tappable; '
        'the error snackbar does not cover it', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      repo.onCreate = (_) async => const Left(_serverError);
      await openCreate(tester, size: const Size(360, 800));
      await typeTag(tester, 'iş, öğrenim, proje, kitap, ev');
      await tester.enterText(bodyField, 'satır\n' * 40);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(titleField, 'P');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(saveButton);
      expect(rect.bottom, lessThanOrEqualTo(800 - 300), reason: 'above the keyboard');
      expect(rect.top, greaterThanOrEqualTo(0));
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(repo.createBodies, hasLength(1));
      final snackRect = tester.getRect(find.byType(SnackBar));
      final saveRect = tester.getRect(saveButton);
      expect(snackRect.bottom, lessThanOrEqualTo(saveRect.top), reason: 'snackbar above Kaydet');
      expect(saveEnabled(tester), isTrue);

      // Kaydet is still hit-testable while the snackbar shows.
      repo.onCreate = null;
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(repo.createBodies, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  });

  group('page closed while saving (mounted checks)', () {
    testWidgets('list page below: close during the request, no exception, list updated', (
      tester,
    ) async {
      final pending = Completer<_NoteResult>();
      repo.onCreate = (_) => pending.future;
      await openCreate(tester);
      await tester.enterText(titleField, 'Kapanınca');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(NotesScreen), findsOneWidget);

      final created = createdNoteFixture().copyWith(id: 100, title: 'Kapanınca', tags: []);
      repo.server = [...repo.server, created];
      pending.complete(Right(created));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Kapanınca'), findsOneWidget);
    });

    testWidgets('/notes/new opened directly: close during the request, no exception', (
      tester,
    ) async {
      final pending = Completer<_NoteResult>();
      repo.onCreate = (_) => pending.future;
      await pumpRouter(tester);
      router.go(AppRouter.notesNewPath);
      await tester.pumpAndSettle();
      await tester.enterText(titleField, 'Doğrudan');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back)); // nothing to pop: go /home
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);

      pending.complete(Right(createdNoteFixture().copyWith(id: 100, title: 'Doğrudan')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(repo.createBodies.single['title'], 'Doğrudan');
    });
  });

  group('Markdown toolbar and preview', () {
    // Notation: «…» is the body selection, ‸ a cursor (as in
    // markdown_format_test.dart).
    final toolbar = find.byKey(const ValueKey('note-format-toolbar'));
    final preview = find.byKey(const ValueKey('note-body-preview'));
    final writeTab = find.text(NoteEditScreen.writeTab);
    final previewTab = find.text(NoteEditScreen.previewTab);
    Finder formatButton(MarkdownFormat f) => find.byKey(MarkdownToolbar.buttonKey(f));

    TextEditingController body(WidgetTester tester) =>
        tester.widget<TextField>(bodyField).controller!;

    bool bodyFocused(WidgetTester tester) =>
        tester.widget<TextField>(bodyField).focusNode!.hasFocus;

    String shown(WidgetTester tester) {
      final c = body(tester);
      final s = c.selection;
      if (s.isCollapsed) return '${c.text.substring(0, s.start)}‸${c.text.substring(s.start)}';
      return '${c.text.substring(0, s.start)}«${c.text.substring(s.start, s.end)}»'
          '${c.text.substring(s.end)}';
    }

    /// Types the body (which focuses it) and sets the marked selection.
    Future<void> setBody(WidgetTester tester, String marked) async {
      final TextSelection selection;
      final String text;
      final cursor = marked.indexOf('‸');
      if (cursor != -1) {
        text = marked.replaceFirst('‸', '');
        selection = TextSelection.collapsed(offset: cursor);
      } else {
        final start = marked.indexOf('«');
        final end = marked.indexOf('»') - 1;
        text = marked.replaceFirst('«', '').replaceFirst('»', '');
        selection = TextSelection(baseOffset: start, extentOffset: end);
      }
      await tester.enterText(bodyField, text);
      body(tester).selection = selection;
      await tester.pump();
      expect(bodyFocused(tester), isTrue, reason: 'body focused before the tap');
    }

    Future<void> tapFormat(WidgetTester tester, MarkdownFormat f) async {
      await tester.ensureVisible(formatButton(f));
      await tester.pump();
      await tester.tap(formatButton(f));
      await tester.pump();
    }

    const applied = {
      MarkdownFormat.h1: '# «kelime»',
      MarkdownFormat.h2: '## «kelime»',
      MarkdownFormat.h3: '### «kelime»',
      MarkdownFormat.bold: '**«kelime»**',
      MarkdownFormat.italic: '*«kelime»*',
      MarkdownFormat.strike: '~~«kelime»~~',
      MarkdownFormat.inlineCode: '`«kelime»`',
      MarkdownFormat.codeBlock: '```\n«kelime»\n```',
      MarkdownFormat.bulletList: '- «kelime»',
      MarkdownFormat.numberedList: '1. «kelime»',
      MarkdownFormat.taskList: '- [ ] «kelime»',
      MarkdownFormat.quote: '> «kelime»',
      MarkdownFormat.rule: 'kelime\n\n---\n\n‸',
      MarkdownFormat.link: '[kelime](«https://»)',
      MarkdownFormat.table: 'kelime\n\n| «Başlık» | Başlık |\n| --- | --- |\n|  |  |\n\n',
    };

    test('the expectation table covers every format', () {
      expect(applied.keys.toSet(), MarkdownFormat.values.toSet());
    });

    for (final f in MarkdownFormat.values) {
      testWidgets('${f.name}: changes the body at the selection, keeps focus, enables Kaydet', (
        tester,
      ) async {
        await openCreate(tester);
        await tester.enterText(titleField, 'Not');
        await setBody(tester, '«kelime»');
        await tapFormat(tester, f);
        expect(shown(tester), applied[f]);
        expect(bodyFocused(tester), isTrue, reason: 'focus kept (keyboard stays open)');
        expect(tester.testTextInput.isVisible, isTrue, reason: 'keyboard stays open');
        expect(saveEnabled(tester), isTrue);
        expect(find.text(NoteEditScreen.bodyCounter(body(tester).text)), findsOneWidget);
      });
    }

    testWidgets(
      'desktop mouse click on a format button keeps the body focused',
      (tester) async {
        await openCreate(tester);
        await tester.tap(bodyField, kind: PointerDeviceKind.mouse);
        await tester.enterText(bodyField, 'kelime');
        body(tester).selection = const TextSelection(baseOffset: 0, extentOffset: 6);
        await tester.pump();
        for (final f in [MarkdownFormat.bold, MarkdownFormat.h1, MarkdownFormat.table]) {
          await tester.ensureVisible(formatButton(f));
          await tester.pump();
          await tester.tap(formatButton(f), kind: PointerDeviceKind.mouse);
          await tester.pump();
          expect(bodyFocused(tester), isTrue, reason: '${f.name}: a click outside the field');
        }
        expect(body(tester).text, startsWith('# **kelime**'));
      },
      variant: const TargetPlatformVariant({TargetPlatform.macOS, TargetPlatform.linux}),
    );

    for (final f in [
      MarkdownFormat.h1,
      MarkdownFormat.h2,
      MarkdownFormat.h3,
      MarkdownFormat.bold,
      MarkdownFormat.italic,
      MarkdownFormat.strike,
      MarkdownFormat.inlineCode,
      MarkdownFormat.codeBlock,
      MarkdownFormat.bulletList,
      MarkdownFormat.numberedList,
      MarkdownFormat.taskList,
      MarkdownFormat.quote,
    ]) {
      testWidgets('${f.name}: a second tap removes it again', (tester) async {
        await openCreate(tester);
        await setBody(tester, '«kelime»');
        await tapFormat(tester, f);
        await tapFormat(tester, f);
        expect(shown(tester), '«kelime»');
        expect(bodyFocused(tester), isTrue);
      });
    }

    testWidgets('a cursor (no selection) puts the marks around it', (tester) async {
      await openCreate(tester);
      await setBody(tester, 'ab‸cd');
      await tapFormat(tester, MarkdownFormat.bold);
      expect(shown(tester), 'ab**‸**cd');
    });

    testWidgets('a multi-line selection numbers every line', (tester) async {
      await openCreate(tester);
      await setBody(tester, '«süt\nekmek\nyumurta»');
      await tapFormat(tester, MarkdownFormat.numberedList);
      expect(shown(tester), '1. «süt\n2. ekmek\n3. yumurta»');
    });

    testWidgets('edit: a format is a change; Kaydet sends the new body', (tester) async {
      final note = fixture.firstWhere((n) => n.id == 1).copyWith(body: 'eski');
      repo = FakeNoteRepository([note]);
      await openEdit(tester, note);
      expect(saveEnabled(tester), isFalse);
      await tester.tap(bodyField);
      await tester.pump();
      body(tester).selection = const TextSelection(baseOffset: 0, extentOffset: 4);
      await tester.pump();
      await tapFormat(tester, MarkdownFormat.bold);
      expect(saveEnabled(tester), isTrue);
      await tapSave(tester);
      await tester.pumpAndSettle();
      final (id, patch) = repo.updateCalls.single;
      expect(id, 1);
      expect(patch, {'body': '**eski**'});
    });

    testWidgets('a result over 20000 code points: message, text and selection unchanged', (
      tester,
    ) async {
      await openCreate(tester);
      final full = 'a' * noteBodyMaxLength;
      await setBody(tester, '$full‸');
      await tapFormat(tester, MarkdownFormat.bold);
      expect(find.text(markdownFormatLimitMessage), findsOneWidget);
      expect(body(tester).text, full);
      expect(body(tester).selection, TextSelection.collapsed(offset: full.length));
      expect(bodyFocused(tester), isTrue);
    });

    testWidgets('Yaz → Önizle → Yaz keeps text and selection; a format then applies there', (
      tester,
    ) async {
      await openCreate(tester);
      await setBody(tester, 'bir «iki» üç');
      final before = body(tester).selection;
      expect(find.byKey(const ValueKey('note-body-tabs')), findsOneWidget);

      await tester.tap(previewTab);
      await tester.pumpAndSettle();
      expect(toolbar, findsNothing, reason: 'toolbar hidden in Önizle');
      expect(bodyField, findsNothing);
      expect(
        find.descendant(of: preview, matching: find.text('bir iki üç', findRichText: true)),
        findsOneWidget,
      );

      await tester.tap(writeTab);
      await tester.pumpAndSettle();
      expect(toolbar, findsOneWidget);
      expect(body(tester).text, 'bir iki üç');
      expect(body(tester).selection, before);
      expect(bodyFocused(tester), isTrue);

      await tapFormat(tester, MarkdownFormat.bold);
      expect(shown(tester), 'bir **«iki»** üç');
    });

    testWidgets('Önizle renders Markdown: "# Merhaba" shows Merhaba without #', (tester) async {
      await openCreate(tester);
      await setBody(tester, '# Merhaba\n\n- madde‸');
      await tester.tap(previewTab);
      await tester.pumpAndSettle();
      expect(find.descendant(of: preview, matching: find.byType(NoteMarkdown)), findsOneWidget);
      expect(find.text('Merhaba', findRichText: true), findsOneWidget);
      expect(find.textContaining('#', findRichText: true), findsNothing);
      expect(find.text(NoteEditScreen.previewEmpty), findsNothing);
    });

    testWidgets('Önizle with an empty or blank body: "Önizlenecek bir şey yok"', (tester) async {
      await openCreate(tester);
      await tester.tap(previewTab);
      await tester.pumpAndSettle();
      expect(find.text(NoteEditScreen.previewEmpty), findsOneWidget);
      expect(find.byType(NoteMarkdown), findsNothing);

      await tester.tap(writeTab);
      await tester.pumpAndSettle();
      await setBody(tester, '   \n  ‸');
      await tester.tap(previewTab);
      await tester.pumpAndSettle();
      expect(find.text(NoteEditScreen.previewEmpty), findsOneWidget);
    });

    testWidgets('360px x1.5: 15 buttons, each 48x48 with its Turkish tooltip, both ends reachable '
        'and fully visible by scrolling; the tabs are 48 high', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openCreate(tester, size: const Size(360, 800));
      expect(
        find.descendant(of: toolbar, matching: find.byType(IconButton)),
        findsNWidgets(MarkdownFormat.values.length),
      );
      const expectedTooltips = [
        'Başlık 1',
        'Başlık 2',
        'Başlık 3',
        'Kalın',
        'İtalik',
        'Üstü çizili',
        'Satır içi kod',
        'Kod bloğu',
        'Madde işaretli liste',
        'Numaralı liste',
        'Yapılacaklar listesi',
        'Alıntı',
        'Yatay çizgi',
        'Bağlantı',
        'Tablo',
      ];
      for (final (i, f) in MarkdownFormat.values.indexed) {
        final b = formatButton(f);
        await tester.ensureVisible(b);
        await tester.pump();
        expectTapTarget(tester, b, f.name);
        expect(tester.widget<IconButton>(b).tooltip, expectedTooltips[i], reason: f.name);
        final r = tester.getRect(b);
        expect(r.left, greaterThanOrEqualTo(-0.5), reason: '${f.name} left');
        expect(r.right, lessThanOrEqualTo(360.5), reason: '${f.name} right');
        expect(b.hitTestable(), findsOneWidget, reason: '${f.name} tappable');
      }
      // The row really scrolls: the last button is past the first window.
      final position = tester
          .state<ScrollableState>(find.descendant(of: toolbar, matching: find.byType(Scrollable)))
          .position;
      expect(position.maxScrollExtent, greaterThan(0));
      expect(position.pixels, position.maxScrollExtent);

      for (final tab in [writeTab, previewTab]) {
        final segment = find.ancestor(of: tab, matching: find.byType(TextButton));
        await tester.ensureVisible(segment);
        await tester.pump();
        expectTapTarget(tester, segment, 'tab segment');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('while saving the toolbar is disabled', (tester) async {
      final pending = Completer<_NoteResult>();
      repo.onCreate = (_) => pending.future;
      await openCreate(tester);
      await tester.enterText(titleField, 'Not');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();
      for (final f in MarkdownFormat.values) {
        expect(tester.widget<IconButton>(formatButton(f)).onPressed, isNull, reason: f.name);
      }
      pending.complete(Right(createdNoteFixture().copyWith(id: 100, title: 'Not')));
      await tester.pumpAndSettle();
    });
  });
}
