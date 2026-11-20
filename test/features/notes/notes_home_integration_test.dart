// Notes ↔ Home on the real app: real router, real HomeScreen, real
// notifiers; only the repositories are fakes. The note fake behaves like the
// server's POST /notes/of-day (the day's pick is stored; a deleted pick is
// replaced; null without notes). Creating, editing and deleting a note
// updates the Home "Günün Notu" card (one more POST, no skeleton); tapping
// the card opens the edit page; the other Home cards are not reloaded.

import 'dart:async';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/projects_card.dart';
import 'package:varys/features/home/presentation/widgets/random_note_card.dart';
import 'package:varys/features/home/presentation/widgets/routines_card.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/presentation/note_edit_screen.dart';
import 'package:varys/features/notes/presentation/notes_screen.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

import '../../helpers/varys_app_harness.dart';
import '../projects/fake_project_repository.dart';
import 'fake_note_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late FakeProjectRepository projectRepo;
  late FakeNoteRepository noteRepo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    projectRepo = FakeProjectRepository();
    noteRepo = FakeNoteRepository([]); // no notes yet
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => const Right([]));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = const Size(600, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
        noteRepositoryProvider.overrideWith((ref) async => noteRepo),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  Finder inCard(Finder f) => find.descendant(of: find.byType(RandomNoteCard), matching: f);
  final cardTitle = find.byKey(const ValueKey('random-note-title'));

  Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) => tapAndSettle(tester, find.byIcon(Icons.arrow_back));

  final skeleton = find.byKey(const ValueKey('random-note-skeleton'));

  /// Counts the first load of the other Home cards; [expectOtherCardsUntouched]
  /// then checks none of them was loaded again.
  int otherCardsLoaded() {
    verify(() => planRepo.getPlan(any())).called(1);
    verify(() => routineRepo.getRoutinesForDay(any())).called(1);
    expect(projectRepo.activeCalls, 1);
    return projectRepo.activeCalls;
  }

  void expectOtherCardsUntouched(int projectCalls) {
    verifyNever(() => planRepo.getPlan(any()));
    verifyNever(() => routineRepo.getRoutinesForDay(any()));
    expect(projectRepo.activeCalls, projectCalls);
    expect(find.byType(ProjectsCard), findsOneWidget);
    expect(find.byType(RoutinesCard), findsOneWidget);
  }

  /// Parks the next POST /notes/of-day; returns the gate to release it.
  Completer<void> parkNoteOfDay() {
    final gate = Completer<void>();
    noteRepo.ofDayGate = gate;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    return gate;
  }

  Future<void> release(WidgetTester tester, Completer<void> gate) async {
    noteRepo.ofDayGate = null;
    gate.complete();
    await tester.pumpAndSettle();
  }

  testWidgets('create on /notes → Home card shows it; edit → new title; delete → '
      '"Henüz not yok"; other Home cards are not reloaded', (tester) async {
    await pumpApp(tester);
    expect(inCard(find.text(RandomNoteCard.emptyText)), findsOneWidget);
    expect(find.byType(ProjectsCard), findsOneWidget);
    expect(find.byType(RoutinesCard), findsOneWidget);
    // Each other card loaded once; verified calls are not counted again below.
    verify(() => planRepo.getPlan(any())).called(1);
    verify(() => routineRepo.getRoutinesForDay(any())).called(1);
    final projectCalls = projectRepo.activeCalls;
    expect(projectCalls, 1);

    // Card "Not ekle" → /notes (empty) → "Not ekle" → form.
    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-add')));
    expect(find.byType(NotesScreen), findsOneWidget);
    expect(find.text(NotesScreen.emptyText), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const ValueKey('notes-empty-add')));
    expect(find.byType(NoteEditScreen), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('note-title-field')), 'Tek not');
    await tester.enterText(find.byKey(const ValueKey('note-body-field')), 'İlk satır');
    await tester.enterText(find.byKey(const ValueKey('note-tag-input')), 'İş');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byKey(const ValueKey('note-save')));

    // Back on the list with the new note; then Home.
    expect(find.byType(NotesScreen), findsOneWidget);
    expect(find.text('Tek not'), findsOneWidget);
    expect(noteRepo.createBodies.single['tags'], ['iş']);
    await back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.widget<Text>(cardTitle).data, 'Tek not', reason: 'the only note is the pick');
    expect(inCard(find.text('İlk satır')), findsOneWidget);
    expect(inCard(find.text('iş')), findsOneWidget);

    // Edit the title from /notes → the card follows.
    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-more')));
    final id = noteRepo.server.single.id;
    await tapAndSettle(tester, find.byKey(ValueKey('note-title-$id')));
    await tester.enterText(find.byKey(const ValueKey('note-title-field')), 'Yeni başlık');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byKey(const ValueKey('note-save')));
    expect(noteRepo.updateCalls.single.$2, {'title': 'Yeni başlık'});
    await back(tester);
    expect(tester.widget<Text>(cardTitle).data, 'Yeni başlık');

    // Delete it → the card is empty again.
    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-more')));
    await tapAndSettle(tester, find.byKey(ValueKey('note-delete-$id')));
    await tapAndSettle(tester, find.byKey(const ValueKey('note-delete-confirm')));
    expect(find.text(NotesScreen.emptyText), findsOneWidget);
    await back(tester);
    expect(inCard(find.text(RandomNoteCard.emptyText)), findsOneWidget);
    expect(cardTitle, findsNothing);

    // The other Home cards were never reloaded by any of this.
    verifyNever(() => planRepo.getPlan(any()));
    verifyNever(() => routineRepo.getRoutinesForDay(any()));
    expect(projectRepo.activeCalls, projectCalls);
    expect(find.byType(ProjectsCard), findsOneWidget);
    expect(find.byType(RoutinesCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Markdown: "# Merhaba" typed in the form and saved → the /notes row and the Home '
      'card show "Merhaba" in bold with no "#"; the card content still opens the edit page', (
    tester,
  ) async {
    await pumpApp(tester);
    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-add')));
    await tapAndSettle(tester, find.byKey(const ValueKey('notes-empty-add')));
    await tester.enterText(find.byKey(const ValueKey('note-title-field')), 'Selam');
    await tester.enterText(find.byKey(const ValueKey('note-body-field')), '# Merhaba\n\nalt satır');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byKey(const ValueKey('note-save')));
    expect(noteRepo.createBodies.single['body'], '# Merhaba\n\nalt satır');

    /// Plain text and the style of the "Merhaba" run of a preview.
    (String, TextStyle?) preview(Finder f) {
      final paragraph = tester.renderObject<RenderParagraph>(f);
      TextStyle? style;
      paragraph.text.visitChildren((s) {
        if (s is TextSpan && s.text == 'Merhaba') style = s.style;
        return true;
      });
      return (paragraph.text.toPlainText(), style);
    }

    // /notes row.
    final id = noteRepo.server.single.id;
    final (rowText, rowStyle) = preview(find.byKey(ValueKey('note-body-$id')));
    expect(rowText, 'Merhaba\nalt satır');
    expect(rowStyle?.fontWeight, FontWeight.w600);
    expect(find.textContaining('#'), findsNothing);

    // Home card.
    await back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    final cardBody = inCard(find.byKey(const ValueKey('random-note-body')));
    final (cardText, cardStyle) = preview(cardBody);
    expect(cardText, 'Merhaba\nalt satır');
    expect(cardStyle?.fontWeight, FontWeight.w600);
    expect(inCard(find.textContaining('#')), findsNothing);

    // A tap on the rendered body opens the edit page with the raw Markdown.
    await tapAndSettle(tester, cardBody);
    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('note-body-field'))).controller!.text,
      '# Merhaba\n\nalt satır',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('with several notes the card shows the stored pick of the day; a new note '
      'does not change it (one more POST, same note)', (tester) async {
    noteRepo.server = notesFixture(); // ids 1..5; fake picks the smallest unseen id → 1
    await pumpApp(tester);
    expect(tester.widget<Text>(cardTitle).data, 'İş toplantısı notları');
    expect(noteRepo.ofDayDays, [_day]);
    final calls = noteRepo.ofDayCalls;

    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-more')));
    await tapAndSettle(tester, find.byKey(const ValueKey('notes-add')));
    await tester.enterText(find.byKey(const ValueKey('note-title-field')), 'Altıncı');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byKey(const ValueKey('note-save')));
    await back(tester);

    expect(noteRepo.ofDayCalls, calls + 1, reason: 'card reloaded exactly once');
    expect(
      tester.widget<Text>(cardTitle).data,
      'İş toplantısı notları',
      reason: 'the day\'s pick is stored; a new note does not replace it',
    );
  });

  testWidgets('a favorite toggle on /notes does not break the card (reloaded once)', (
    tester,
  ) async {
    noteRepo.server = [notesFixture().firstWhere((n) => n.id == 3)];
    await pumpApp(tester);
    final calls = noteRepo.ofDayCalls;
    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-more')));
    await tapAndSettle(tester, find.byKey(const ValueKey('note-favorite-3')));
    expect(noteRepo.updateCalls.single.$2, {'is_favorite': true});
    await back(tester);
    expect(noteRepo.ofDayCalls, calls + 1);
    expect(tester.widget<Text>(cardTitle).data, 'Öğrenim planı');
  });

  testWidgets('card content tap → edit form → new title → Kaydet → back on Home: the card '
      'shows the new title after exactly one POST, never a skeleton', (tester) async {
    noteRepo.server = notesFixture(); // the day's pick: id 1
    await pumpApp(tester);
    final projectCalls = otherCardsLoaded();
    expect(tester.widget<Text>(cardTitle).data, 'İş toplantısı notları');
    final calls = noteRepo.ofDayCalls;

    await tapAndSettle(tester, inCard(find.byKey(const ValueKey('random-note-open'))));
    expect(find.byType(NoteEditScreen), findsOneWidget);
    final title = find.byKey(const ValueKey('note-title-field'));
    expect(tester.widget<TextField>(title).controller!.text, 'İş toplantısı notları');
    await tester.enterText(title, 'Yeni başlık');
    await tester.pumpAndSettle();

    final gate = parkNoteOfDay();
    await tapAndSettle(tester, find.byKey(const ValueKey('note-save')));
    expect(noteRepo.updateCalls.single.$1, 1);
    expect(noteRepo.updateCalls.single.$2, {'title': 'Yeni başlık'});
    // The form closed itself; Home is back while the card reloads.
    expect(find.byType(NoteEditScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(noteRepo.ofDayCalls, calls + 1);
    expect(skeleton, findsNothing, reason: 'the old note stays while reloading');
    expect(tester.widget<Text>(cardTitle).data, 'İş toplantısı notları');

    await release(tester, gate);
    expect(tester.widget<Text>(cardTitle).data, 'Yeni başlık');
    expect(skeleton, findsNothing);
    expect(noteRepo.ofDayCalls, calls + 1, reason: 'exactly one POST, no loop');
    expect(noteRepo.ofDayDays.toSet(), {_day});
    expectOtherCardsUntouched(projectCalls);
    expect(tester.takeException(), isNull);
  });

  testWidgets('two notes: card shows A → "Daha fazla" → delete A on /notes → back: the card '
      'shows B after one POST; A is gone; no skeleton', (tester) async {
    final fixture = notesFixture();
    final a = fixture.firstWhere((n) => n.id == 1);
    final b = fixture.firstWhere((n) => n.id == 2);
    noteRepo.server = [a, b];
    await pumpApp(tester);
    final projectCalls = otherCardsLoaded();
    expect(tester.widget<Text>(cardTitle).data, a.title);
    final calls = noteRepo.ofDayCalls;

    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-more')));
    expect(find.byType(NotesScreen), findsOneWidget);
    await tapAndSettle(tester, find.byKey(const ValueKey('note-delete-1')));
    final gate = parkNoteOfDay();
    await tapAndSettle(tester, find.byKey(const ValueKey('note-delete-confirm')));
    expect(noteRepo.deleteIds, [1]);
    expect(noteRepo.ofDayCalls, calls + 1);

    await back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(skeleton, findsNothing, reason: 'reloading keeps the old content, no skeleton');

    await release(tester, gate);
    expect(tester.widget<Text>(cardTitle).data, b.title);
    expect(inCard(find.text(a.title)), findsNothing, reason: 'the deleted note is not shown');
    expect(skeleton, findsNothing);
    expect(noteRepo.ofDayCalls, calls + 1);
    expect(noteRepo.dayEntries[_day]!.noteId, b.id, reason: 'server replaced the day\'s pick');
    expectOtherCardsUntouched(projectCalls);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a single note deleted on /notes → back: "Henüz not yok" after one POST', (
    tester,
  ) async {
    final only = notesFixture().firstWhere((n) => n.id == 3);
    noteRepo.server = [only];
    await pumpApp(tester);
    final projectCalls = otherCardsLoaded();
    expect(tester.widget<Text>(cardTitle).data, only.title);
    final calls = noteRepo.ofDayCalls;

    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-more')));
    await tapAndSettle(tester, find.byKey(const ValueKey('note-delete-3')));
    await tapAndSettle(tester, find.byKey(const ValueKey('note-delete-confirm')));
    await back(tester);

    expect(inCard(find.text(RandomNoteCard.emptyText)), findsOneWidget);
    expect(inCard(find.text(only.title)), findsNothing);
    expect(cardTitle, findsNothing);
    expect(inCard(find.byKey(const ValueKey('random-note-open'))), findsNothing);
    expect(noteRepo.ofDayCalls, calls + 1);
    expectOtherCardsUntouched(projectCalls);
    expect(tester.takeException(), isNull);
  });
}
