// Integration: real app router + real HomeScreen + real DailyPlanNotifier +
// real FocusTaskSelectionPage; only the repositories are fakes. Choose the
// focus from today's "Bugün Yapılacaklar" list and check the PUT body.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/focus_task_selection_page.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _planDay = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _planDay;
}

/// Real backend JSON: tasks 1 todo, 2 in_progress, 3 done, 4 todo, 5 done.
/// Both focus slots empty.
DailyPlan _fixturePlan() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  return DailyPlan(
    planDate: _planDay,
    tasks: (json['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList(),
  );
}

/// Hand-written fake: GET returns [plan]; each PUT body is built with the
/// same [DailyPlanRepository.buildUpdateBody] the real PUT uses, recorded,
/// and applied like the server does (absent key = keep, null = clear).
class _FakeDailyPlanRepository extends Fake implements DailyPlanRepository {
  _FakeDailyPlanRepository(this.plan);

  DailyPlan plan;
  int getCalls = 0;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<Either<Failure, DailyPlan>> getPlan(DateTime day) async {
    getCalls++;
    return Right(plan);
  }

  @override
  Future<Either<Failure, DailyPlan>> updatePlan(
    DateTime day, {
    PlanField<int> mainFocusTaskId = const PlanField.unset(),
    PlanField<int> sideFocusTaskId = const PlanField.unset(),
    PlanField<String> sayNoText = const PlanField.unset(),
  }) async {
    final body = DailyPlanRepository.buildUpdateBody(
      mainFocusTaskId: mainFocusTaskId,
      sideFocusTaskId: sideFocusTaskId,
      sayNoText: sayNoText,
    );
    bodies.add(body);

    Task? byId(Object? id) => id == null ? null : plan.tasks.firstWhere((t) => t.id == id);
    plan = DailyPlan(
      planDate: plan.planDate,
      mainFocus:
          body.containsKey('main_focus_task_id') ? byId(body['main_focus_task_id']) : plan.mainFocus,
      sideFocus:
          body.containsKey('side_focus_task_id') ? byId(body['side_focus_task_id']) : plan.sideFocus,
      sayNoText: body.containsKey('say_no_text') ? body['say_no_text'] as String? : plan.sayNoText,
      tasks: plan.tasks,
    );
    return Right(plan);
  }
}

const _t1 = 'İlk görev - yapılacak';
const _t2 = 'İkinci görev - devam ediyor';
const _t4 = 'Dördüncü görev - yapılacak';

void main() {
  late _FakeDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    planRepo = _FakeDailyPlanRepository(_fixturePlan());
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => const Right([]));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = const Size(600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(routerConfig: ref.watch(routerProvider)),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  }

  Finder inMainCard(Finder f) => find.descendant(of: find.byType(MainFocusCard), matching: f);
  Finder inSideCard(Finder f) => find.descendant(of: find.byType(SideFocusCard), matching: f);
  Finder inPage(Finder f) =>
      find.descendant(of: find.byType(FocusTaskSelectionPage), matching: f);
  Finder pageTile(String title) =>
      find.ancestor(of: inPage(find.text(title)), matching: find.byType(ListTile));

  Future<void> chooseMainFocus(WidgetTester tester, String title) async {
    await tester.tap(inMainCard(find.text('Ana odak seç')));
    await tester.pumpAndSettle();
    expect(find.byType(FocusTaskSelectionPage), findsOneWidget);
    expect(inPage(find.text('Ana odak seç')), findsOneWidget);
    await tester.tap(inPage(find.text(title)));
    await tester.pumpAndSettle();
  }

  testWidgets('choose main focus → card updates, PUT body is only main_focus_task_id; '
      'then the main focus cannot be chosen as side focus', (tester) async {
    await pumpApp(tester);
    expect(inMainCard(find.text(_t1)), findsNothing);

    await chooseMainFocus(tester, _t1);

    expect(find.byType(FocusTaskSelectionPage), findsNothing);
    expect(inMainCard(find.text(_t1)), findsOneWidget);
    expect(planRepo.bodies, [
      {'main_focus_task_id': 1},
    ]);

    // Side focus page: task 1 is faded, labeled "Ana odak", tap does nothing.
    await tester.tap(inSideCard(find.text('İkincil odak seç')));
    await tester.pumpAndSettle();
    expect(inPage(find.text('İkincil odak seç')), findsOneWidget);
    expect(tester.widget<ListTile>(pageTile(_t1)).enabled, isFalse);
    expect(find.descendant(of: pageTile(_t1), matching: find.text('Ana odak')), findsOneWidget);

    await tester.tap(inPage(find.text(_t1)));
    await tester.pumpAndSettle();
    expect(find.byType(FocusTaskSelectionPage), findsOneWidget);
    expect(planRepo.bodies, hasLength(1), reason: 'no new PUT');

    // A selectable task still works for the side slot.
    await tester.tap(inPage(find.text(_t2)));
    await tester.pumpAndSettle();
    expect(inSideCard(find.text(_t2)), findsOneWidget);
    expect(inMainCard(find.text(_t1)), findsOneWidget);
    expect(planRepo.bodies.last, {'side_focus_task_id': 2});
  });

  testWidgets('back from the page changes nothing (no PUT, focus kept)', (tester) async {
    await pumpApp(tester);
    await chooseMainFocus(tester, _t1);

    // Open the side page and leave with BackArrow.
    await tester.tap(inSideCard(find.text('İkincil odak seç')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(inMainCard(find.text(_t1)), findsOneWidget);
    expect(inSideCard(find.text('İkincil odak seç')), findsOneWidget);
    expect(planRepo.bodies, [
      {'main_focus_task_id': 1},
    ]);
  });

  testWidgets('plan reload with a different task list (focus moved to another day): '
      'card title kept, selection page opens without crashing', (tester) async {
    await pumpApp(tester);
    await chooseMainFocus(tester, _t1);
    expect(inMainCard(find.text(_t1)), findsOneWidget);

    // Server now returns task 1 only as main_focus: it left today's list.
    final focus = planRepo.plan.mainFocus!;
    planRepo.plan = DailyPlan(
      planDate: _planDay,
      mainFocus: focus.copyWith(plannedDate: DateTime(2026, 11, 5)),
      tasks: planRepo.plan.tasks.where((t) => t.id != 1).toList(),
    );
    final getsBefore = planRepo.getCalls;
    ProviderScope.containerOf(tester.element(find.byType(HomeScreen)))
        .invalidate(dailyPlanProvider);
    await tester.pumpAndSettle();
    expect(planRepo.getCalls, getsBefore + 1);

    expect(tester.takeException(), isNull);
    expect(inMainCard(find.text(_t1)), findsOneWidget);

    // Side page: task 1 is not in the list, others are selectable.
    await tester.tap(inSideCard(find.text('İkincil odak seç')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(FocusTaskSelectionPage), findsOneWidget);
    expect(inPage(find.text(_t1)), findsNothing);
    expect(tester.widget<ListTile>(pageTile(_t2)).enabled, isTrue);
    expect(tester.widget<ListTile>(pageTile(_t4)).enabled, isTrue);

    await tester.tap(inPage(find.text(_t4)));
    await tester.pumpAndSettle();
    expect(inSideCard(find.text(_t4)), findsOneWidget);
    expect(inMainCard(find.text(_t1)), findsOneWidget);
    expect(planRepo.bodies.last, {'side_focus_task_id': 4});
  });
}
