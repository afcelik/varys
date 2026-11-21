// /calendar on the real app router and shell: opened by push from the Home
// date header and from the schedule card's calendar button; outside the shell
// (no menu) with a BackArrow; a single /home stays on the stack; a deep link
// (go, nothing to pop) returns to a single Home. Not a menu destination.

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
import 'package:varys/features/calendar/data/calendar_repository_impl.dart';
import 'package:varys/features/calendar/presentation/calendar_screen.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/date_header.dart';
import 'package:varys/features/home/presentation/widgets/schedule_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

import '../../features/calendar/fake_calendar_repository.dart';
import '../../features/schedule/fake_schedule_repository.dart';
import '../../helpers/varys_app_harness.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 21);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late FakeScheduleRepository scheduleRepo;
  late FakeCalendarRepository calendarRepo;
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
    scheduleRepo = FakeScheduleRepository();
    calendarRepo = FakeCalendarRepository();
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
    await pumpVarysApp(
      tester,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        nowProvider.overrideWithValue(() => DateTime(2026, 11, 21, 9, 10)),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
        calendarRepositoryProvider.overrideWith((ref) async => calendarRepo),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    router = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    ).read(routerProvider);
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

  void expectCalendarOverSingleHome() {
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(find.byType(BackArrow), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');
    expect(find.byType(NavigationRail), findsNothing);
    expect(homeCount(), 1, reason: 'no duplicate /home on the stack');
    final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
    expect(pushed, hasLength(1));
    expect(pushed.single.route.path, AppRouter.calendarPath);
    expect(calendarRepo.requests, [(year: 2026, month: 11)]);
  }

  Future<void> backToSingleHome(WidgetTester tester) async {
    await tester.tap(find.byType(BackArrow));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, AppRouter.homePath);
    expect(homeCount(), 1);
    expect(stackMatches().whereType<ImperativeRouteMatch>(), isEmpty);
    expect(router.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  }

  testWidgets('tapping the Home date header pushes /calendar; BackArrow returns', (tester) async {
    await pumpApp(tester);
    expect(find.byType(DateHeader), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('date-header-tap')));
    await tester.pumpAndSettle();
    expectCalendarOverSingleHome();
    await backToSingleHome(tester);
  });

  testWidgets('the schedule card calendar button pushes /calendar; BackArrow returns', (
    tester,
  ) async {
    await pumpApp(tester);
    final button = find.byKey(const ValueKey('schedule-card-calendar'));
    expect(find.descendant(of: find.byType(ScheduleCard), matching: button), findsOneWidget);
    expect(tester.widget<IconButton>(button).tooltip, 'Takvim');
    await tester.tap(button);
    await tester.pumpAndSettle();
    expectCalendarOverSingleHome();
    await backToSingleHome(tester);
  });

  testWidgets('go /calendar (deep link): BackArrow lands on a single Home', (tester) async {
    await pumpApp(tester);
    router.go(AppRouter.calendarPath);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);
    expect(router.canPop(), isFalse);
    await backToSingleHome(tester);
  });

  testWidgets('/calendar is not a menu destination (still 3 tabs)', (tester) async {
    await pumpApp(tester);
    expect(NavigationDestinations.shellDestinations.map((d) => d.routePath), [
      AppRouter.homePath,
      AppRouter.planningPath,
      AppRouter.varysChatPath,
    ]);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(3));
    expect(find.text(CalendarScreen.title), findsNothing);
  });
}
