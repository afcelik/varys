import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/projects/domain/project.dart';

import '../../projects/fake_project_repository.dart';

Task _task({int? projectId, DateTime? due}) => Task(
  id: 1,
  title: 'Görev',
  status: TaskStatus.todo,
  createdAt: DateTime(2026, 11, 19),
  updatedAt: DateTime(2026, 11, 19),
  projectId: projectId,
  dueDate: due,
);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR', null));

  group('validateTaskTitle', () {
    test('empty and whitespace-only titles are required', () {
      expect(validateTaskTitle(''), taskTitleRequiredMessage);
      expect(validateTaskTitle('   \n '), taskTitleRequiredMessage);
    });

    test('255 characters pass, 256 fail; surrounding spaces are trimmed first', () {
      expect(validateTaskTitle('a' * 255), isNull);
      expect(validateTaskTitle('  ${'a' * 255}  '), isNull);
      expect(validateTaskTitle('a' * 256), taskTitleTooLongMessage);
    });

    test('an emoji counts as one character (runes, like Python len)', () {
      // 🚀 is 2 UTF-16 code units; 255 of them is 510 units but 255 runes.
      expect(('🚀' * 255).length, 510);
      expect(validateTaskTitle('🚀' * 255), isNull);
      expect(validateTaskTitle('🚀' * 256), taskTitleTooLongMessage);
    });
  });

  group('validateTaskDescription', () {
    test('empty is fine; 2000 pass, 2001 fail; emoji counted as one', () {
      expect(validateTaskDescription(''), isNull);
      expect(validateTaskDescription('b' * 2000), isNull);
      expect(validateTaskDescription('b' * 2001), taskDescriptionTooLongMessage);
      expect(validateTaskDescription('🙂' * 2000), isNull);
      expect(validateTaskDescription('🙂' * 2001), taskDescriptionTooLongMessage);
    });

    test('isTaskFormValid needs both fields valid', () {
      expect(isTaskFormValid(title: 'İş', description: ''), isTrue);
      expect(isTaskFormValid(title: ' ', description: ''), isFalse);
      expect(isTaskFormValid(title: 'İş', description: 'b' * 2001), isFalse);
    });
  });

  group('projectChoices (real GET /projects fixture)', () {
    final projects = projectsFixture();

    test('Projesiz is first; completed projects are not offered', () {
      final choices = projectChoices(projects);
      expect(choices.first, ProjectChoice.none);
      expect(choices.first.id, isNull);
      expect(choices.first.label, 'Projesiz');
      final completed = projects.where((p) => p.status == ProjectStatus.completed).map((p) => p.id);
      expect(completed, isNotEmpty, reason: 'fixture has a completed project');
      expect(choices.map((c) => c.id), isNot(contains(anyOf(completed.toList()))));
    });

    test('active, on hold, someday in that order with Turkish status labels', () {
      final choices = projectChoices(projects).skip(1).toList();
      expect(choices.map((c) => c.id), [1, 2, 3, 4]);
      expect(choices.map((c) => c.statusLabel), ['Aktif', 'Aktif', 'Beklemede', 'İleride']);
      expect(choices.first.label, 'Ev taşıma');
    });

    test('no projects → only Projesiz', () {
      expect(projectChoices(const []), [ProjectChoice.none]);
    });
  });

  group('buildNewTask', () {
    test('trims, empty description becomes null, due keeps only the day, no planned date', () {
      final t = buildNewTask(
        title: '  Yeni iş  ',
        description: '   ',
        projectId: 3,
        dueDate: DateTime(2026, 11, 21, 23, 45),
      );
      expect(t.title, 'Yeni iş');
      expect(t.description, isNull);
      expect(t.projectId, 3);
      expect(t.dueDate, DateTime(2026, 11, 21));
      expect(t.plannedDate, isNull);
      expect(t.status, TaskStatus.todo);
    });

    test('description kept trimmed; no project and no due stay null', () {
      final t = buildNewTask(title: 'İş', description: ' not ');
      expect(t.description, 'not');
      expect(t.projectId, isNull);
      expect(t.dueDate, isNull);
    });
  });

  group('taskMetaLine', () {
    final names = projectNamesById(projectsFixture());

    test('project name and due day, either, or none', () {
      expect(
        taskMetaLine(_task(projectId: 1, due: DateTime(2026, 11, 21)), names),
        'Ev taşıma · 21 Kas',
      );
      expect(taskMetaLine(_task(projectId: 1), names), 'Ev taşıma');
      expect(taskMetaLine(_task(due: DateTime(2026, 1, 3)), names), '3 Oca');
      expect(taskMetaLine(_task(), names), isNull);
    });

    test('a completed project is still named (all statuses mapped)', () {
      expect(names[5], 'Vergi beyannamesi');
      expect(taskMetaLine(_task(projectId: 5), names), 'Vergi beyannamesi');
    });

    test('unknown project id (deleted / not loaded) shows nothing, no crash', () {
      expect(taskMetaLine(_task(projectId: 999), names), isNull);
      expect(taskMetaLine(_task(projectId: 999, due: DateTime(2026, 11, 21)), names), '21 Kas');
      expect(taskMetaLine(_task(projectId: 1), const {}), isNull);
    });
  });

  group('projectChoices keepProjectId (edit form)', () {
    final projects = projectsFixture();

    test("the task's completed project is offered last with 'Tamamlanan'; others stay hidden", () {
      final completed = projects.singleWhere((p) => p.id == 5);
      expect(completed.status, ProjectStatus.completed);
      // A second completed project (copied from the real one) must stay hidden.
      final all = [...projects, completed.copyWith(id: 6, title: 'Eski iş')];

      final choices = projectChoices(all, keepProjectId: 5);
      expect(choices.map((c) => c.id), [null, 1, 2, 3, 4, 5]);
      expect(choices.last.label, 'Vergi beyannamesi');
      expect(choices.last.statusLabel, 'Tamamlanan');
      expect(projectChoices(all, keepProjectId: 6).map((c) => c.id), [null, 1, 2, 3, 4, 6]);
    });

    test('a non-completed or unknown keepProjectId changes nothing', () {
      expect(projectChoices(projects, keepProjectId: 1), projectChoices(projects));
      expect(projectChoices(projects, keepProjectId: 999), projectChoices(projects));
    });
  });

  group('computeTaskChanges', () {
    final original = Task(
      id: 7,
      title: 'Giriş ekranı',
      description: 'Form',
      status: TaskStatus.todo,
      createdAt: DateTime(2026, 11, 19),
      updatedAt: DateTime(2026, 11, 19),
      projectId: 1,
      dueDate: DateTime(2026, 11, 21),
      plannedDate: DateTime(2026, 11, 19),
    );

    TaskFormValues form({
      String title = 'Giriş ekranı',
      String description = 'Form',
      int? projectId = 1,
      bool projectResolved = true,
      DateTime? due,
      DateTime? planned,
      bool clearDue = false,
      bool clearPlanned = false,
    }) => TaskFormValues(
      title: title,
      description: description,
      projectId: projectId,
      projectResolved: projectResolved,
      dueDate: clearDue ? null : (due ?? DateTime(2026, 11, 21)),
      plannedDate: clearPlanned ? null : (planned ?? DateTime(2026, 11, 19)),
    );

    test('same values → isEmpty, every field unset', () {
      final c = computeTaskChanges(original, form());
      expect(c.isEmpty, isTrue);
      expect(c, const TaskChanges());
    });

    test('title: trimmed set; trimmed-equal is no change', () {
      expect(computeTaskChanges(original, form(title: '  Yeni  ')).title, 'Yeni');
      expect(computeTaskChanges(original, form(title: '  Giriş ekranı ')).isEmpty, isTrue);
    });

    test('whitespace-only title is invalid (form cannot be saved)', () {
      expect(isTaskFormValid(title: '   ', description: ''), isFalse);
    });

    test('description: set (trimmed), clear when emptied, unset when equal', () {
      expect(
        computeTaskChanges(original, form(description: ' Yeni not ')).description,
        const PlanField<String>.set('Yeni not'),
      );
      expect(
        computeTaskChanges(original, form(description: '   ')).description,
        const PlanField<String>.clear(),
      );
      expect(computeTaskChanges(original, form(description: ' Form ')).description.isUnset, isTrue);
    });

    test('description: null and empty are equal (no change either way)', () {
      final noDesc = original.copyWith(description: null);
      expect(computeTaskChanges(noDesc, form(description: '')).isEmpty, isTrue);
      final emptyDesc = original.copyWith(description: '');
      expect(computeTaskChanges(emptyDesc, form(description: '  ')).isEmpty, isTrue);
      expect(
        computeTaskChanges(noDesc, form(description: 'Not')).description,
        const PlanField<String>.set('Not'),
      );
    });

    test('project: set, clear, unset', () {
      expect(
        computeTaskChanges(original, form(projectId: 3)).projectId,
        const PlanField<int>.set(3),
      );
      expect(
        computeTaskChanges(original, form(projectId: null)).projectId,
        const PlanField<int>.clear(),
      );
      expect(computeTaskChanges(original, form(projectId: 1)).projectId.isUnset, isTrue);
      final noProject = original.copyWith(projectId: null);
      expect(
        computeTaskChanges(noProject, form(projectId: 2)).projectId,
        const PlanField<int>.set(2),
      );
    });

    test('project not resolved (list not loaded) → always unset', () {
      final c = computeTaskChanges(original, form(projectId: null, projectResolved: false));
      expect(c.projectId.isUnset, isTrue);
      expect(c.isEmpty, isTrue);
    });

    test('due date: set (day only), clear, unset', () {
      expect(
        computeTaskChanges(original, form(due: DateTime(2026, 12, 2, 18, 30))).dueDate,
        PlanField<DateTime>.set(DateTime(2026, 12, 2)),
      );
      expect(
        computeTaskChanges(original, form(clearDue: true)).dueDate,
        const PlanField<DateTime>.clear(),
      );
      expect(computeTaskChanges(original, form()).dueDate.isUnset, isTrue);
    });

    test('planned date: set (day only), clear, unset', () {
      expect(
        computeTaskChanges(original, form(planned: DateTime(2026, 11, 20))).plannedDate,
        PlanField<DateTime>.set(DateTime(2026, 11, 20)),
      );
      expect(
        computeTaskChanges(original, form(clearPlanned: true)).plannedDate,
        const PlanField<DateTime>.clear(),
      );
      final unplanned = original.copyWith(plannedDate: null);
      expect(computeTaskChanges(unplanned, form(clearPlanned: true)).plannedDate.isUnset, isTrue);
    });

    test('same day at a different time is NO change (time part ignored)', () {
      final timed = original.copyWith(
        dueDate: DateTime(2026, 11, 21, 9, 15),
        plannedDate: DateTime(2026, 11, 19, 23, 59),
      );
      final c = computeTaskChanges(
        timed,
        form(due: DateTime(2026, 11, 21, 18), planned: DateTime(2026, 11, 19)),
      );
      expect(c.isEmpty, isTrue);
    });

    test('several changes at once carry only the changed fields', () {
      final c = computeTaskChanges(
        original,
        form(title: 'Yeni', projectId: null, clearPlanned: true),
      );
      expect(
        c,
        const TaskChanges(
          title: 'Yeni',
          projectId: PlanField.clear(),
          plannedDate: PlanField.clear(),
        ),
      );
    });
  });

  group('Eisenhower flags in the form helpers', () {
    Task flagged({bool important = false, bool urgent = false}) =>
        _task().copyWith(isImportant: important, isUrgent: urgent);

    TaskFormValues values({bool? important, bool? urgent}) => TaskFormValues(
      title: 'Görev',
      description: '',
      projectId: null,
      isImportant: important,
      isUrgent: urgent,
    );

    test('buildNewTask: flags default to false and carry given values', () {
      final plain = buildNewTask(title: 'A', description: '');
      expect((plain.isImportant, plain.isUrgent), (false, false));
      final both = buildNewTask(title: 'A', description: '', isImportant: true, isUrgent: true);
      expect((both.isImportant, both.isUrgent), (true, true));
    });

    test('same flags → no change, TaskChanges is empty', () {
      final changes = computeTaskChanges(
        flagged(important: true),
        values(important: true, urgent: false),
      );
      expect(changes.isImportant, isNull);
      expect(changes.isUrgent, isNull);
      expect(changes.isEmpty, isTrue);
    });

    test('only urgent switched on → only isUrgent set', () {
      final changes = computeTaskChanges(
        flagged(important: true),
        values(important: true, urgent: true),
      );
      expect(changes, const TaskChanges(isUrgent: true));
      expect(changes.isEmpty, isFalse);
    });

    test('important switched off → isImportant false (sent), urgent untouched', () {
      final changes = computeTaskChanges(
        flagged(important: true, urgent: true),
        values(important: false, urgent: true),
      );
      expect(changes, const TaskChanges(isImportant: false));
      expect(changes.isEmpty, isFalse);
    });

    test('a form without the flags (null) never sends them, even for flagged tasks', () {
      final changes = computeTaskChanges(flagged(important: true, urgent: true), values());
      expect(changes.isImportant, isNull);
      expect(changes.isUrgent, isNull);
      expect(changes.isEmpty, isTrue);
    });

    test('TaskChanges equality and hashCode include the flags', () {
      expect(const TaskChanges(isUrgent: true), isNot(const TaskChanges(isUrgent: false)));
      expect(const TaskChanges(isUrgent: true), isNot(const TaskChanges(isImportant: true)));
      expect(
        const TaskChanges(isImportant: true).hashCode,
        const TaskChanges(isImportant: true).hashCode,
      );
      expect(const TaskChanges(isImportant: false).isEmpty, isFalse);
    });
  });
}
