// Focus selection route: the FocusSlot must come as `extra`; anything else
// shows an error page (no silent default). Not a redirect: go_router's
// redirect on push adds a second /home to the stack, which these tests
// guard against. Uses the real app router and shell. The focus cards pass
// the right slot.

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
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/focus_candidates.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/focus_task_selection_page.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

/// Real backend JSON, both focus slots empty (so both cards show their
/// "seç" tiles).
DailyPlan _plan() {
  final json =
      jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
          as Map<String, dynamic>;
  return DailyPlan(
    planDate: _day,
    tasks: (json['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList(),
  );
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(_plan()));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => const Right([]));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
  });

  List<Override> overrides() => [
    todayProvider.overrideWith(_FixedToday.new),
    dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
    taskRepositoryProvider.overrideWith((ref) async => taskRepo),
    routineRepositoryProvider.overrideWith((ref) async => routineRepo),
  ];

  group('real app router', () {
    late GoRouter router;

    Future<void> pumpApp(WidgetTester tester) async {
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
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

    /// Only Home is on the stack: one /home match, nothing pushed, nothing
    /// to pop, and back (maybePop) keeps Home on screen (app does not close).
    Future<void> expectOnlyHome(WidgetTester tester) async {
      expect(find.byType(FocusTaskSelectionPage), findsNothing);
      expect(find.byType(FocusSelectionUnavailablePage), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);

      expect(router.routerDelegate.currentConfiguration.uri.path, AppRouter.homePath);
      expect(homeCount(), 1, reason: 'no duplicate /home on the stack');
      expect(stackMatches().whereType<ImperativeRouteMatch>(), isEmpty);
      expect(router.canPop(), isFalse);

      final popped = await tester.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await tester.pumpAndSettle();
      expect(popped, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    /// Invalid extra: the error page is on top of exactly one /home; the
    /// only imperative (pushed) match is the focus selection route itself.
    Future<void> expectErrorPageOverSingleHome(WidgetTester tester) async {
      expect(find.byType(FocusSelectionUnavailablePage), findsOneWidget);
      expect(find.text('Bu sayfa doğrudan açılamaz.'), findsOneWidget);
      // No data page: no task list, no selection page.
      expect(find.byType(FocusTaskSelectionPage), findsNothing);
      expect(
        find.descendant(
          of: find.byType(FocusSelectionUnavailablePage),
          matching: find.byType(ListTile),
        ),
        findsNothing,
      );
      expect(find.text('İlk görev - yapılacak'), findsNothing);

      expect(homeCount(), 1, reason: 'no duplicate /home on the stack');
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed, hasLength(1));
      expect(pushed.single.route.path, AppRouter.focusTaskSelectionPath);
      expect(pushed.single.matchedLocation, isNot(AppRouter.homePath));
      expect(router.canPop(), isTrue);
    }

    for (final entry in <String, Object?>{
      'no extra': null,
      "extra 'main' (String)": 'main',
      'extra 1 (int)': 1,
    }.entries) {
      testWidgets('push with ${entry.key}: error page over a single /home; '
          'BackArrow returns to a single /home', (tester) async {
        await pumpApp(tester);
        router.push(AppRouter.focusTaskSelectionPath, extra: entry.value);
        await tester.pumpAndSettle();
        await expectErrorPageOverSingleHome(tester);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        await expectOnlyHome(tester);
      });
    }

    testWidgets('go (deep link / notification) without extra: error page, BackArrow lands '
        'on a single Home', (tester) async {
      await pumpApp(tester);
      router.go(AppRouter.focusTaskSelectionPath);
      await tester.pumpAndSettle();
      expect(find.text('Bu sayfa doğrudan açılamaz.'), findsOneWidget);
      expect(find.byType(FocusTaskSelectionPage), findsNothing);
      expect(router.canPop(), isFalse);

      // BackArrow: nothing to pop → go('/home').
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await expectOnlyHome(tester);
    });

    testWidgets('push with FocusSlot.side opens the page for that slot; back returns Home', (
      tester,
    ) async {
      await pumpApp(tester);
      router.push(AppRouter.focusTaskSelectionPath, extra: FocusSlot.side);
      await tester.pumpAndSettle();

      expect(find.byType(FocusTaskSelectionPage), findsOneWidget);
      expect(
        tester.widget<FocusTaskSelectionPage>(find.byType(FocusTaskSelectionPage)).slot,
        FocusSlot.side,
      );
      expect(find.text('İkincil odak seç'), findsWidgets);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await expectOnlyHome(tester);
    });

    testWidgets('focus cards open the real page with their own slot', (tester) async {
      await pumpApp(tester);

      await tester.tap(
        find.descendant(of: find.byType(MainFocusCard), matching: find.text('Ana odak seç')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FocusTaskSelectionPage>(find.byType(FocusTaskSelectionPage)).slot,
        FocusSlot.main,
      );
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: find.byType(SideFocusCard), matching: find.text('İkincil odak seç')),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<FocusTaskSelectionPage>(find.byType(FocusTaskSelectionPage)).slot,
        FocusSlot.side,
      );
    });
  });

  group('cards pass the slot as extra', () {
    testWidgets('MainFocusCard → FocusSlot.main, SideFocusCard → FocusSlot.side', (tester) async {
      final extras = <Object?>[];
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          GoRoute(
            path: AppRouter.focusTaskSelectionPath,
            builder: (context, state) {
              extras.add(state.extra);
              return Scaffold(
                body: TextButton(onPressed: () => context.pop(), child: const Text('Geri')),
              );
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = const Size(600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: find.byType(MainFocusCard), matching: find.text('Ana odak seç')),
      );
      await tester.pumpAndSettle();
      expect(extras.last, FocusSlot.main);
      await tester.tap(find.text('Geri'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(of: find.byType(SideFocusCard), matching: find.text('İkincil odak seç')),
      );
      await tester.pumpAndSettle();
      expect(extras.last, FocusSlot.side);
      expect(extras.toSet(), {FocusSlot.main, FocusSlot.side});
    });
  });
}
