import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/home/presentation/widgets/daily_plan_state_widgets.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

final _planDay = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _planDay;
}

/// Plan built from real backend JSON (test/fixtures/daily_plan_with_tasks.json).
DailyPlan _fixturePlan() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  return DailyPlan(
    planDate: _planDay,
    mainFocus: Task.fromJson(json['main_focus'] as Map<String, dynamic>),
    sideFocus: null,
    sayNoText: json['say_no_text'] as String?,
    tasks: (json['tasks'] as List)
        .map((t) => Task.fromJson(t as Map<String, dynamic>))
        .toList(),
  );
}

void main() {
  late _MockTaskRepository taskRepo;
  late _MockDailyPlanRepository planRepo;
  late DailyPlan initialPlan;
  late Task focusTask;
  late Task focusTaskDone;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    taskRepo = _MockTaskRepository();
    planRepo = _MockDailyPlanRepository();
    initialPlan = _fixturePlan();
    focusTask = initialPlan.mainFocus!; // id 3, "Ana odak görevi", todo
    focusTaskDone = focusTask.copyWith(status: TaskStatus.done);

    // Planning list: the focus task (not necessarily planned for today) + one other
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([focusTask]));
    when(() => taskRepo.updateTaskStatus(focusTask.id, TaskStatus.done))
        .thenAnswer((_) async => Right(focusTaskDone));
  });

  List<Override> overrides() => [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
      ];

  test('completing the focus task in Planning reloads the daily plan (focus becomes done)', () async {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);

    var plan = initialPlan;
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));

    container.listen(dailyPlanProvider, (_, _) {});
    container.listen(taskListNotifierProvider, (_, _) {});
    await container.read(dailyPlanProvider.future);
    await container.read(taskListNotifierProvider.future);
    expect(container.read(dailyPlanProvider).value!.mainFocus!.status, TaskStatus.todo);

    plan = initialPlan.copyWith(mainFocus: focusTaskDone);
    final result = await container.read(taskListNotifierProvider.notifier).toggleTaskCompletion(focusTask.id);

    expect(result.isRight(), isTrue);
    final reloaded = await container.read(dailyPlanProvider.future);
    expect(reloaded.mainFocus!.status, TaskStatus.done);
    verify(() => planRepo.getPlan(_planDay)).called(2);
  });

  test('a failed Planning toggle does not reload the daily plan', () async {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(initialPlan));
    when(() => taskRepo.updateTaskStatus(focusTask.id, TaskStatus.done))
        .thenAnswer((_) async => const Left(NetworkFailure('Sunucuya bağlanılamıyor')));

    container.listen(dailyPlanProvider, (_, _) {});
    container.listen(taskListNotifierProvider, (_, _) {});
    await container.read(dailyPlanProvider.future);
    await container.read(taskListNotifierProvider.future);

    final result = await container.read(taskListNotifierProvider.notifier).toggleTaskCompletion(focusTask.id);

    expect(result.isLeft(), isTrue);
    expect(container.read(taskListNotifierProvider).value!.tasks.value!.single.status, TaskStatus.todo);
    verify(() => planRepo.getPlan(_planDay)).called(1);
  });

  testWidgets('HomeScreen keeps old data (no skeleton) while the plan reloads, then shows focus as done',
      (tester) async {
    tester.view.physicalSize = const Size(790, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final reload = Completer<Either<Failure, DailyPlan>>();
    var calls = 0;
    when(() => planRepo.getPlan(any())).thenAnswer((_) {
      calls++;
      return calls == 1 ? Future.value(Right(initialPlan)) : reload.future;
    });

    await tester.pumpWidget(ProviderScope(
      overrides: overrides(),
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();

    final mainFocusCard = find.byType(MainFocusCard);
    expect(find.descendant(of: mainFocusCard, matching: find.text('Devam ediyor')), findsOneWidget);

    // Planning tab (kept alive by the shell in the app) completes the focus task
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    container.listen(taskListNotifierProvider, (_, _) {});
    await tester.pump();
    final toggle = container.read(taskListNotifierProvider.notifier).toggleTaskCompletion(focusTask.id);
    await tester.pump();
    await tester.pump();

    // Reload in flight: old rows + focus card stay, no skeleton, no error
    expect(calls, 2);
    expect(find.byType(DailyPlanLoading), findsNothing);
    expect(find.byType(DailyPlanError), findsNothing);
    expect(find.text('İlk görev - yapılacak'), findsOneWidget);
    expect(find.text('Dördüncü görev - yapılacak'), findsOneWidget);
    expect(find.descendant(of: mainFocusCard, matching: find.text('Ana odak görevi')), findsOneWidget);

    reload.complete(Right(initialPlan.copyWith(mainFocus: focusTaskDone)));
    await tester.pumpAndSettle();
    expect((await toggle).isRight(), isTrue);

    expect(find.descendant(of: mainFocusCard, matching: find.text('Tamamlandı')), findsOneWidget);
    expect(find.byType(DailyPlanLoading), findsNothing);
  });
}
