import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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
}
