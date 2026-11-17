// Integration: real HomeScreen + real DailyPlanNotifier / TaskListNotifier;
// only the repositories are mocked. Pull a Planning task into today via the
// "Planlamadan ekle" sheet.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/add_from_planning_sheet.dart';
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

Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
        as Map<String, dynamic>;

/// Real backend JSON: main focus id 3, 5 tasks (2 done) planned for 2026-11-01.
DailyPlan _fixturePlan() {
  final json = _fixture();
  return DailyPlan(
    planDate: _planDay,
    mainFocus: Task.fromJson(json['main_focus'] as Map<String, dynamic>),
    tasks: (json['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList(),
  );
}

/// Unplanned Planning task, real JSON shape.
Task _unplanned() => Task.fromJson(
  Map<String, dynamic>.from((_fixture()['tasks'] as List).first as Map)
    ..['id'] = 20
    ..['title'] = 'Fatura öde'
    ..['planned_date'] = null,
);

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late DailyPlan plan;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    plan = _fixturePlan();
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
    when(() => taskRepo.getTasks()).thenAnswer((_) async => Right([...plan.tasks, _unplanned()]));
    when(
      () => taskRepo.planForDay(20, any()),
    ).thenAnswer((_) async => Right(_unplanned().copyWith(plannedDate: _planDay)));
  });

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(790, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
          taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        ],
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inCard(Finder f) => find.descendant(of: find.byType(DailyTasksCard), matching: f);
  Finder inMainCard(Finder f) => find.descendant(of: find.byType(MainFocusCard), matching: f);

  testWidgets(
    'pick a Planning task -> Ekle -> it is in "Bugün Yapılacaklar", counter updated, focus untouched',
    (tester) async {
      await pumpHome(tester);
      expect(inCard(find.text('2/5')), findsOneWidget);
      expect(inCard(find.text('Fatura öde')), findsNothing);
      expect(inMainCard(find.text('Ana odak görevi')), findsOneWidget);

      await tester.tap(inCard(find.byTooltip(AddFromPlanningSheet.title)));
      await tester.pumpAndSettle();

      final sheetRow = find.descendant(
        of: find.byType(AddFromPlanningSheet),
        matching: find.widgetWithText(CheckboxListTile, 'Fatura öde'),
      );
      // Only the unplanned task is offered (the 5 plan tasks are already today).
      expect(
        find.descendant(
          of: find.byType(AddFromPlanningSheet),
          matching: find.byType(CheckboxListTile),
        ),
        findsOneWidget,
      );
      await tester.tap(sheetRow);
      await tester.pump();
      await tester.tap(find.text('Ekle (1)'));
      await tester.pumpAndSettle();

      expect(find.byType(AddFromPlanningSheet), findsNothing);
      verify(() => taskRepo.planForDay(20, _planDay)).called(1);
      expect(inCard(find.text('Fatura öde')), findsOneWidget);
      expect(inCard(find.text('2/6')), findsOneWidget);
      // Focus card unchanged; plan not reloaded from the server.
      expect(inMainCard(find.text('Ana odak görevi')), findsOneWidget);
      verify(() => planRepo.getPlan(any())).called(1);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
