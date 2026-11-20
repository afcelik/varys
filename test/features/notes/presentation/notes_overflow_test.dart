// Overflow matrix for the notes pages: every width x text scale 1.0 / 1.5.
// /notes: filled (unbroken 255-character title, 60-line body, many long
// tags), no notes, no match for the search, loading, error, keyboard open
// while searching. /notes/edit: filled (255 title, long body, 20 tags) with
// and without the keyboard. /notes/new: suggestions open, error snackbar
// open. Checks: no exception, drawn line counts (maxLines), 48x48 tap
// targets, Kaydet visible and hit-testable. Loading never uses
// pumpAndSettle.

import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:varys/features/notes/presentation/widgets/tag_input.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_note_repository.dart';

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _textScales = [1.0, 1.5];
const _height = 800.0;
const _keyboard = 300.0;

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

/// 20 tags of 30-40 characters (the longest a tag may be is 40).
final _twentyTags = [
  for (var i = 0; i < maxTagsPerNote; i++) 'çok uzun etiket adı numara $i ${'ş' * (i % 10)}',
];

/// Every Markdown block (headings, a 255 character line without spaces, a
/// very wide table, a long code line, …), filled up to exactly 20000
/// characters.
final String _markdownBody = () {
  final head = [
    '# Birinci düzey başlık ${'uzun ' * 10}',
    '## İkinci düzey',
    '### Üçüncü düzey',
    'ş' * 255,
    '**kalın** *eğik* ~~çizik~~ `kod` [site](https://ornek.com)',
    '- madde\n  - iç madde',
    '1. bir\n2. iki',
    '- [ ] yap\n- [x] bitti',
    '> alıntı ${'söz ' * 30}',
    '---',
    [
      '| ${List.generate(8, (i) => 'Sütun başlığı $i').join(' | ')} |',
      '| ${List.filled(8, '---').join(' | ')} |',
      '| ${List.generate(8, (i) => 'uzun hücre içeriği $i').join(' | ')} |',
    ].join('\n'),
    '```\n${'kod' * 120}\n```',
    '![kedi](https://ornek.com/kedi.png)',
  ].join('\n\n');
  const filler = '\n\nöğrenim günlüğü, ışık ve çiçek üzerine bir paragraf.';
  final buffer = StringBuffer(head);
  while (buffer.length + filler.length <= noteBodyMaxLength) {
    buffer.write(filler);
  }
  return buffer.toString().padRight(noteBodyMaxLength, '.');
}();

