// Note form routes on the real app router and shell:
// - /notes/new opens the create form (no extra needed).
// - /notes/edit needs a Note as `extra`; anything else (none, String, int,
//   a Map that looks like a note) shows an error page and never the form
//   (no silent fallback). Not a redirect: a redirect on push adds a second
//   /home.
// - From /notes, tapping a row opens the edit form for that note.

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/presentation/note_edit_screen.dart';
import 'package:varys/features/notes/presentation/notes_screen.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

import '../../features/notes/fake_note_repository.dart';
import '../../features/projects/fake_project_repository.dart';

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
  late FakeNoteRepository noteRepo;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    noteRepo = FakeNoteRepository();
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => const Right([]));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
          taskRepositoryProvider.overrideWith((ref) async => taskRepo),
          routineRepositoryProvider.overrideWith((ref) async => routineRepo),
          projectRepositoryProvider.overrideWith((ref) async => FakeProjectRepository()),
          noteRepositoryProvider.overrideWith((ref) async => noteRepo),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(routerProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(router.canPop(), isFalse);
  }

  List<RouteMatch> stackMatches() {
    final matches = <RouteMatch>[];
    void collect(List<RouteMatchBase> list) {
      for (final m in list) {
        if (m is ShellRouteMatch) {
          collect(m.matches);
        } else if (m is RouteMatch) {
          matches.add(m);
        }
      }
    }

    collect(router.routerDelegate.currentConfiguration.matches);
    return matches;
  }

  int homeCount() => stackMatches().where((m) => m.route.path == AppRouter.homePath).length;

  String fieldText(WidgetTester tester, String key) =>
      tester.widget<TextField>(find.byKey(ValueKey(key))).controller!.text;

  Future<void> expectOnlyHome(WidgetTester tester) async {
    expect(find.byType(NoteEditScreen), findsNothing);
    expect(find.byType(NoteEditUnavailablePage), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRouter.homePath);
    expect(homeCount(), 1, reason: 'no duplicate /home on the stack');
    expect(stackMatches().whereType<ImperativeRouteMatch>(), isEmpty);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  }

  for (final entry in <String, Object?>{
    'no extra': null,
    "extra 'x' (String)": 'x',
    'extra 2 (int)': 2,
    'extra note JSON (Map)': {'id': 1, 'title': 'İş toplantısı notları', 'tags': <String>[]},
  }.entries) {
    testWidgets('push /notes/edit with ${entry.key}: error page (no form) over a single Home; '
        'BackArrow returns to it', (tester) async {
      await pumpApp(tester);
      router.push(AppRouter.notesEditPath, extra: entry.value);
      await tester.pumpAndSettle();

      expect(find.byType(NoteEditUnavailablePage), findsOneWidget);
      expect(find.text(NoteEditUnavailablePage.message), findsOneWidget);
      expect(find.byType(NoteEditScreen), findsNothing, reason: 'no fallback to a form');
      expect(find.byType(NavigationBar), findsNothing);
      expect(homeCount(), 1);
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed, hasLength(1));
      expect(pushed.single.route.path, AppRouter.notesEditPath);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await expectOnlyHome(tester);
    });
  }

  testWidgets('go /notes/edit (deep link) without extra: error page; BackArrow lands on a '
      'single Home', (tester) async {
    await pumpApp(tester);
    router.go(AppRouter.notesEditPath);
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditUnavailablePage), findsOneWidget);
    expect(find.byType(NoteEditScreen), findsNothing);
    expect(router.canPop(), isFalse);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  testWidgets('push /notes/new (no extra): create form outside the shell; BackArrow returns '
      'to a single Home', (tester) async {
    await pumpApp(tester);
    router.push(AppRouter.notesNewPath);
    await tester.pumpAndSettle();

    expect(find.byType(NoteEditScreen), findsOneWidget);
    expect(tester.widget<NoteEditScreen>(find.byType(NoteEditScreen)).note, isNull);
    expect(find.text(NoteEditScreen.createTitle), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(homeCount(), 1);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  testWidgets('push /notes/edit with a Note: edit form with the fields filled', (tester) async {
    await pumpApp(tester);
    final note = notesFixture().firstWhere((n) => n.id == 1);
    router.push(AppRouter.notesEditPath, extra: note);
    await tester.pumpAndSettle();

    expect(tester.widget<NoteEditScreen>(find.byType(NoteEditScreen)).note, note);
    expect(find.text(NoteEditScreen.editTitle), findsOneWidget);
    expect(fieldText(tester, 'note-title-field'), note.title);
    expect(fieldText(tester, 'note-body-field'), note.body);
    expect(find.byKey(const ValueKey('note-tag-chip-iş')), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await expectOnlyHome(tester);
  });

  testWidgets('from /notes a row tap opens its edit form (no "Sayfa bulunamadı")', (tester) async {
    await pumpApp(tester);
    router.push(AppRouter.notesPath);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('note-title-3')));
    await tester.pumpAndSettle();

    expect(find.text(AppRouter.errorTitle), findsNothing);
    expect(tester.widget<NoteEditScreen>(find.byType(NoteEditScreen)).note!.id, 3);
    expect(fieldText(tester, 'note-title-field'), 'Öğrenim planı');
    expect(homeCount(), 1);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(NotesScreen), findsOneWidget);
  });
}
