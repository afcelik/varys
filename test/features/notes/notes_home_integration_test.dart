// Notes ↔ Home on the real app: real router, real HomeScreen, real
// notifiers; only the repositories are fakes. The note fake behaves like the
// server (note of the day = notes by id [ordinal % n], null without notes).
// Creating, editing and deleting a note on /notes updates the Home
// "Rastgele Not" card; the other Home cards are not reloaded.

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
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

  testWidgets('with several notes the card shows the server pick for the day, and a '
      'new note changes n (the pick follows the server rule)', (tester) async {
    noteRepo.server = notesFixture(); // ids 1..5; 2026-11-19 → index 4 → id 5
    await pumpApp(tester);
    expect(tester.widget<Text>(cardTitle).data, 'Çiçek bakımı');
    final calls = noteRepo.randomCalls;

    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-more')));
    await tapAndSettle(tester, find.byKey(const ValueKey('notes-add')));
    await tester.enterText(find.byKey(const ValueKey('note-title-field')), 'Altıncı');
    await tester.pumpAndSettle();
    await tapAndSettle(tester, find.byKey(const ValueKey('note-save')));
    await back(tester);

    // 739939 % 6 = 1 → the 2nd note by id (id 2, the 255-character title).
    expect(noteRepo.randomCalls, calls + 1, reason: 'card reloaded exactly once');
    expect(tester.widget<Text>(cardTitle).data, notesFixture().firstWhere((n) => n.id == 2).title);
  });

  testWidgets('a favorite toggle on /notes does not break the card (reloaded once)', (
    tester,
  ) async {
    noteRepo.server = [notesFixture().firstWhere((n) => n.id == 3)];
    await pumpApp(tester);
    final calls = noteRepo.randomCalls;
    await tapAndSettle(tester, find.byKey(const ValueKey('random-note-more')));
    await tapAndSettle(tester, find.byKey(const ValueKey('note-favorite-3')));
    expect(noteRepo.updateCalls.single.$2, {'is_favorite': true});
    await back(tester);
    expect(noteRepo.randomCalls, calls + 1);
    expect(tester.widget<Text>(cardTitle).data, 'Öğrenim planı');
  });
}
