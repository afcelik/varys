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
import 'package:varys/features/home/presentation/widgets/daily_tasks_card.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

final _planDay = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _planDay;
}

/// Real backend JSON; 5 tasks (2 done). Main focus set to task 1 so a Home
/// toggle of that row must also update the focus card.
DailyPlan _fixturePlan() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  final tasks =
      (json['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();
  return DailyPlan(
    planDate: _planDay,
    mainFocus: tasks.first, // id 1 "İlk görev - yapılacak", todo
    sideFocus: null,
    sayNoText: null,
    tasks: tasks,
  );
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late DailyPlan plan;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskStatus.todo);
    registerFallbackValue(_fixturePlan().tasks.first);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    plan = _fixturePlan();
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(790, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
      ],
      child: const MaterialApp(home: HomeScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Finder inTasksCard(Finder f) => find.descendant(of: find.byType(DailyTasksCard), matching: f);
  Finder addField() => inTasksCard(find.byType(TextField));
  Finder rowCheckbox(String title) => find.descendant(
      of: find.widgetWithText(ListTile, title), matching: find.byType(Checkbox));
  Finder inMainCard(String text) =>
      find.descendant(of: find.byType(MainFocusCard), matching: find.text(text));

  void expectNoRawErrors() {
    expect(find.textContaining('Instance of'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text('Plan yüklenemedi'), findsNothing);
  }

  Task serverTask(int id, String title, TaskStatus status) => Task(
        id: id,
        title: title,
        description: null,
        status: status,
        createdAt: DateTime(2026, 11, 1, 15),
        updatedAt: DateTime(2026, 11, 1, 15),
        deletedAt: null,
        plannedDate: DateTime(2026, 11, 1),
        dueDate: null,
      );

  group('Adding a task', () {
    testWidgets('temp row (disabled) appears at once, replaced by server task; counter updates',
        (tester) async {
      final create = Completer<Either<Failure, Task>>();
      when(() => taskRepo.createTask(any())).thenAnswer((_) => create.future);
      await pumpHome(tester);
      expect(inTasksCard(find.text('2/5')), findsOneWidget);

      await tester.enterText(addField(), 'Yeni görev');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Optimistic: row visible, checkbox disabled, field cleared, counter 2/6
      expect(tester.widget<Checkbox>(rowCheckbox('Yeni görev')).onChanged, isNull);
      expect(tester.widget<TextField>(addField()).controller!.text, isEmpty);
      expect(inTasksCard(find.text('2/6')), findsOneWidget);

      final sent = verify(() => taskRepo.createTask(captureAny())).captured.single as Task;
      expect(sent.title, 'Yeni görev');
      expect(sent.id, isNegative);
      expect(sent.plannedDate, DateTime(2026, 11, 1));

      create.complete(Right(serverTask(10, 'Yeni görev', TaskStatus.todo)));
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(rowCheckbox('Yeni görev')).onChanged, isNotNull);
      expect(inTasksCard(find.text('2/6')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('failed add: temp row removed, typed text restored, Turkish snackbar',
        (tester) async {
      when(() => taskRepo.createTask(any()))
          .thenAnswer((_) async => const Left(NetworkFailure('connection refused')));
      await pumpHome(tester);

      await tester.enterText(addField(), 'Kaybolmasın');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Kaybolmasın'), findsNothing);
      expect(tester.widget<TextField>(addField()).controller!.text, 'Kaybolmasın');
      expect(find.widgetWithText(SnackBar, 'Bağlantı hatası'), findsOneWidget);
      expect(inTasksCard(find.text('2/5')), findsOneWidget);
      expectNoRawErrors();
    });

    testWidgets('whitespace-only input sends no request and adds no row', (tester) async {
      await pumpHome(tester);

      await tester.enterText(addField(), '   ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      verifyNever(() => taskRepo.createTask(any()));
      expect(inTasksCard(find.byType(ListTile)), findsNWidgets(5));
      expect(inTasksCard(find.text('2/5')), findsOneWidget);
    });
  });

  group('Completing a task', () {
    testWidgets('checkbox completes row: counter, strikethrough, row moves down, focus card syncs',
        (tester) async {
      const title = 'İlk görev - yapılacak';
      when(() => taskRepo.updateTaskStatus(1, TaskStatus.done))
          .thenAnswer((_) async => Right(plan.tasks.first.copyWith(status: TaskStatus.done)));
      await pumpHome(tester);
      expect(inMainCard('Devam ediyor'), findsOneWidget);
      // Before: first row is above the last incomplete row
      expect(tester.getTopLeft(find.widgetWithText(ListTile, title)).dy,
          lessThan(tester.getTopLeft(find.widgetWithText(ListTile, 'Dördüncü görev - yapılacak')).dy));

      await tester.tap(rowCheckbox(title));
      await tester.pumpAndSettle();

      verify(() => taskRepo.updateTaskStatus(1, TaskStatus.done)).called(1);
      expect(inTasksCard(find.text('3/5')), findsOneWidget);
      expect(tester.widget<Checkbox>(rowCheckbox(title)).value, isTrue);
      final rowText = tester.widget<Text>(
          find.descendant(of: find.widgetWithText(ListTile, title), matching: find.text(title)));
      expect(rowText.style!.decoration, TextDecoration.lineThrough);
      // After: completed row sits below every incomplete row
      expect(tester.getTopLeft(find.widgetWithText(ListTile, title)).dy,
          greaterThan(tester.getTopLeft(find.widgetWithText(ListTile, 'Dördüncü görev - yapılacak')).dy));
      // Focus card shows the same task as done
      expect(inMainCard('Tamamlandı'), findsOneWidget);
    });

    testWidgets('failed toggle rolls back row, counter and focus card; Turkish snackbar',
        (tester) async {
      const title = 'İlk görev - yapılacak';
      when(() => taskRepo.updateTaskStatus(1, TaskStatus.done)).thenAnswer((_) async =>
          const Left(ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500)));
      await pumpHome(tester);

      await tester.tap(rowCheckbox(title));
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(rowCheckbox(title)).value, isFalse);
      expect(inTasksCard(find.text('2/5')), findsOneWidget);
      expect(inMainCard('Devam ediyor'), findsOneWidget);
      expect(find.widgetWithText(SnackBar, 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.'),
          findsOneWidget);
      expectNoRawErrors();
    });

    testWidgets('double tap: checkbox disabled while request in flight, only one request',
        (tester) async {
      const title = 'Dördüncü görev - yapılacak';
      final pending = Completer<Either<Failure, Task>>();
      when(() => taskRepo.updateTaskStatus(4, TaskStatus.done)).thenAnswer((_) => pending.future);
      await pumpHome(tester);

      await tester.tap(rowCheckbox(title));
      await tester.pump();

      expect(tester.widget<Checkbox>(rowCheckbox(title)).onChanged, isNull);
      // Only the toggled row is disabled
      expect(tester.widget<Checkbox>(rowCheckbox('İlk görev - yapılacak')).onChanged, isNotNull);
      await tester.tap(rowCheckbox(title), warnIfMissed: false);
      await tester.pump();
      verify(() => taskRepo.updateTaskStatus(4, TaskStatus.done)).called(1);

      pending.complete(Right(plan.tasks[3].copyWith(status: TaskStatus.done)));
      await tester.pumpAndSettle();
      expect(tester.widget<Checkbox>(rowCheckbox(title)).onChanged, isNotNull);
      verifyNever(() => taskRepo.updateTaskStatus(any(), any())); // no second toggle sent
    });
  });
}
