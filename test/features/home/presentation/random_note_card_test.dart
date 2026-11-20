import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/widgets/random_note_card.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/presentation/note_edit_screen.dart';
import 'package:varys/features/notes/presentation/today_note_notifier.dart';

import '../../notes/fake_note_repository.dart';

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

void main() {
  late FakeNoteRepository repo;
  late GoRouter router;
  late List<Note> fixture;

  /// Every `extra` the edit route was built with (one per push).
  late List<Object?> editExtras;

  setUp(() {
    fixture = notesFixture();
    repo = FakeNoteRepository();
    editExtras = [];
  });

  Future<void> pumpCard(WidgetTester tester, {double width = 600, bool settle = true}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.homePath,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const RandomNoteCard(),
                  // Stands for the rest of Home: must keep working.
                  Builder(
                    builder: (context) => TextButton(
                      key: const ValueKey('other-card'),
                      onPressed: () => ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('DİĞER KART'))),
                      child: const Text('Diğer kart'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        GoRoute(
          path: AppRouter.notesPath,
          builder: (_, _) => const Scaffold(body: Text('NOTES PAGE')),
        ),
        GoRoute(
          path: AppRouter.notesEditPath,
          builder: (_, state) {
            editExtras.add(state.extra);
            return NoteEditScreen(note: state.extra! as Note);
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          noteRepositoryProvider.overrideWith((ref) async => repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Finder inCard(Finder f) => find.descendant(of: find.byType(RandomNoteCard), matching: f);
  final titleKey = find.byKey(const ValueKey('random-note-title'));
  final bodyKey = find.byKey(const ValueKey('random-note-body'));
  final openKey = find.byKey(const ValueKey('random-note-open'));

  /// Height of one line of the text at [finder]: the same 'Ağ' TextPainter
  /// reference as the Home and planning overflow tests (Step 29).
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

  int drawnLines(WidgetTester tester, Finder finder) =>
      (tester.getSize(finder).height / oneLineHeight(tester, finder)).round();

  void expectTapTarget(WidgetTester tester, Finder f, String what) {
    final size = tester.getSize(f);
    expect(size.width, greaterThanOrEqualTo(48), reason: '$what width');
    expect(size.height, greaterThanOrEqualTo(48), reason: '$what height');
  }

  testWidgets('filled: title, plain-text body, tags; asks for the local day', (tester) async {
    // A single note is always the note of the day.
    repo.server = [fixture.firstWhere((n) => n.id == 1)];
    await pumpCard(tester);

    expect(inCard(find.text(RandomNoteCard.title)), findsOneWidget);
    expect(RandomNoteCard.title, 'Günün Notu');
    expect(find.text('Rastgele Not'), findsNothing);
    expect(inCard(find.text('İş toplantısı notları')), findsOneWidget);
    expect(
      inCard(find.text('Pazartesi sunumu hazırla.\nBütçe tablosunu güncelle.')),
      findsOneWidget,
    );
    expect(inCard(find.text('iş')), findsOneWidget);
    expect(inCard(find.text('öğrenim')), findsOneWidget);
    expect(inCard(find.text(RandomNoteCard.emptyText)), findsNothing);
    expect(repo.ofDayDays, [_day]);
    expectTapTarget(tester, find.byKey(const ValueKey('random-note-more')), 'Daha fazla');
  });

  testWidgets('Markdown marks are shown as typed (no rendering yet)', (tester) async {
    repo.server = [fixture.first.copyWith(body: '# Başlık\n**kalın** ve _italik_')];
    await pumpCard(tester);
    expect(inCard(find.text('# Başlık\n**kalın** ve _italik_')), findsOneWidget);
  });

  testWidgets('body null: only the title (no body text)', (tester) async {
    repo.server = [fixture.firstWhere((n) => n.id == 4)];
    await pumpCard(tester);
    expect(inCard(find.text('Alışveriş listesi')), findsOneWidget);
    expect(bodyKey, findsNothing);
  });

  testWidgets('more than 3 tags: the first 3 and "+N"', (tester) async {
    repo.server = [
      fixture.first.copyWith(tags: ['a1', 'a2', 'a3', 'a4', 'a5']),
    ];
    await pumpCard(tester);
    for (final t in ['a1', 'a2', 'a3']) {
      expect(inCard(find.text(t)), findsOneWidget);
    }
    expect(inCard(find.text('a4')), findsNothing);
    expect(inCard(find.text('+2')), findsOneWidget);
  });

  testWidgets('exactly 3 tags: no "+N"', (tester) async {
    repo.server = [
      fixture.first.copyWith(tags: ['a1', 'a2', 'a3']),
    ];
    await pumpCard(tester);
    expect(find.byKey(const ValueKey('note-tags-more')), findsNothing);
  });

  testWidgets('empty (null note): "Henüz not yok" and "Not ekle" open /notes by push', (
    tester,
  ) async {
    repo.server = [];
    await pumpCard(tester);
    expect(inCard(find.text(RandomNoteCard.emptyText)), findsOneWidget);
    final add = find.byKey(const ValueKey('random-note-add'));
    expect(add, findsOneWidget);
    expectTapTarget(tester, add, 'Not ekle');

    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('NOTES PAGE'), findsOneWidget);
    expect(router.canPop(), isTrue, reason: 'push, not go');
  });

  testWidgets('"Daha fazla" opens /notes by push', (tester) async {
    await pumpCard(tester);
    await tester.tap(find.byKey(const ValueKey('random-note-more')));
    await tester.pumpAndSettle();
    expect(find.text('NOTES PAGE'), findsOneWidget);
    expect(router.canPop(), isTrue);
  });

  testWidgets('loading: skeleton inside the card only', (tester) async {
    repo.ofDayGate = Completer<void>();
    addTearDown(() {
      if (!repo.ofDayGate!.isCompleted) repo.ofDayGate!.complete();
    });
    await pumpCard(tester, settle: false);
    expect(find.byKey(const ValueKey('random-note-skeleton')), findsOneWidget);
    expect(inCard(find.text(RandomNoteCard.title)), findsOneWidget);
    expect(find.byKey(const ValueKey('other-card')), findsOneWidget);
    repo.ofDayGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('random-note-skeleton')), findsNothing);
  });

  testWidgets('error: userMessage + "Tekrar dene" reloads only the card; rest of Home works', (
    tester,
  ) async {
    repo.ofDayFailure = _serverError;
    await pumpCard(tester);
    expect(inCard(find.text(userMessage(_serverError))), findsOneWidget);
    final retry = find.byKey(const ValueKey('random-note-retry'));
    expectTapTarget(tester, retry, 'Tekrar dene');

    // The rest of the page still responds.
    await tester.tap(find.byKey(const ValueKey('other-card')));
    await tester.pump();
    expect(find.text('DİĞER KART'), findsOneWidget);

    repo.ofDayFailure = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(repo.ofDayCalls, 2);
    expect((repo.listCalls, repo.tagsCalls), (0, 0), reason: 'card only, not the notes list');
    expect(titleKey, findsOneWidget);
    expect(inCard(find.text(userMessage(_serverError))), findsNothing);
  });

  testWidgets('refresh keeps the previous note on screen (no skeleton)', (tester) async {
    await pumpCard(tester);
    final before = tester.widget<Text>(titleKey).data;
    repo.ofDayGate = Completer<void>();
    final container = ProviderScope.containerOf(tester.element(find.byType(RandomNoteCard)));
    container.invalidate(todayNoteProvider);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('random-note-skeleton')), findsNothing);
    expect(tester.widget<Text>(titleKey).data, before);
    repo.ofDayGate!.complete();
    await tester.pumpAndSettle();
  });

  group('tap to edit', () {
    testWidgets('tapping the content pushes /notes/edit with the Note; fields are filled', (
      tester,
    ) async {
      final note = fixture.firstWhere((n) => n.id == 1);
      repo.server = [note];
      await pumpCard(tester);

      await tester.tap(openKey);
      await tester.pumpAndSettle();

      expect(editExtras, [note], reason: 'pushed once with the Note as extra');
      expect(find.byType(NoteEditScreen), findsOneWidget);
      expect(
        router.routerDelegate.currentConfiguration.last.matchedLocation,
        AppRouter.notesEditPath,
      );
      expect(router.canPop(), isTrue, reason: 'push, not go');
      final title = tester.widget<TextField>(find.byKey(const ValueKey('note-title-field')));
      expect(title.controller!.text, note.title);
      final body = tester.widget<TextField>(find.byKey(const ValueKey('note-body-field')));
      expect(body.controller!.text, note.body);
      expect(find.text('iş'), findsWidgets);
    });

    testWidgets('tapping the title text itself also opens the edit page', (tester) async {
      repo.server = [fixture.firstWhere((n) => n.id == 1)];
      await pumpCard(tester);
      await tester.tap(titleKey);
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditScreen), findsOneWidget);
    });

    testWidgets('"Daha fazla" opens /notes and never the edit page', (tester) async {
      repo.server = [fixture.firstWhere((n) => n.id == 1)];
      await pumpCard(tester);
      final more = find.byKey(const ValueKey('random-note-more'));
      // Outside the content InkWell, so it can never start the edit tap.
      expect(find.descendant(of: openKey, matching: more), findsNothing);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('NOTES PAGE'), findsOneWidget);
      expect(find.byType(NoteEditScreen), findsNothing);
      expect(editExtras, isEmpty);
    });

    testWidgets('"Tekrar dene" reloads and never opens the edit page', (tester) async {
      repo.server = [fixture.firstWhere((n) => n.id == 1)];
      repo.ofDayFailure = _serverError;
      await pumpCard(tester);
      expect(openKey, findsNothing, reason: 'no content tap target in the error state');
      repo.ofDayFailure = null;
      await tester.tap(find.byKey(const ValueKey('random-note-retry')));
      await tester.pumpAndSettle();
      expect(titleKey, findsOneWidget);
      expect(find.byType(NoteEditScreen), findsNothing);
      expect(editExtras, isEmpty);
    });

    testWidgets('empty card has no content tap target; "Not ekle" never opens edit', (
      tester,
    ) async {
      repo.server = [];
      await pumpCard(tester);
      expect(openKey, findsNothing);
      await tester.tap(find.byKey(const ValueKey('random-note-add')));
      await tester.pumpAndSettle();
      expect(editExtras, isEmpty);
    });

    testWidgets('semantics: the content is a button labelled "Notu düzenle"', (tester) async {
      final handle = tester.ensureSemantics();
      repo.server = [fixture.firstWhere((n) => n.id == 1)];
      await pumpCard(tester);
      final data = tester.getSemantics(openKey).getSemanticsData();
      expect(data.label, startsWith(RandomNoteCard.editSemantics));
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(find.bySemanticsLabel(RegExp('^${RandomNoteCard.editSemantics}')), findsOneWidget);
      handle.dispose();
    });

    for (final (label, id) in [('with body', 1), ('body null', 4)]) {
      testWidgets('tap targets ($label): content ≥48 high, "Daha fazla" ≥48x48 and separate', (
        tester,
      ) async {
        repo.server = [fixture.firstWhere((n) => n.id == id)];
        await pumpCard(tester, width: 320);
        expect(tester.getSize(openKey).height, greaterThanOrEqualTo(48));
        final more = find.byKey(const ValueKey('random-note-more'));
        expectTapTarget(tester, more, 'Daha fazla');
        expect(find.descendant(of: openKey, matching: more), findsNothing);
        expect(tester.getRect(openKey).overlaps(tester.getRect(more)), isFalse);
      });
    }
  });

  for (final (width, scale) in [(360.0, 1.0), (360.0, 1.5), (1400.0, 1.5)]) {
    testWidgets('long title ≤ 2 lines and long body ≤ 3 lines, ${width.toInt()}px x$scale', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final longTitle = fixture.firstWhere((n) => n.id == 2).title; // 255, no spaces
      final longBody = fixture.firstWhere((n) => n.id == 3).body!; // 60 lines
      repo.server = [
        fixture.first.copyWith(
          title: longTitle,
          body: longBody,
          tags: [for (var i = 0; i < 8; i++) 'uzun etiket adı $i'],
        ),
      ];
      await pumpCard(tester, width: width);
      expect(tester.takeException(), isNull);
      expect(drawnLines(tester, titleKey), lessThanOrEqualTo(RandomNoteCard.titleMaxLines));
      expect(drawnLines(tester, titleKey), 2, reason: 'an unbroken 255 title still wraps');
      expect(drawnLines(tester, bodyKey), lessThanOrEqualTo(RandomNoteCard.bodyMaxLines));
      expect(drawnLines(tester, bodyKey), 3);
      expect(inCard(find.text('+5')), findsOneWidget);
    });
  }
}
