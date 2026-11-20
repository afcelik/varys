// Schedule routes on the real app router and shell:
// - /schedule (list) and /schedule/new (create form) need no extra.
// - /schedule/edit needs a ScheduleBlock as `extra`; anything else (none,
//   String, Map, int) shows an error page and never the create form. Not a
//   redirect (a redirect on push adds a second /home).
// - From the Home card, "Blok ekle", a row tap and "Daha fazla" open the real
//   pages. None of these pages is a menu destination.

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
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/schedule_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/presentation/schedule_edit_screen.dart';
import 'package:varys/features/schedule/presentation/schedule_screen.dart';

import '../../features/schedule/fake_schedule_repository.dart';
import '../../helpers/varys_app_harness.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

final _day = scheduleFixtureDay;

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late FakeScheduleRepository scheduleRepo;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    scheduleRepo = FakeScheduleRepository();
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => const Right([]));
  });

  /// Real app root and real routerProvider, logged in on Home.
  Future<void> pumpApp(WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        nowProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9, 10)),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    router = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    ).read(routerProvider);
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

  Future<void> expectOnlyHome(WidgetTester tester) async {
    expect(find.byType(ScheduleEditScreen), findsNothing);
    expect(find.byType(ScheduleEditUnavailablePage), findsNothing);
    expect(find.byType(ScheduleScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRouter.homePath);
    expect(homeCount(), 1, reason: 'no duplicate /home on the stack');
    expect(stackMatches().whereType<ImperativeRouteMatch>(), isEmpty);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
  }

  for (final entry in <String, Object?>{
    'no extra': null,
    "extra 'x' (String)": 'x',
    'extra Map': <String, Object?>{'id': 1, 'title': 'Kahvaltı'},
    'extra 2 (int)': 2,
  }.entries) {
    testWidgets('push /schedule/edit with ${entry.key}: error page (no create form) over a '
        'single /home; BackArrow returns to a single /home', (tester) async {
      await pumpApp(tester);
      router.push(AppRouter.scheduleEditPath, extra: entry.value);
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleEditUnavailablePage), findsOneWidget);
      expect(find.text('Bu sayfa doğrudan açılamaz.'), findsOneWidget);
      expect(find.byType(ScheduleEditScreen), findsNothing, reason: 'no silent create form');
      expect(find.text(ScheduleEditScreen.saveText), findsNothing);
      expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');
      expect(homeCount(), 1);
      final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
      expect(pushed, hasLength(1));
      expect(pushed.single.route.path, AppRouter.scheduleEditPath);

      await back(tester);
      await expectOnlyHome(tester);
    });
  }

  testWidgets('go /schedule/edit (deep link) without extra: error page; BackArrow lands on a '
      'single Home', (tester) async {
    await pumpApp(tester);
    router.go(AppRouter.scheduleEditPath);
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleEditUnavailablePage), findsOneWidget);
    expect(router.canPop(), isFalse);
    await back(tester);
    await expectOnlyHome(tester);
  });

  testWidgets('push /schedule/new: create form outside the shell; back to a single Home', (
    tester,
  ) async {
    await pumpApp(tester);
    router.push(AppRouter.scheduleNewPath);
    await tester.pumpAndSettle();
    expect(tester.widget<ScheduleEditScreen>(find.byType(ScheduleEditScreen)).block, isNull);
    expect(find.text(ScheduleEditScreen.createTitle), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(homeCount(), 1);
    await back(tester);
    await expectOnlyHome(tester);
  });

  testWidgets('push /schedule/edit with a ScheduleBlock: edit form for it', (tester) async {
    await pumpApp(tester);
    final block = scheduleListFixture()[2];
    router.push(AppRouter.scheduleEditPath, extra: block);
    await tester.pumpAndSettle();
    expect(tester.widget<ScheduleEditScreen>(find.byType(ScheduleEditScreen)).block, block);
    expect(find.text(ScheduleEditScreen.editTitle), findsOneWidget);
    await back(tester);
    await expectOnlyHome(tester);
  });

  testWidgets('push /schedule: the page with a BackArrow, outside the shell', (tester) async {
    await pumpApp(tester);
    router.push(AppRouter.schedulePath);
    await tester.pumpAndSettle();
    expect(find.byType(ScheduleScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    await back(tester);
    await expectOnlyHome(tester);
  });

  testWidgets('Home -> /schedule -> row -> edit form; BackArrow steps back one page at a time', (
    tester,
  ) async {
    await pumpApp(tester);
    router.push(AppRouter.schedulePath);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-list-title-2')));
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditScreen.editTitle), findsOneWidget);
    await back(tester);
    expect(find.byType(ScheduleScreen), findsOneWidget);
    await back(tester);
    await expectOnlyHome(tester);
  });

  group('from the Home card (real pages)', () {
    testWidgets('"Blok ekle" opens the real create form; back to Home', (tester) async {
      await pumpApp(tester);
      final add = find.descendant(
        of: find.byType(ScheduleCard),
        matching: find.byTooltip(ScheduleCard.addTooltip),
      );
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleEditScreen), findsOneWidget);
      expect(tester.widget<ScheduleEditScreen>(find.byType(ScheduleEditScreen)).block, isNull);
      expect(find.byType(ScheduleEditUnavailablePage), findsNothing);
      await back(tester);
      await expectOnlyHome(tester);
    });

    testWidgets('a row tap opens the real edit form for that block', (tester) async {
      await pumpApp(tester);
      final title = find.descendant(
        of: find.byType(ScheduleCard),
        matching: find.byKey(const ValueKey('schedule-title-2')),
      );
      await tester.ensureVisible(title);
      await tester.tap(title);
      await tester.pumpAndSettle();
      final form = tester.widget<ScheduleEditScreen>(find.byType(ScheduleEditScreen));
      expect(form.block, scheduleDayFixture().firstWhere((b) => b.id == 2));
      expect(find.text(ScheduleEditScreen.editTitle), findsOneWidget);
      expect(find.byType(ScheduleEditUnavailablePage), findsNothing);
      await back(tester);
      await expectOnlyHome(tester);
    });

    testWidgets('"Daha fazla" opens the real /schedule page', (tester) async {
      await pumpApp(tester);
      final more = find.byKey(const ValueKey('schedule-card-more'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleScreen), findsOneWidget);
      expect(find.byType(ScheduleEditScreen), findsNothing);
      await back(tester);
      await expectOnlyHome(tester);
    });
  });

  test('schedule pages are not menu destinations', () {
    final paths = NavigationDestinations.shellDestinations.map((d) => d.routePath).toList();
    expect(paths, [AppRouter.homePath, AppRouter.planningPath, AppRouter.varysChatPath]);
    for (final p in [
      AppRouter.schedulePath,
      AppRouter.scheduleNewPath,
      AppRouter.scheduleEditPath,
    ]) {
      expect(paths, isNot(contains(p)));
    }
  });
}
