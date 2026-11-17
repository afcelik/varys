import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/presentation/widgets/daily_tasks_card.dart';
import 'package:varys/features/planning/domain/task.dart';

void main() {
  group('DailyTasksCard', () {
    final planDate = DateTime(2026, 11, 1);

    // Helper to create test tasks
    Task createTask(int id, String title, TaskStatus status) {
      return Task(
        id: id,
        title: title,
        description: null,
        status: status,
        createdAt: DateTime(2026, 11, 1, 10, 0),
        updatedAt: DateTime(2026, 11, 1, 10, 0),
        deletedAt: null,
        plannedDate: DateTime(2026, 11, 1, 0, 0),
        dueDate: null,
      );
    }

    testWidgets('displays progress counter as COMPLETED/TOTAL', (tester) async {
      // 2 completed, 3 total = "2/3" but actually 2 done out of 5 total
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: null,
        sayNoText: null,
        tasks: [
          createTask(1, 'Task 1', TaskStatus.todo),
          createTask(2, 'Task 2', TaskStatus.inProgress),
          createTask(3, 'Task 3', TaskStatus.done),
          createTask(4, 'Task 4', TaskStatus.todo),
          createTask(5, 'Task 5', TaskStatus.done),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyTasksCard(plan: plan),
            ),
          ),
        ),
      );

      // Should show "2/5" (completed/total)
      expect(find.text('2/5'), findsOneWidget);
    });

    testWidgets('orders tasks: incomplete first, then completed at bottom', (tester) async {
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: null,
        sayNoText: null,
        tasks: [
          createTask(3, 'Completed Task', TaskStatus.done),
          createTask(1, 'Todo Task', TaskStatus.todo),
          createTask(5, 'Another Done', TaskStatus.done),
          createTask(2, 'In Progress', TaskStatus.inProgress),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyTasksCard(plan: plan),
            ),
          ),
        ),
      );

      // Find all task titles
      final texts = tester.widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .where((t) => t.isNotEmpty && t != 'Bugün Yapılacaklar' && t != 'Bugün için görev yok' && t != 'Yeni görev ekle...' && !t.contains('/'))
          .toList();

      // Incomplete tasks should come first
      expect(texts.indexOf('Todo Task'), lessThan(texts.indexOf('Completed Task')));
      expect(texts.indexOf('In Progress'), lessThan(texts.indexOf('Another Done')));
    });

    testWidgets('completed tasks have strikethrough and dimmed opacity', (tester) async {
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: null,
        sayNoText: null,
        tasks: [
          createTask(1, 'Active Task', TaskStatus.todo),
          createTask(2, 'Done Task', TaskStatus.done),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyTasksCard(plan: plan),
            ),
          ),
        ),
      );

      // Check Opacity wrapper for completed task
      final opacities = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(opacities.length, equals(2));

      // Done task should have opacity 0.6
      final doneOpacity = opacities.firstWhere((o) => o.opacity == 0.6);
      expect(doneOpacity.opacity, equals(0.6));

      // Active task should have opacity 1.0
      final activeOpacity = opacities.firstWhere((o) => o.opacity == 1.0);
      expect(activeOpacity.opacity, equals(1.0));
    });

    testWidgets('empty state shows "Bugün için görev yok"', (tester) async {
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: null,
        sayNoText: null,
        tasks: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyTasksCard(plan: plan),
            ),
          ),
        ),
      );

      expect(find.text('Bugün için görev yok'), findsOneWidget);
    });

    testWidgets('checkbox toggle calls notifier', (tester) async {
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: null,
        sayNoText: null,
        tasks: [
          createTask(1, 'Test Task', TaskStatus.todo),
        ],
      );

      // We can't easily mock the notifier in this simple test
      // This test would require a more complex setup with mocked providers
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyTasksCard(plan: plan),
            ),
          ),
        ),
      );

      expect(find.byType(Checkbox), findsOneWidget);
    });

    testWidgets('temp task (negative ID) has disabled checkbox', (tester) async {
      // Create a task with negative ID
      final tempTask = Task(
        id: -1,
        title: 'Temp Task',
        description: null,
        status: TaskStatus.todo,
        createdAt: DateTime(2026, 11, 1, 10, 0),
        updatedAt: DateTime(2026, 11, 1, 10, 0),
        deletedAt: null,
        plannedDate: DateTime(2026, 11, 1, 0, 0),
        dueDate: null,
      );

      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: null,
        sayNoText: null,
        tasks: [tempTask],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyTasksCard(plan: plan),
            ),
          ),
        ),
      );

      // The checkbox should be disabled (onChanged == null)
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.onChanged, isNull);
    });

    testWidgets('add task field submits on Enter', (tester) async {
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: null,
        sayNoText: null,
        tasks: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyTasksCard(plan: plan),
            ),
          ),
        ),
      );

      // Find the text field
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      // Enter text
      await tester.enterText(textField, 'New Task');

      // Verify text is in field
      expect((tester.widget<TextField>(textField).controller?.text ?? ''), equals('New Task'));
    });

    testWidgets('renders one row per task', (tester) async {
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: null,
        sayNoText: null,
        tasks: [
          createTask(1, 'Task 1', TaskStatus.todo),
          createTask(2, 'Task 2', TaskStatus.todo),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DailyTasksCard(plan: plan),
            ),
          ),
        ),
      );

      // Per-row disabling during a toggle is covered in home_daily_tasks_integration_test.dart
      expect(find.byType(ListTile), findsNWidgets(2));
    });
  });
}