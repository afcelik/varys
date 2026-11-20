// /eisenhower/:quadrant on the real app router and shell. The quadrant page
// is pushed from the Home card, outside the shell; an unknown quadrant
// shows an error page built in pageBuilder (no redirect: a redirect on push
// adds a second /home). Not a menu destination. Data: real GET /tasks
// (tasks_eisenhower.json) through a mocked TaskRepository.

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
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/eisenhower_quadrant_page.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/eisenhower.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

import '../../features/notes/fake_note_repository.dart';
import '../../features/projects/fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 19);

const _failure = ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);

/// Real GET /tasks: 1 doNow (due 21.11), 2 schedule (project 1 "Ev taşıma"),
/// 3 delegate, 4 eliminate, 5 done (doNow flags).
List<Task> _fixture() =>
    (jsonDecode(File('test/fixtures/tasks_eisenhower.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .map(Task.fromJson)
        .toList();

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late GoRouter router;
  late List<Task> server;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    server = _fixture();
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(server));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => Right(server));
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
          noteRepositoryProvider.overrideWith((ref) async => FakeNoteRepository()),
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

  /// All route matches on the stack (shell matches flattened).
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
  String currentPath() => router.routerDelegate.currentConfiguration.uri.path;

  Future<void> backToHome(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(currentPath(), AppRouter.homePath);
    expect(homeCount(), 1);
    expect(router.canPop(), isFalse);
  }

  final expectedTitles = {
    EisenhowerQuadrant.doNow: 'Vergi beyannamesini gönder',
    EisenhowerQuadrant.schedule: 'Haftalık hedefleri yaz',
    EisenhowerQuadrant.delegate: 'Kargo görevlisini ara',
    EisenhowerQuadrant.eliminate: 'Eski e-postaları ayıkla',
  };

  for (final q in EisenhowerQuadrant.values) {
    testWidgets('Home card quadrant ${q.name}: page pushed outside the shell; BackArrow returns', (
      tester,
    ) async {
      await pumpApp(tester);
      final tile = find.byKey(ValueKey('eisenhower-quadrant-${q.pathSegment}'));
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();

      expect(find.byType(EisenhowerQuadrantPage), findsOneWidget);
      expect(find.byKey(const ValueKey('eisenhower-page-title')), findsOneWidget);
      expect(find.text(q.title), findsOneWidget);
      expect(find.text(q.subtitle), findsOneWidget);
      expect(find.text(expectedTitles[q]!), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');
      expect(homeCount(), 1);
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed.single.route.path, AppRouter.eisenhowerRoutePath, reason: 'pushed, not go');
      expect(pushed.single.matchedLocation, '/eisenhower/${q.pathSegment}');

      await backToHome(tester);
      expect(tester.takeException(), isNull);
    });
  }

  for (final segment in ['xyz', 'doNow', 'DO-NOW', 'do_now']) {
    testWidgets('push /eisenhower/$segment: error page over a single Home; BackArrow returns', (
      tester,
    ) async {
      await pumpApp(tester);
      unawaited(router.push('/eisenhower/$segment'));
      await tester.pumpAndSettle();

      expect(find.text(EisenhowerUnavailablePage.message), findsOneWidget);
      expect(find.byType(EisenhowerQuadrantPage), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(homeCount(), 1, reason: 'no redirect, no second /home');

      await backToHome(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('go /eisenhower/xyz (deep link): error page; BackArrow falls back to /home', (
    tester,
  ) async {
    await pumpApp(tester);
    router.go('/eisenhower/xyz');
    await tester.pumpAndSettle();
    expect(find.text(EisenhowerUnavailablePage.message), findsOneWidget);
    expect(router.canPop(), isFalse);

    await backToHome(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('not a menu destination: still exactly 3 tabs', (tester) async {
    await pumpApp(tester);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(3));
    expect(
      find.descendant(of: find.byType(NavigationBar), matching: find.textContaining('Öncelik')),
      findsNothing,
    );
  });

  group('quadrant page', () {
    Future<void> openPage(WidgetTester tester, EisenhowerQuadrant q) async {
      await pumpApp(tester);
      unawaited(router.push(AppRouter.eisenhowerPath(q)));
      await tester.pumpAndSettle();
    }

    testWidgets('filled: newest first, done task left out, meta line (project · due day)', (
      tester,
    ) async {
      final base = server.firstWhere((t) => t.id == 1);
      server = [
        base.copyWith(id: 20, title: 'Daha yeni acil iş', createdAt: DateTime(2026, 11, 21)),
        ...server,
      ];
      await openPage(tester, EisenhowerQuadrant.doNow);

      final rows = find.byWidgetPredicate(
        (w) =>
            w is ListTile &&
            (w.key as ValueKey?)?.value.toString().startsWith('eisenhower-page-task-') == true,
      );
      expect(tester.widgetList<ListTile>(rows).map((t) => (t.key! as ValueKey).value), [
        'eisenhower-page-task-20',
        'eisenhower-page-task-1',
      ]);
      expect(find.text('Kira ödemesini yap'), findsNothing, reason: 'done');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('eisenhower-page-meta-1'))).data,
        '21 Kas',
      );
    });

    testWidgets('meta line shows the project name', (tester) async {
      await openPage(tester, EisenhowerQuadrant.schedule);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('eisenhower-page-meta-2'))).data,
        'Ev taşıma',
      );
    });

    testWidgets('empty quadrant: "Bu bölmede görev yok"', (tester) async {
      server = server.where((t) => t.id != 3).toList();
      await openPage(tester, EisenhowerQuadrant.delegate);
      expect(find.text(EisenhowerQuadrantPage.emptyText), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('error: userMessage + "Tekrar dene"; retry shows the tasks', (tester) async {
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Left(_failure));
      await openPage(tester, EisenhowerQuadrant.eliminate);
      expect(find.text(userMessage(_failure)), findsOneWidget);
      expect(find.text(EisenhowerQuadrantPage.emptyText), findsNothing);
      final retry = find.byKey(const ValueKey('eisenhower-page-retry'));
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(server));
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text('Eski e-postaları ayıkla'), findsOneWidget);
    });

    testWidgets('loading: spinner, never the empty text (frame by frame)', (tester) async {
      // The very first list fetch is still running (Home card in skeleton).
      final gate = Completer<Either<Failure, List<Task>>>();
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) => gate.future);
      await pumpApp(tester);
      expect(find.byKey(const ValueKey('eisenhower-loading')), findsOneWidget);
      unawaited(router.push(AppRouter.eisenhowerPath(EisenhowerQuadrant.doNow)));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey('eisenhower-page-loading')), findsOneWidget);
      expect(find.text(EisenhowerQuadrantPage.emptyText), findsNothing);
      gate.complete(Right(server));
      await tester.pumpAndSettle();
      expect(find.text('Vergi beyannamesini gönder'), findsOneWidget);
    });

    testWidgets('row tap pushes the edit form with that task; back returns to the page', (
      tester,
    ) async {
      await openPage(tester, EisenhowerQuadrant.schedule);
      await tester.tap(find.text('Haftalık hedefleri yaz'));
      await tester.pumpAndSettle();

      final form = tester.widget<TaskEditScreen>(find.byType(TaskEditScreen));
      expect(form.task?.id, 2);
      expect(find.text(TaskEditScreen.editTitle), findsOneWidget);
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().map((m) => m.route.path);
      expect(pushed, [AppRouter.eisenhowerRoutePath, AppRouter.tasksEditPath]);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(EisenhowerQuadrantPage), findsOneWidget);
      expect(homeCount(), 1);
    });
  });
}
