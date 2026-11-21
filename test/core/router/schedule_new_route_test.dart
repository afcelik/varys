// /schedule/new on the real app router and shell. No extra: the old create
// form (today, daily). A ScheduleNewArgs extra: that day, optionally one-time.
// Any other extra (String, Map, int): an error page built in pageBuilder (no
// redirect: a redirect on push adds a second /home). The last group drives
// the calendar's 'Bu güne blok ekle' end to end: the day list and the month
// counts follow the saved block (consistent fake servers).

import 'dart:async';

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
import 'package:varys/features/calendar/domain/calendar_month.dart';
import 'package:varys/features/calendar/presentation/calendar_providers.dart';
import 'package:varys/features/calendar/presentation/calendar_screen.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/presentation/schedule_edit_screen.dart';
import 'package:varys/features/schedule/presentation/schedule_new_args.dart';

import '../../features/calendar/fake_calendar_repository.dart';
import '../../features/notes/fake_note_repository.dart';
import '../../features/projects/fake_project_repository.dart';
import '../../features/schedule/fake_schedule_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 21);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

Finder _cell(DateTime d) => find.byKey(ValueKey('calendar-day-${formatDateForApi(d)}'));

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
    calendarRepo = FakeCalendarRepository.consistent(
      tasks: () => const <Task>[],
      routines: () => const <RoutineDayItem>[],
      blocks: () => scheduleRepo.server,
    );
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
          nowProvider.overrideWithValue(() => DateTime(2026, 11, 21, 9, 10)),
          dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
          taskRepositoryProvider.overrideWith((ref) async => taskRepo),
          routineRepositoryProvider.overrideWith((ref) async => routineRepo),
          projectRepositoryProvider.overrideWith((ref) async => FakeProjectRepository()),
          scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
          calendarRepositoryProvider.overrideWith((ref) async => calendarRepo),
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

  String startDateText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('schedule-start-date-text'))).data!;
  String startDateLabel(WidgetTester tester) => tester
      .widget<InputDecorator>(find.byKey(const ValueKey('schedule-start-date')))
      .decoration
      .labelText!;
  bool chipSelected(WidgetTester tester, String type) =>
      tester.widget<ChoiceChip>(find.byKey(ValueKey('schedule-type-$type'))).selected;

  group('valid extras', () {
    testWidgets('no extra: the old create form (today, daily) over a single Home', (tester) async {
      await pumpApp(tester);
      unawaited(router.push(AppRouter.scheduleNewPath));
      await tester.pumpAndSettle();
      expect(find.text(ScheduleEditScreen.createTitle), findsOneWidget);
      expect(startDateText(tester), '21.11.2026');
      expect(chipSelected(tester, 'daily'), isTrue);
      expect(startDateLabel(tester), 'Başlangıç tarihi');
      expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');
      expect(homeCount(), 1);
    });

    testWidgets('ScheduleNewArgs(25 Kasım, once): that day, Tek sefer, label Gün', (tester) async {
      await pumpApp(tester);
      unawaited(
        router.push(
          AppRouter.scheduleNewPath,
          extra: ScheduleNewArgs(day: DateTime(2026, 11, 25), once: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(ScheduleEditScreen.createTitle), findsOneWidget);
      expect(startDateText(tester), '25.11.2026');
      expect(chipSelected(tester, 'once'), isTrue);
      expect(chipSelected(tester, 'daily'), isFalse);
      expect(startDateLabel(tester), 'Gün');
      expect(find.byKey(const ValueKey('schedule-once-note')), findsNothing);
      expect(homeCount(), 1);
    });

    testWidgets('ScheduleNewArgs(25 Kasım) without once: that day, daily', (tester) async {
      await pumpApp(tester);
      unawaited(
        router.push(AppRouter.scheduleNewPath, extra: ScheduleNewArgs(day: DateTime(2026, 11, 25))),
      );
      await tester.pumpAndSettle();
      expect(startDateText(tester), '25.11.2026');
      expect(chipSelected(tester, 'daily'), isTrue);
    });

    testWidgets('a day outside 2000-01-01..2100-12-31 is clamped; the time part is dropped', (
      tester,
    ) async {
      await pumpApp(tester);
      unawaited(
        router.push(
          AppRouter.scheduleNewPath,
          extra: ScheduleNewArgs(day: DateTime(1999, 12, 31), once: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(startDateText(tester), '01.01.2000');
      router.pop();
      await tester.pumpAndSettle();
      unawaited(
        router.push(
          AppRouter.scheduleNewPath,
          extra: ScheduleNewArgs(day: DateTime(2026, 11, 25, 23, 59), once: true),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state<ScheduleEditScreenState>(find.byType(ScheduleEditScreen));
      expect(state.startDate, DateTime(2026, 11, 25));
    });

    testWidgets('go /schedule/new (deep link, no extra): the create form; BackArrow falls back', (
      tester,
    ) async {
      await pumpApp(tester);
      router.go(AppRouter.scheduleNewPath);
      await tester.pumpAndSettle();
      expect(find.text(ScheduleEditScreen.createTitle), findsOneWidget);
      expect(router.canPop(), isFalse);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleEditScreen), findsNothing);
      expect(homeCount(), lessThanOrEqualTo(1));
      expect(tester.takeException(), isNull);
    });
  });

  group('invalid extras', () {
    for (final (name, extra) in <(String, Object)>[
      ('a String', '2026-11-25'),
      ('a Map', <String, dynamic>{'day': '2026-11-25', 'once': true}),
      ('an int', 25),
    ]) {
      testWidgets('push /schedule/new with $name: error page over a single Home; BackArrow '
          'returns', (tester) async {
        await pumpApp(tester);
        unawaited(router.push(AppRouter.scheduleNewPath, extra: extra));
        await tester.pumpAndSettle();

        expect(find.text(ScheduleEditUnavailablePage.message), findsOneWidget);
        expect(find.text('Bu sayfa doğrudan açılamaz.'), findsOneWidget);
        expect(find.byType(ScheduleEditScreen), findsNothing, reason: 'no silent fallback');
        expect(find.byType(NavigationBar), findsNothing);
        expect(homeCount(), 1, reason: 'no redirect, no second /home');
        final pushed = stackMatches().whereType<ImperativeRouteMatch>().toList();
        expect(pushed.single.route.path, AppRouter.scheduleNewPath);

        await tester.tap(find.byIcon(Icons.arrow_back));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(currentPath(), AppRouter.homePath);
        expect(homeCount(), 1);
        expect(router.canPop(), isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('calendar: Bu güne blok ekle', () {
    CalendarDay dayOf(WidgetTester tester, DateTime d) {
      final container = ProviderScope.containerOf(tester.element(find.byType(CalendarScreen)));
      final month = container
          .read(calendarMonthProvider((year: d.year, month: d.month)))
          .requireValue;
      return month.days.firstWhere((c) => c.day == d);
    }

    testWidgets('25 Kasım -> form on that day as once -> Kaydet -> back on the calendar: the '
        'block is in Program on the 25th only and only its count rose', (tester) async {
      await pumpApp(tester);
      unawaited(router.push(AppRouter.calendarPath));
      await tester.pumpAndSettle();
      final d25 = DateTime(2026, 11, 25);
      final d26 = DateTime(2026, 11, 26);
      await tester.tap(_cell(d25));
      await tester.pumpAndSettle();
      final before25 = dayOf(tester, d25).scheduleCount;
      final before26 = dayOf(tester, d26).scheduleCount;
      final requestsBefore = calendarRepo.requests.length;

      await tester.tap(find.byKey(const ValueKey('calendar-day-add-block')));
      await tester.pumpAndSettle();
      expect(startDateText(tester), '25.11.2026');
      expect(chipSelected(tester, 'once'), isTrue);
      await tester.enterText(find.byKey(const ValueKey('schedule-title')), 'Doktor randevusu');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('schedule-save')));
      await tester.pumpAndSettle();

      final body = scheduleRepo.createBodies.single;
      expect(body['recurrence_type'], 'once');
      expect(body['start_date'], d25);
      expect(body['days_of_week'], isNull);
      expect(body['day_of_month'], isNull);
      expect(body['interval_days'], isNull);

      expect(find.byType(CalendarScreen), findsOneWidget, reason: 'popped back');
      expect(homeCount(), 1);
      final program = find.byKey(const ValueKey('calendar-section-schedule'));
      expect(find.descendant(of: program, matching: find.text('Doktor randevusu')), findsOneWidget);
      expect(calendarRepo.requests.length, greaterThan(requestsBefore), reason: 'month refreshed');
      expect(dayOf(tester, d25).scheduleCount, before25 + 1);
      expect(dayOf(tester, d26).scheduleCount, before26);

      await tester.tap(_cell(d26));
      await tester.pumpAndSettle();
      expect(find.text('Doktor randevusu'), findsNothing, reason: 'one-time: not on the 26th');
      expect(tester.takeException(), isNull);
    });
  });
}