void main() {
  late FakeNoteRepository repo;
  late GoRouter router;
  late List<Note> fixture;
  late Note worst;

  setUp(() {
    fixture = notesFixture();
    final longTitle = fixture.firstWhere((n) => n.id == 2).title; // 255, unbroken
    final longBody = fixture.firstWhere((n) => n.id == 3).body!; // 60 lines
    worst = fixture
        .firstWhere((n) => n.id == 2)
        .copyWith(title: longTitle, body: longBody, tags: _twentyTags);
    repo = FakeNoteRepository([...fixture.where((n) => n.id != 2), worst]);
  });

  Future<void> pumpRouter(WidgetTester tester, double width, double textScale) async {
    tester.view.physicalSize = Size(width, _height);
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
      textScale: textScale != 1.0 ? textScale : null,
      overrides: [noteRepositoryProvider.overrideWith((ref) async => repo)],
    );
    await tester.pumpAndSettle();
  }

  Future<void> openNotes(
    WidgetTester tester,
    double width,
    double textScale, {
    bool settle = true,
  }) async {
    await pumpRouter(tester, width, textScale);
    router.push(AppRouter.notesPath);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
  }

  Future<void> openForm(WidgetTester tester, double width, double textScale, {Note? note}) async {
    await pumpRouter(tester, width, textScale);
    router.push(AppRouter.notesPath);
    await tester.pumpAndSettle();
    if (note == null) {
      router.push(AppRouter.notesNewPath);
    } else {
      router.push(AppRouter.notesEditPath, extra: note);
    }
    await tester.pumpAndSettle();
  }

  void openKeyboard(WidgetTester tester) {
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
    addTearDown(tester.view.resetViewInsets);
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

  void expectTapTarget(WidgetTester tester, Finder f, String what) {
    expect(f, findsOneWidget, reason: what);
    final size = tester.getSize(f);
    expect(size.width, greaterThanOrEqualTo(48), reason: '$what width');
    expect(size.height, greaterThanOrEqualTo(48), reason: '$what height');
  }

  void expectInsideWindow(WidgetTester tester, Finder f, double width, String what) {
    final r = tester.getRect(f);
    expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$what left');
    expect(r.right, lessThanOrEqualTo(width + 0.5), reason: '$what right');
  }

  final save = find.byKey(const ValueKey('note-save'));

  /// Scrolls the lazily built notes list until [f] is built and visible.
  Future<void> scrollToRow(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('notes-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
  }

  /// Kaydet is on screen, above [bottomLimit], at least 48 high and hit-testable.
  void expectSaveReachable(WidgetTester tester, double bottomLimit, String what) {
    final r = tester.getRect(save);
    expect(r.top, greaterThanOrEqualTo(0), reason: '$what Kaydet top');
    expect(r.bottom, lessThanOrEqualTo(bottomLimit + 0.5), reason: '$what Kaydet bottom');
    expect(r.height, greaterThanOrEqualTo(48), reason: '$what Kaydet height');
    expect(save.hitTestable(), findsOneWidget, reason: '$what Kaydet hit-testable');
  }

  /// Each visible tag chip in the form is one line, inside the window, with a
  /// 48x48 remove button.
  Future<void> expectFormChips(WidgetTester tester, double width, String what) async {
    for (final tag in [_twentyTags.first, _twentyTags.last]) {
      final remove = find.byKey(ValueKey('note-tag-remove-$tag'));
      await tester.ensureVisible(remove);
      await tester.pump();
      expectTapTarget(tester, remove, '$what remove $tag');
      final label = find.descendant(
        of: find.byKey(ValueKey('note-tag-chip-$tag')),
        matching: find.text(tag),
      );
      expect(drawnLines(tester, label), 1, reason: '$what chip $tag lines');
      expectInsideWindow(tester, find.byKey(ValueKey('note-tag-chip-$tag')), width, what);
    }
  }

  group('/notes', () {
    for (final width in _widths) {
      for (final scale in _textScales) {
        final label = '${width.toInt()}px x$scale';

        testWidgets('filled (255 unbroken title, long body, 20 long tags), $label', (tester) async {
          await openNotes(tester, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expectTapTarget(tester, find.byKey(const ValueKey('notes-add')), '$label add');
          expectTapTarget(
            tester,
            find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(IconButton)),
            '$label back',
          );

          final title = find.byKey(const ValueKey('note-title-2'));
          await tester.ensureVisible(title);
          await tester.pump();
          expect(drawnLines(tester, title), NotesScreen.titleMaxLines, reason: '$label title');
          expect(tester.renderObject<RenderParagraph>(title).didExceedMaxLines, isTrue);
          final body = find.byKey(const ValueKey('note-body-2'));
          expect(drawnLines(tester, body), NotesScreen.bodyMaxLines, reason: '$label body');
          expect(
            find.descendant(of: find.byKey(const ValueKey('note-2')), matching: find.text('+17')),
            findsOneWidget,
            reason: '$label +N',
          );
          expectTapTarget(tester, find.byKey(const ValueKey('note-favorite-2')), '$label star');
          expectTapTarget(tester, find.byKey(const ValueKey('note-delete-2')), '$label delete');
          expectInsideWindow(tester, find.byKey(const ValueKey('note-2')), width, label);
          // Back to the top, then every other row in list order.
          await tester.drag(find.byKey(const ValueKey('notes-list')), const Offset(0, 5000));
          await tester.pumpAndSettle();
          for (final id in [5, 4, 3, 1]) {
            final t = find.byKey(ValueKey('note-title-$id'));
            await scrollToRow(tester, t);
            expect(drawnLines(tester, t), lessThanOrEqualTo(2), reason: '$label title $id');
          }

          // Chip row: every chip ≥48 high and fully visible once scrolled to.
          final chips = [
            find.byKey(const ValueKey('notes-chip-favorites')),
            for (final t in repo.serverTags) find.byKey(ValueKey('notes-chip-tag-${t.name}')),
          ];
          for (final chip in [chips.first, chips[chips.length ~/ 2], chips.last]) {
            await tester.ensureVisible(chip);
            await tester.pump();
            expect(tester.getSize(chip).height, greaterThanOrEqualTo(48), reason: label);
            expectInsideWindow(tester, chip, width, '$label chip');
          }
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('Markdown body row (table, code, 255 unbroken line), $label', (tester) async {
          repo.server = [worst.copyWith(body: _markdownBody)];
          await openNotes(tester, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          final body = find.byKey(const ValueKey('note-body-2'));
          await scrollToRow(tester, body);
          expect(drawnLines(tester, body), NotesScreen.bodyMaxLines, reason: '$label body');
          expect(tester.renderObject<RenderParagraph>(body).didExceedMaxLines, isTrue);
          final shown = tester.renderObject<RenderParagraph>(body).text.toPlainText();
          for (final mark in ['# ', '**', '```']) {
            expect(shown, isNot(contains(mark)), reason: '$label $mark');
          }
          expect(drawnLines(tester, find.byKey(const ValueKey('note-title-2'))), 2);
          expectInsideWindow(tester, find.byKey(const ValueKey('note-2')), width, label);
          expectTapTarget(tester, find.byKey(const ValueKey('note-favorite-2')), '$label star');
          expectTapTarget(tester, find.byKey(const ValueKey('note-delete-2')), '$label delete');
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('no notes, $label', (tester) async {
          repo.server = [];
          await openNotes(tester, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expect(find.text(NotesScreen.emptyText), findsOneWidget);
          expectTapTarget(tester, find.byKey(const ValueKey('notes-empty-add')), label);
        });

        testWidgets('search with no match, $label', (tester) async {
          await openNotes(tester, width, scale);
          await tester.enterText(find.byKey(const ValueKey('notes-search')), 'zzz');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          expect(find.text(NotesScreen.noMatchText), findsOneWidget);
          expectTapTarget(tester, find.byKey(const ValueKey('notes-clear-filters')), label);
          expectTapTarget(tester, find.byKey(const ValueKey('notes-search-clear')), label);
        });

        testWidgets('loading, $label', (tester) async {
          repo.listGate = Completer<void>();
          addTearDown(() {
            if (!repo.listGate!.isCompleted) repo.listGate!.complete();
          });
          await openNotes(tester, width, scale, settle: false);
          expect(tester.takeException(), isNull, reason: label);
          expect(find.byKey(const ValueKey('notes-skeleton')), findsOneWidget);
          expectTapTarget(tester, find.byKey(const ValueKey('notes-add')), '$label add');
        });

        testWidgets('error, $label', (tester) async {
          repo.listFailure = _serverError;
          await openNotes(tester, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expect(find.text(userMessage(_serverError)), findsOneWidget);
          expectTapTarget(tester, find.byKey(const ValueKey('notes-retry')), label);
        });

        testWidgets('keyboard open while searching, $label', (tester) async {
          await openNotes(tester, width, scale);
          openKeyboard(tester);
          await tester.tap(find.byKey(const ValueKey('notes-search')));
          await tester.enterText(find.byKey(const ValueKey('notes-search')), 'ö');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          final search = tester.getRect(find.byKey(const ValueKey('notes-search')));
          expect(search.bottom, lessThanOrEqualTo(_height - _keyboard), reason: label);
          // The list stays usable above the keyboard: its last row can be
          // scrolled to and tapped.
          final row = find.byKey(const ValueKey('note-title-1'));
          await scrollToRow(tester, row);
          expect(row.hitTestable(), findsOneWidget, reason: '$label row reachable');
          expect(tester.getRect(row).bottom, lessThanOrEqualTo(_height - _keyboard + 0.5));
        });
      }
    }
  });

  group('/notes/edit and /notes/new', () {
    for (final width in _widths) {
      for (final scale in _textScales) {
        final label = '${width.toInt()}px x$scale';

        testWidgets('edit filled (255 title, long body, 20 tags), $label', (tester) async {
          await openForm(tester, width, scale, note: worst);
          expect(tester.takeException(), isNull, reason: label);
          expect(find.text(tagLimitMessage), findsOneWidget);
          expectSaveReachable(tester, _height, label);
          await expectFormChips(tester, width, label);
          expectInsideWindow(tester, find.byKey(const ValueKey('note-title-field')), width, label);
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('edit filled with the keyboard open, $label', (tester) async {
          await openForm(tester, width, scale, note: worst);
          openKeyboard(tester);
          await tester.tap(find.byKey(const ValueKey('note-body-field')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          expectSaveReachable(tester, _height - _keyboard, label);
        });

        testWidgets('edit Yaz tab with the format toolbar, $label', (tester) async {
          await openForm(tester, width, scale, note: worst);
          expect(tester.takeException(), isNull, reason: label);
          final toolbar = find.byKey(const ValueKey('note-format-toolbar'));
          expect(toolbar, findsOneWidget);
          expectInsideWindow(tester, toolbar, width, '$label toolbar');
          for (final f in [MarkdownFormat.values.first, MarkdownFormat.values.last]) {
            final b = find.byKey(MarkdownToolbar.buttonKey(f));
            await tester.ensureVisible(b);
            await tester.pump();
            expectTapTarget(tester, b, '$label ${f.name}');
            expectInsideWindow(tester, b, width, '$label ${f.name}');
            expect(b.hitTestable(), findsOneWidget, reason: '$label ${f.name}');
          }
          for (final key in ['note-tab-write', 'note-tab-preview']) {
            final tab = find.byKey(ValueKey(key));
            expect(drawnLines(tester, tab), 1, reason: '$label $key lines');
            expectTapTarget(
              tester,
              find.ancestor(of: tab, matching: find.byType(TextButton)),
              '$label $key',
            );
          }
          expectSaveReachable(tester, _height, label);
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('edit Önizle tab, every block, 20000 characters, $label', (tester) async {
          expect(_markdownBody.runes.length, noteBodyMaxLength);
          await openForm(tester, width, scale, note: worst.copyWith(body: _markdownBody));
          final previewTab = find.byKey(const ValueKey('note-tab-preview'));
          await tester.ensureVisible(previewTab); // below the 255 title at 360px x1.5
          await tester.pumpAndSettle();
          expect(previewTab.hitTestable(), findsOneWidget, reason: '$label tab tappable');
          await tester.tap(previewTab);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          expect(find.byKey(const ValueKey('note-format-toolbar')), findsNothing);
          final preview = find.byKey(const ValueKey('note-body-preview'));
          expect(preview, findsOneWidget);
          expectInsideWindow(tester, preview, width, '$label preview');
          expectSaveReachable(tester, _height, label);
          // Scroll through the whole preview: every block lays out.
          await tester.drag(
            find.byKey(const ValueKey('note-form-scroll')),
            const Offset(0, -100000),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          expectSaveReachable(tester, _height, '$label scrolled');
        });

        testWidgets('new with suggestions open, $label', (tester) async {
          await openForm(tester, width, scale);
          await tester.enterText(find.byKey(const ValueKey('note-title-field')), 'Yeni not');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          final box = find.byKey(const ValueKey('note-tag-suggestions'));
          expect(box, findsOneWidget, reason: label);
          expect(find.text(TagInput.suggestionsLabel), findsOneWidget);
          for (final t in repo.serverTags.take(3)) {
            final s = find.byKey(ValueKey('note-tag-suggestion-${t.name}'));
            await tester.ensureVisible(s);
            await tester.pump();
            expectTapTarget(tester, s, '$label suggestion ${t.name}');
            expectInsideWindow(tester, s, width, label);
            expect(
              drawnLines(tester, find.descendant(of: s, matching: find.text(t.name))),
              1,
              reason: label,
            );
          }
          expectSaveReachable(tester, _height, label);
        });

        testWidgets('new with the error snackbar open, $label', (tester) async {
          repo.onCreate = (_) async => const Left(_serverError);
          await openForm(tester, width, scale);
          await tester.enterText(find.byKey(const ValueKey('note-title-field')), 'Yeni not');
          await tester.pumpAndSettle();
          await tester.tap(save);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          final snack = find.byType(SnackBar);
          expect(snack, findsOneWidget);
          expect(find.text(userMessage(_serverError)), findsOneWidget);
          expect(
            tester.getRect(snack).bottom,
            lessThanOrEqualTo(tester.getRect(save).top + 0.5),
            reason: '$label snackbar above Kaydet',
          );
          expectSaveReachable(tester, _height, label);
        });
      }
    }
  });
}
