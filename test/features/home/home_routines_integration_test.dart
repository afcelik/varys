// Home + RoutinesCard integration: real HomeScreen, real notifiers; only the
// repositories are fakes returning real Either values. Routine data is real
// backend JSON (test/fixtures/routines_day.json):
//   1 "Su iç" daily, completed, streak 3
//   2 "Spor" weekly, 3 "Fatura öde" monthly, 4 "Bitki sula" interval: open

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/daily_tasks_card.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/home/presentation/widgets/inbox_card.dart';
import 'package:varys/features/home/presentation/widgets/random_note_card.dart';
import 'package:varys/features/home/presentation/widgets/routines_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routines_screen.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 1);
const _serverError =
    ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

List<RoutineDayItem> _routines() =>
    (jsonDecode(File('test/fixtures/routines_day.json').readAsStringSync()) as List<dynamic>)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();

DailyPlan _plan() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  final tasks =
      (json['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();
  return DailyPlan(planDate: _day, mainFocus: tasks.first, tasks: tasks);
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late DailyPlan plan;
  late List<RoutineDayItem> routines;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(TaskStatus.todo);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    plan = _plan();
    routines = _routines();
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(plan.tasks));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(routines));
  });

  List<Override> overrides() => [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
      ];

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Home inside a minimal GoRouter (/home + /routines) so push works.
  Future<void> pumpHome(WidgetTester tester, {Size size = const Size(790, 2600)}) async {
    setSize(tester, size);
    final router = GoRouter(
      initialLocation: AppRouter.homePath,
      routes: [
        GoRoute(path: AppRouter.homePath, builder: (_, _) => const HomeScreen()),
        GoRoute(path: AppRouter.routinesPath, builder: (_, _) => const RoutinesScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(),
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Finder inCard(Finder f) => find.descendant(of: find.byType(RoutinesCard), matching: f);
  Finder row(String title) => find.ancestor(of: inCard(find.text(title)), matching: find.byType(ListTile));
  Finder checkbox(String title) => find.descendant(of: row(title), matching: find.byType(Checkbox));
  Finder streak(int id) => inCard(find.byKey(ValueKey('streak-$id')));
  double top(WidgetTester tester, Finder f) => tester.getTopLeft(f).dy;

  void expectNoRawErrors() {
    expect(find.textContaining('Instance of'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  }

  testWidgets('shows counter, open rows first, completed row last and dimmed, streak',
      (tester) async {
    await pumpHome(tester);

    expect(inCard(find.text('Rutinler')), findsOneWidget);
    expect(inCard(find.text('1/4')), findsOneWidget);
    final titles = ['Spor', 'Fatura öde', 'Bitki sula', 'Su iç'];
    for (var i = 0; i < titles.length - 1; i++) {
      expect(top(tester, row(titles[i])) < top(tester, row(titles[i + 1])), isTrue);
    }
    expect(tester.widget<Checkbox>(checkbox('Su iç')).value, isTrue);
    final doneText = tester.widget<Text>(inCard(find.text('Su iç')));
    expect(doneText.style?.decoration, TextDecoration.lineThrough);
    expect(find.ancestor(of: row('Su iç'), matching: find.byType(Opacity)).evaluate().map(
        (e) => (e.widget as Opacity).opacity), contains(0.6));

    expect(find.descendant(of: streak(1), matching: find.text('3')), findsOneWidget);
    expect(find.descendant(of: streak(1), matching: find.byIcon(Icons.local_fire_department)),
        findsOneWidget);
    expect(streak(2), findsNothing, reason: 'streak 0 shows nothing');
    verify(() => routineRepo.getRoutinesForDay(_day)).called(1);
  });

  testWidgets('checkbox: row moves to the bottom, counter updates, refreshed streak shows',
      (tester) async {
    when(() => routineRepo.markDone(any(), any())).thenAnswer((_) async => const Right(null));
    await pumpHome(tester);
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right([
          for (final r in routines)
            r.id == 2 ? r.copyWith(completed: true, currentStreak: 1, longestStreak: 1) : r,
        ]));

    await tester.tap(checkbox('Spor'));
    await tester.pumpAndSettle();

    verify(() => routineRepo.markDone(2, _day)).called(1);
    expect(inCard(find.text('2/4')), findsOneWidget);
    expect(tester.widget<Checkbox>(checkbox('Spor')).value, isTrue);
    expect(top(tester, row('Bitki sula')) < top(tester, row('Spor')), isTrue,
        reason: 'completed row is below open rows');
    expect(find.descendant(of: streak(2), matching: find.text('1')), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('failed toggle: checkbox reverts, counter reverts, Turkish snackbar',
      (tester) async {
    final done = Completer<Either<Failure, void>>();
    when(() => routineRepo.markDone(any(), any())).thenAnswer((_) => done.future);
    await pumpHome(tester);

    await tester.tap(checkbox('Spor'));
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox('Spor')).value, isTrue, reason: 'optimistic');
    expect(inCard(find.text('2/4')), findsOneWidget);

    done.complete(const Left(_serverError));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(checkbox('Spor')).value, isFalse);
    expect(inCard(find.text('1/4')), findsOneWidget);
    expect(find.descendant(of: find.byType(SnackBar), matching: find.text(_serverError.userMessage)),
        findsOneWidget);
    expectNoRawErrors();
  });

  testWidgets('double tap while in flight sends one request (checkbox disabled)',
      (tester) async {
    final done = Completer<Either<Failure, void>>();
    when(() => routineRepo.markDone(any(), any())).thenAnswer((_) => done.future);
    await pumpHome(tester);

    await tester.tap(checkbox('Spor'));
    await tester.pump();
    expect(tester.widget<Checkbox>(checkbox('Spor')).onChanged, isNull);
    await tester.tap(checkbox('Spor'), warnIfMissed: false);
    await tester.pump();

    verify(() => routineRepo.markDone(2, _day)).called(1);
    done.complete(const Right(null));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(checkbox('Spor')).onChanged, isNotNull);
  });

  testWidgets('routine error affects ONLY the card; rest of Home works; retry loads',
      (tester) async {
    when(() => routineRepo.getRoutinesForDay(any()))
        .thenAnswer((_) async => const Left(_serverError));
    await pumpHome(tester);

    // Card: fixed Turkish message + single retry button.
    expect(inCard(find.text(_serverError.userMessage)), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(inCard(find.text('Tekrar dene')), findsOneWidget);
    expect(find.text('Plan yüklenemedi'), findsNothing);
    expectNoRawErrors();

    // Rest of Home: focus and tasks cards render and work.
    expect(find.byType(MainFocusCard), findsOneWidget);
    expect(find.byType(DailyTasksCard), findsOneWidget);
    expect(
        find.descendant(of: find.byType(DailyTasksCard), matching: find.text(plan.tasks.last.title)),
        findsOneWidget);
    expect(find.byType(RandomNoteCard), findsOneWidget);
    expect(find.byType(InboxCard), findsOneWidget);

    when(() => taskRepo.updateTaskStatus(any(), any())).thenAnswer(
        (inv) async => Right(plan.tasks.first.copyWith(status: TaskStatus.done)));
    final taskBox = find.descendant(
        of: find.ancestor(
            of: find.descendant(
                of: find.byType(DailyTasksCard), matching: find.text(plan.tasks.first.title)),
            matching: find.byType(ListTile)),
        matching: find.byType(Checkbox));
    await tester.tap(taskBox);
    await tester.pumpAndSettle();
    verify(() => taskRepo.updateTaskStatus(plan.tasks.first.id, TaskStatus.done)).called(1);
    expect(find.text('Tekrar dene'), findsOneWidget, reason: 'card error unchanged');

    // Retry inside the card.
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(routines));
    await tester.tap(inCard(find.text('Tekrar dene')));
    await tester.pumpAndSettle();
    expect(find.text('Tekrar dene'), findsNothing);
    expect(inCard(find.text('1/4')), findsOneWidget);
    expect(inCard(find.text('Spor')), findsOneWidget);
  });

  testWidgets('loading skeleton is inside the card while the rest of Home is shown',
      (tester) async {
    final load = Completer<Either<Failure, List<RoutineDayItem>>>();
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) => load.future);
    setSize(tester, const Size(790, 2600));
    await tester.pumpWidget(ProviderScope(
      overrides: overrides(),
      child: const MaterialApp(home: HomeScreen()),
    ));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }

    expect(inCard(find.byKey(const ValueKey('routines-skeleton'))), findsOneWidget);
    expect(find.byType(DailyTasksCard), findsOneWidget);

    load.complete(Right(routines));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('routines-skeleton')), findsNothing);
    expect(inCard(find.text('1/4')), findsOneWidget);
  });

  testWidgets('empty day shows "Bugün için rutin yok" and 0/0', (tester) async {
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
    await pumpHome(tester);

    expect(inCard(find.text('Bugün için rutin yok')), findsOneWidget);
    expect(inCard(find.text('0/0')), findsOneWidget);
    expect(inCard(find.byType(Checkbox)), findsNothing);
  });

  testWidgets('"Daha fazla" pushes /routines; back arrow returns to Home', (tester) async {
    await pumpHome(tester);

    await tester.ensureVisible(inCard(find.text('Daha fazla')));
    await tester.tap(inCard(find.text('Daha fazla')));
    await tester.pumpAndSettle();

    expect(find.byType(RoutinesScreen), findsOneWidget);
    expect(find.text(RoutinesScreen.placeholderText), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Rutinler'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget, reason: 'pushed, so back pops to Home');
  });

  group('placement: after daily tasks, before random note and inbox', () {
    Future<void> expectOrder(WidgetTester tester) async {
      final tasks = top(tester, find.byType(DailyTasksCard));
      final routinesTop = top(tester, find.byType(RoutinesCard));
      expect(tasks < routinesTop, isTrue);
      expect(routinesTop < top(tester, find.byType(RandomNoteCard)), isTrue);
      expect(routinesTop < top(tester, find.byType(InboxCard)), isTrue);
    }

    testWidgets('single column', (tester) async {
      await pumpHome(tester);
      await expectOrder(tester);
    });

    testWidgets('two columns: in the right column under the daily tasks card',
        (tester) async {
      await pumpHome(tester, size: const Size(1400, 2600));
      await expectOrder(tester);
      expect(tester.getTopLeft(find.byType(RoutinesCard)).dx,
          tester.getTopLeft(find.byType(DailyTasksCard)).dx);
      expect(tester.getTopLeft(find.byType(RoutinesCard)).dx >
          tester.getTopLeft(find.byType(MainFocusCard)).dx, isTrue);
    });
  });

  group('menu (real app router): /routines is not a menu destination', () {
    test('shell destinations do not include /routines', () {
      final paths = NavigationDestinations.shellDestinations.map((d) => d.routePath).toList();
      expect(paths, [AppRouter.homePath, AppRouter.planningPath, AppRouter.varysChatPath]);
      expect(paths, isNot(contains(AppRouter.routinesPath)));
    });

    Future<void> pumpApp(WidgetTester tester, Size size) async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
      setSize(tester, size);
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(),
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(routerProvider)),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
    }

    Future<void> openRoutines(WidgetTester tester) async {
      await tester.ensureVisible(inCard(find.text('Daha fazla')));
      await tester.tap(inCard(find.text('Daha fazla')));
      await tester.pumpAndSettle();
      expect(find.byType(RoutinesScreen), findsOneWidget);
    }

    testWidgets('bottom bar: 3 tabs without "Rutinler"; hidden on /routines', (tester) async {
      await pumpApp(tester, const Size(790, 2600));

      final bar = find.byType(NavigationBar);
      expect(bar, findsOneWidget);
      expect(find.descendant(of: bar, matching: find.byType(NavigationDestination)),
          findsNWidgets(3));
      expect(find.descendant(of: bar, matching: find.text('Rutinler')), findsNothing);

      await openRoutines(tester);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('side rail: 3 destinations without "Rutinler"; hidden on /routines',
        (tester) async {
      // Wide enough for the extended rail plus Home's two-column layout.
      await pumpApp(tester, const Size(1800, 2600));

      final rail = find.byType(NavigationRail);
      expect(rail, findsOneWidget);
      expect(tester.widget<NavigationRail>(rail).destinations, hasLength(3));
      expect(find.descendant(of: rail, matching: find.text('Rutinler')), findsNothing);

      await openRoutines(tester);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}
