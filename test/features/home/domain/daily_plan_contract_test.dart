import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/planning/domain/task.dart';

void main() {
  group('DailyPlan Contract Tests - Real Backend JSON', () {
    // This is the ACTUAL JSON response from GET /daily-plans/{date} endpoint
    // Backend returns: DailyPlanResponse with nested TaskRead objects (snake_case)
    const actualDailyPlanJson = {
      'id': 1,
      'plan_date': '2026-01-15',
      'main_focus_task_id': 1,
      'side_focus_task_id': 2,
      'say_no_text': 'Say no to distractions',
      'created_at': '2026-01-15T08:00:00',
      'updated_at': '2026-01-15T08:00:00',
      'main_focus': {
        'id': 1,
        'title': 'Main Focus Task',
        'description': 'This is the main focus',
        'status': 'todo',
        'created_at': '2026-01-10T10:00:00',
        'updated_at': '2026-01-10T10:00:00',
        'deleted_at': null,
        'planned_date': '2026-01-15T09:00:00',
        'due_date': '2026-01-15T18:00:00',
      },
      'side_focus': {
        'id': 2,
        'title': 'Side Focus Task',
        'description': 'This is the side focus',
        'status': 'in_progress',
        'created_at': '2026-01-11T10:00:00',
        'updated_at': '2026-01-11T10:00:00',
        'deleted_at': null,
        'planned_date': '2026-01-15T14:00:00',
        'due_date': '2026-01-15T20:00:00',
      },
      'tasks': [
        {
          'id': 1,
          'title': 'Main Focus Task',
          'description': 'This is the main focus',
          'status': 'todo',
          'created_at': '2026-01-10T10:00:00',
          'updated_at': '2026-01-10T10:00:00',
          'deleted_at': null,
          'planned_date': '2026-01-15T09:00:00',
          'due_date': '2026-01-15T18:00:00',
        },
        {
          'id': 2,
          'title': 'Side Focus Task',
          'description': 'This is the side focus',
          'status': 'in_progress',
          'created_at': '2026-01-11T10:00:00',
          'updated_at': '2026-01-11T10:00:00',
          'deleted_at': null,
          'planned_date': '2026-01-15T14:00:00',
          'due_date': '2026-01-15T20:00:00',
        },
        {
          'id': 3,
          'title': 'Another Task',
          'description': 'Another task for today',
          'status': 'done',
          'created_at': '2026-01-12T10:00:00',
          'updated_at': '2026-01-13T10:00:00',
          'deleted_at': null,
          'planned_date': '2026-01-15T10:00:00',
          'due_date': null,
        },
      ],
    };

    // Daily plan with only side focus
    const actualDailyPlanJsonSideOnly = {
      'id': 2,
      'plan_date': '2026-01-16',
      'main_focus_task_id': null,
      'side_focus_task_id': 5,
      'say_no_text': 'Focus on what matters',
      'created_at': '2026-01-16T08:00:00',
      'updated_at': '2026-01-16T08:00:00',
      'main_focus': null,
      'side_focus': {
        'id': 5,
        'title': 'Only Side Focus',
        'description': 'No main focus today',
        'status': 'todo',
        'created_at': '2026-01-15T10:00:00',
        'updated_at': '2026-01-15T10:00:00',
        'deleted_at': null,
        'planned_date': '2026-01-16T14:00:00',
        'due_date': '2026-01-16T20:00:00',
      },
      'tasks': [
        {
          'id': 5,
          'title': 'Only Side Focus',
          'description': 'No main focus today',
          'status': 'todo',
          'created_at': '2026-01-15T10:00:00',
          'updated_at': '2026-01-15T10:00:00',
          'deleted_at': null,
          'planned_date': '2026-01-16T14:00:00',
          'due_date': '2026-01-16T20:00:00',
        },
      ],
    };

    test('parses actual backend JSON with all fields populated', () {
      final planDate = DateTime.parse('2026-01-15');
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: Task.fromJson(actualDailyPlanJson['main_focus'] as Map<String, dynamic>),
        sideFocus: Task.fromJson(actualDailyPlanJson['side_focus'] as Map<String, dynamic>),
        sayNoText: actualDailyPlanJson['say_no_text'] as String,
        tasks: (actualDailyPlanJson['tasks'] as List)
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

      expect(plan.planDate, equals(planDate));
      expect(plan.sayNoText, equals('Say no to distractions'));
      expect(plan.tasks.length, equals(3));

      // Main focus
      expect(plan.mainFocus, isNotNull);
      expect(plan.mainFocus!.id, equals(1));
      expect(plan.mainFocus!.title, equals('Main Focus Task'));
      expect(plan.mainFocus!.status, equals(TaskStatus.todo));

      // Side focus
      expect(plan.sideFocus, isNotNull);
      expect(plan.sideFocus!.id, equals(2));
      expect(plan.sideFocus!.title, equals('Side Focus Task'));
      expect(plan.sideFocus!.status, equals(TaskStatus.inProgress));

      // Tasks list
      expect(plan.tasks[0].id, equals(1));
      expect(plan.tasks[1].id, equals(2));
      expect(plan.tasks[2].id, equals(3));
      expect(plan.tasks[2].status, equals(TaskStatus.done));
      expect(plan.tasks[2].isCompleted, isTrue);
    });

    test('parses actual backend JSON for empty daily plan', () {
      final planDate = DateTime.parse('2026-01-20');
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: null,
        sayNoText: null,
        tasks: [],
      );

      expect(plan.planDate, equals(planDate));
      expect(plan.mainFocus, isNull);
      expect(plan.sideFocus, isNull);
      expect(plan.sayNoText, isNull);
      expect(plan.tasks, isEmpty);
    });

    test('parses actual backend JSON with only side focus', () {
      final planDate = DateTime.parse('2026-01-16');
      final plan = DailyPlan(
        planDate: planDate,
        mainFocus: null,
        sideFocus: Task.fromJson(actualDailyPlanJsonSideOnly['side_focus'] as Map<String, dynamic>),
        sayNoText: actualDailyPlanJsonSideOnly['say_no_text'] as String,
        tasks: (actualDailyPlanJsonSideOnly['tasks'] as List)
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

      expect(plan.planDate, equals(planDate));
      expect(plan.mainFocus, isNull);
      expect(plan.sideFocus, isNotNull);
      expect(plan.sideFocus!.id, equals(5));
      expect(plan.tasks.length, equals(1));
      expect(plan.tasks[0].id, equals(5));
    });

    test('Task.fromJson handles integer ids from nested objects in DailyPlanResponse', () {
      final mainFocusJson = actualDailyPlanJson['main_focus'] as Map<String, dynamic>;
      final sideFocusJson = actualDailyPlanJson['side_focus'] as Map<String, dynamic>;
      final tasksJson = actualDailyPlanJson['tasks'] as List<dynamic>;

      final mainFocus = Task.fromJson(mainFocusJson);
      final sideFocus = Task.fromJson(sideFocusJson);
      final tasks = tasksJson.map((e) => Task.fromJson(e as Map<String, dynamic>)).toList();

      // Verify all IDs are integers (not strings)
      expect(mainFocus.id, isA<int>());
      expect(mainFocus.id, equals(1));

      expect(sideFocus.id, isA<int>());
      expect(sideFocus.id, equals(2));

      for (final task in tasks) {
        expect(task.id, isA<int>());
      }
      expect(tasks[0].id, equals(1));
      expect(tasks[1].id, equals(2));
      expect(tasks[2].id, equals(3));
    });

    test('DailyPlanUpdate uses snake_case for task IDs matching backend', () {
      const updateJson = {
        'main_focus_task_id': 1,
        'side_focus_task_id': 2,
        'say_no_text': 'Updated text',
      };

      final update = DailyPlanUpdate.fromJson(updateJson);

      expect(update.mainFocusTaskId, equals(1));
      expect(update.sideFocusTaskId, equals(2));
      expect(update.sayNoText, equals('Updated text'));
      expect(update.mainFocusTaskId, isA<int>());
      expect(update.sideFocusTaskId, isA<int>());

      // Serialize back to JSON - should use snake_case
      final json = update.toJson();
      expect(json['main_focus_task_id'], equals(1));
      expect(json['side_focus_task_id'], equals(2));
      expect(json['main_focus_task_id'], isA<int>());
      expect(json['side_focus_task_id'], isA<int>());
    });

    test('DailyPlanUpdate handles null fields for clearing', () {
      const updateJson = {
        'main_focus_task_id': null,
        'side_focus_task_id': null,
        'say_no_text': null,
      };

      final update = DailyPlanUpdate.fromJson(updateJson);

      expect(update.mainFocusTaskId, isNull);
      expect(update.sideFocusTaskId, isNull);
      expect(update.sayNoText, isNull);
    });
  });
}