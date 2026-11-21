// The calendar day header's 'Bu güne blok ekle' button: 48x48 with a
// tooltip, beside the (max 2-line) day title without overlap, in every day
// state; it pushes /schedule/new with ScheduleNewArgs(selected day, once).
// The target route is a stub that records the extra.

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/calendar/data/calendar_repository_impl.dart';
import 'package:varys/features/calendar/presentation/calendar_screen.dart';
import 'package:varys/features/calendar/presentation/widgets/calendar_day_list.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/presentation/schedule_new_args.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../schedule/fake_schedule_repository.dart';
import '../fake_calendar_repository.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _today = DateTime(2026, 11, 21);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

Finder _cell(DateTime d) => find.byKey(ValueKey('calendar-day-${formatDateForApi(d)}'));

void main() {
  late FakeScheduleRepository scheduleRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late List<(String, Object?)> pushes;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    scheduleRepo = FakeScheduleRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    pushes = [];
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => const Right([]));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
  });

  Future<void> pumpPage(WidgetTester tester, {double width = 600, double scale = 1.0}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRouter.calendarPath,
      routes: [
        GoRoute(path: AppRouter.calendarPath, builder: (_, _) => const CalendarScreen()),
        GoRoute(
          path: AppRouter.scheduleNewPath,
          builder: (_, state) {
            pushes.add((AppRouter.scheduleNewPath, state.extra));
            return const Scaffold(body: Text('opened new'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      textScale: scale,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        calendarRepositoryProvider.overrideWith((ref) async => FakeCalendarRepository()),
        scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
      ],
    );
    await tester.pumpAndSettle();
  }

  final button = find.byKey(const ValueKey('calendar-day-add-block'));
  final title = find.byKey(const ValueKey('calendar-day-title'));

  testWidgets('tooltip and a 48x48 target, right of the day title', (tester) async {
    await pumpPage(tester);
    expect(find.byTooltip('Bu güne blok ekle'), findsOneWidget);
    expect(CalendarDayList.addBlockTooltip, 'Bu güne blok ekle');
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(tester.getRect(button).left, greaterThanOrEqualTo(tester.getRect(title).right));
  });

  testWidgets("today selected: pushes /schedule/new with today and once", (tester) async {
    await pumpPage(tester);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('opened new'), findsOneWidget);
    final (path, extra) = pushes.single;
    expect(path, AppRouter.scheduleNewPath);
    expect(extra, isA<ScheduleNewArgs>());
    expect((extra! as ScheduleNewArgs).day, _today);
    expect(extra as ScheduleNewArgs, ScheduleNewArgs(day: DateTime(2026, 11, 21), once: true));
  });

  testWidgets('another selected day (25 Kasım): the extra carries that day and once', (
    tester,
  ) async {
    await pumpPage(tester);
    await tester.tap(_cell(DateTime(2026, 11, 25)));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    final extra = pushes.single.$2! as ScheduleNewArgs;
    expect(extra.day, DateTime(2026, 11, 25));
    expect(extra.once, isTrue);
  });

  testWidgets('a day in the next month (after navigating): that day', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byKey(const ValueKey('calendar-next')));
    await tester.pumpAndSettle();
    await tester.tap(_cell(DateTime(2026, 12, 3)));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(pushes.single.$2, ScheduleNewArgs(day: DateTime(2026, 12, 3), once: true));
  });

  for (final (name, setUpState) in <(String, void Function(FakeScheduleRepository))>[
    ('filled', (_) {}),
    ('empty day', (r) => r.server = []),
    (
      'section error',
      (r) => r.dayFailure = const ServerFailure(
        'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
        statusCode: 500,
      ),
    ),
  ]) {
    testWidgets('$name, 320px x1.5: button 48x48 beside a title of at most 2 lines, no '
        'overflow, still opens the form', (tester) async {
      setUpState(scheduleRepo);
      await pumpPage(tester, width: 320, scale: 1.5);
      expect(tester.takeException(), isNull);
      final b = tester.getRect(button);
      final t = tester.getRect(title);
      expect(b.width, greaterThanOrEqualTo(48));
      expect(b.height, greaterThanOrEqualTo(48));
      expect(b.overlaps(t), isFalse);
      expect(b.right, lessThanOrEqualTo(320));
      final paragraph = tester.renderObject<RenderParagraph>(title);
      expect(paragraph.size.height, lessThanOrEqualTo(2 * paragraph.preferredLineHeight + 0.5));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(pushes.single.$2, ScheduleNewArgs(day: _today, once: true));
    });
  }
}
