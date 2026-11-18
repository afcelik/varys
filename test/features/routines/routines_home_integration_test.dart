// End-to-end inside the app: real app router, real HomeScreen, real
// notifiers (routinesListProvider, routinesForDayProvider). Only the
// repositories are fake. The routine repository keeps routines in memory and
// answers GET /routines/day with the routines scheduled on that day, the way
// the backend does, so the Home card shows only today's routines.

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
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/routines_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routine_edit_screen.dart';
import 'package:varys/features/routines/presentation/routines_screen.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

/// 2026-11-01 is a Sunday (weekday 6 with Monday=0).
final _today = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

/// In-memory routine store. Created routines get server-like fields from the
/// real POST /routines fixture. [dayGate], when set, parks the next day
/// fetch until completed (to observe the card while it re-fetches).
class _InMemoryRoutineRepository implements RoutineRepository {
  _InMemoryRoutineRepository(this.routines);

  final List<Routine> routines;
  int _nextId = 100;
  int dayFetches = 0;
  Completer<void>? dayGate;

  static final Routine _template = Routine.fromJson(
    jsonDecode(File('test/fixtures/routine_created.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  static bool _scheduled(Routine r, DateTime day) {
    if (day.isBefore(r.startDate)) return false;
    switch (r.recurrenceType) {
      case RecurrenceType.daily:
        return true;
      case RecurrenceType.weekly:
        return r.daysOfWeek!.contains(day.weekday - 1);
      case RecurrenceType.monthly:
        final lastDay = DateTime(day.year, day.month + 1, 0).day;
        final target = r.dayOfMonth! > lastDay ? lastDay : r.dayOfMonth!;
        return day.day == target;
      case RecurrenceType.interval:
        return day.difference(r.startDate).inDays % r.intervalDays! == 0;
    }
  }

  @override
  Future<Either<Failure, List<Routine>>> getRoutines() async => Right(List.of(routines));

  @override
  Future<Either<Failure, List<RoutineDayItem>>> getRoutinesForDay(DateTime day) async {
    dayFetches++;
    final gate = dayGate;
    if (gate != null) await gate.future;
    return Right([
      for (final r in routines)
        if (_scheduled(r, day))
          RoutineDayItem(
            id: r.id,
            title: r.title,
            description: r.description,
            recurrenceType: r.recurrenceType,
            daysOfWeek: r.daysOfWeek,
            dayOfMonth: r.dayOfMonth,
            intervalDays: r.intervalDays,
            startDate: r.startDate,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
            completed: false,
            currentStreak: 0,
            longestStreak: 0,
          ),
    ]);
  }

  @override
  Future<Either<Failure, Routine>> createRoutine({
    required String title,
    String? description,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
  }) async {
    final created = _template.copyWith(
      id: _nextId++,
      title: title,
      description: description,
      recurrenceType: recurrenceType,
      daysOfWeek: daysOfWeek,
      dayOfMonth: dayOfMonth,
      intervalDays: intervalDays,
      startDate: startDate,
    );
    routines.add(created);
    return Right(created);
  }

  @override
  Future<Either<Failure, Routine>> updateRoutine(int id, RoutineChanges changes) async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, void>> deleteRoutine(int id) async {
    routines.removeWhere((r) => r.id == id);
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> markDone(int routineId, DateTime day) async => const Right(null);

  @override
  Future<Either<Failure, void>> undo(int routineId, DateTime day) async => const Right(null);
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _InMemoryRoutineRepository routineRepo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _today, tasks: const [])));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => const Right([]));
    // Real GET /routines data: only "Su iç" (daily) is scheduled on Sunday
    // 2026-11-01 (Spor = Mon/Wed/Fri, Fatura = 31st, Bitki = every 3 days
    // from 2026-11-10).
    routineRepo = _InMemoryRoutineRepository(
      (jsonDecode(File('test/fixtures/routines_list.json').readAsStringSync()) as List)
          .map((e) => Routine.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  });

  late GoRouter router;

  Future<void> pumpApp(WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = const Size(790, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
          taskRepositoryProvider.overrideWith((ref) async => taskRepo),
          routineRepositoryProvider.overrideWith((ref) async => routineRepo),
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
  }

  Finder inCard(Finder f) => find.descendant(of: find.byType(RoutinesCard), matching: f);
  Finder skeleton() => inCard(find.byKey(const ValueKey('routines-skeleton')));

  Future<void> openRoutinesFromHome(WidgetTester tester) async {
    await tester.ensureVisible(inCard(find.text(RoutinesCard.moreText)));
    await tester.tap(inCard(find.text(RoutinesCard.moreText)));
    await tester.pumpAndSettle();
    expect(find.byType(RoutinesScreen), findsOneWidget);
  }

  Future<void> backToHome(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(RoutinesScreen), findsNothing);
  }

  /// From the list page: "Rutin ekle" → fill → Kaydet → back on the list.
  Future<void> createViaForm(
    WidgetTester tester, {
    required String title,
    required String typeLabel,
    List<int> days = const [],
  }) async {
    await tester.tap(find.byKey(const ValueKey('routines-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('routine-title')), title);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('routine-type')),
        matching: find.text(typeLabel),
      ),
    );
    await tester.pumpAndSettle();
    for (final d in days) {
      await tester.tap(find.byKey(ValueKey('weekday-$d')));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.byKey(const ValueKey('routine-save')));
    await tester.tap(find.byKey(const ValueKey('routine-save')));
    await tester.pumpAndSettle();
    expect(find.byType(RoutineEditScreen), findsNothing, reason: 'form popped after save');
    expect(find.byType(RoutinesScreen), findsOneWidget);
    expect(find.text(title), findsOneWidget, reason: 'new routine in the list');
  }

  testWidgets('starting state: card shows only the routine scheduled today', (tester) async {
    await pumpApp(tester);
    expect(inCard(find.text('Su iç')), findsOneWidget);
    expect(inCard(find.text('Spor')), findsNothing);
    expect(inCard(find.text('0/1')), findsOneWidget);
  });

  testWidgets('create a daily routine on /routines -> it appears in the Home card', (tester) async {
    await pumpApp(tester);
    await openRoutinesFromHome(tester);
    await createViaForm(tester, title: 'Kitap oku', typeLabel: 'Günlük');
    await backToHome(tester);

    expect(inCard(find.text('Kitap oku')), findsOneWidget);
    expect(inCard(find.text('Su iç')), findsOneWidget);
    expect(inCard(find.text('0/2')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('create a weekly routine that includes Sunday -> it appears in the card', (
    tester,
  ) async {
    await pumpApp(tester);
    await openRoutinesFromHome(tester);
    await createViaForm(tester, title: 'Haftalık plan', typeLabel: 'Haftalık', days: [6]);
    await backToHome(tester);
    expect(inCard(find.text('Haftalık plan')), findsOneWidget);
  });

  testWidgets('create a weekly routine NOT scheduled today (Mon/Tue) -> listed on /routines, '
      'NOT in the Home card', (tester) async {
    await pumpApp(tester);
    final fetchesBefore = routineRepo.dayFetches;
    await openRoutinesFromHome(tester);
    await createViaForm(tester, title: 'Yüzme', typeLabel: 'Haftalık', days: [0, 1]);
    expect(find.text('Pzt, Sal'), findsOneWidget);
    await backToHome(tester);

    expect(routineRepo.dayFetches, fetchesBefore + 1, reason: 'card re-fetched once');
    expect(inCard(find.text('Yüzme')), findsNothing, reason: 'not scheduled on Sunday');
    expect(inCard(find.text('Su iç')), findsOneWidget);
    expect(inCard(find.text('0/1')), findsOneWidget);
  });

  testWidgets('delete a routine on /routines -> it is gone from the Home card', (tester) async {
    await pumpApp(tester);
    expect(inCard(find.text('Su iç')), findsOneWidget);

    await openRoutinesFromHome(tester);
    await tester.tap(find.byKey(const ValueKey('routine-delete-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Sil')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('routine-row-1')), findsNothing);
    await backToHome(tester);

    expect(inCard(find.text('Su iç')), findsNothing);
    expect(inCard(find.text('Bugün için rutin yok')), findsOneWidget);
  });

  testWidgets('while the card re-fetches after a mutation, old rows stay and no skeleton', (
    tester,
  ) async {
    await pumpApp(tester);
    await openRoutinesFromHome(tester);
    routineRepo.dayGate = Completer<void>();
    await createViaForm(tester, title: 'Kitap oku', typeLabel: 'Günlük');
    await backToHome(tester);

    // Re-fetch still parked: previous rows visible, no skeleton flash.
    expect(inCard(find.text('Su iç')), findsOneWidget);
    expect(inCard(find.text('Kitap oku')), findsNothing);
    expect(skeleton(), findsNothing);

    routineRepo.dayGate!.complete();
    routineRepo.dayGate = null;
    await tester.pumpAndSettle();
    expect(inCard(find.text('Kitap oku')), findsOneWidget);
    expect(skeleton(), findsNothing);
  });
}
