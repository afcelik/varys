import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';

void main() {
  /// Real backend project (project_created.json): title "Yeni proje",
  /// description "Açıklama metni", active, 2026-11-01 .. 2026-12-15.
  late Project original;

  setUpAll(() {
    original = Project.fromJson(
      jsonDecode(File('test/fixtures/project_created.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  group('validateProjectTitle', () {
    test('empty or whitespace-only -> required', () {
      expect(validateProjectTitle(''), projectTitleRequiredMessage);
      expect(validateProjectTitle('   \n\t'), projectTitleRequiredMessage);
    });

    test('1 and 255 characters (after trim) are valid; 256 is too long', () {
      expect(validateProjectTitle('a'), isNull);
      expect(validateProjectTitle('  ${'a' * 255}  '), isNull);
      expect(validateProjectTitle('a' * 256), projectTitleTooLongMessage);
    });

    test('emoji count as one character each, as the backend counts them', () {
      // '🚀' is two UTF-16 units but one code point.
      expect('🚀' * 255, hasLength(510));
      expect(validateProjectTitle('🚀' * 255), isNull);
      expect(validateProjectTitle('🚀' * 256), projectTitleTooLongMessage);
      expect(validateProjectTitle('ğüşİöç' * 42 + 'abc'), isNull); // 255 Turkish chars
    });
  });

  group('validateProjectDescription', () {
    test('empty is valid; 2000 (after trim) valid; 2001 too long', () {
      expect(validateProjectDescription(''), isNull);
      expect(validateProjectDescription(' ${'x' * 2000} '), isNull);
      expect(validateProjectDescription('x' * 2001), projectDescriptionTooLongMessage);
    });

    test('emoji count as one character', () {
      expect(validateProjectDescription('😀' * 2000), isNull);
      expect(validateProjectDescription('😀' * 2001), projectDescriptionTooLongMessage);
    });
  });

  group('validateProjectDates', () {
    test('either absent -> valid', () {
      expect(validateProjectDates(null, null), isNull);
      expect(validateProjectDates(DateTime(2026, 5, 1), null), isNull);
      expect(validateProjectDates(null, DateTime(2026, 5, 1)), isNull);
    });

    test('same day valid (time of day ignored); target one day before start invalid', () {
      expect(validateProjectDates(DateTime(2026, 5, 1, 18), DateTime(2026, 5, 1, 6)), isNull);
      expect(validateProjectDates(DateTime(2026, 5, 1), DateTime(2026, 5, 2)), isNull);
      expect(
        validateProjectDates(DateTime(2026, 5, 2), DateTime(2026, 5, 1)),
        projectDatesOrderMessage,
      );
    });

    test('isProjectFormValid combines all three rules', () {
      expect(isProjectFormValid(title: 'P', description: ''), isTrue);
      expect(isProjectFormValid(title: ' ', description: ''), isFalse);
      expect(isProjectFormValid(title: 'P', description: 'x' * 2001), isFalse);
      expect(
        isProjectFormValid(
          title: 'P',
          description: '',
          startDate: DateTime(2026, 5, 2),
          targetDate: DateTime(2026, 5, 1),
        ),
        isFalse,
      );
    });
  });

  group('canChooseActive / defaultNewProjectStatus', () {
    const free = ProjectLimits(maxActive: 3, activeCount: 2);
    const full = ProjectLimits(maxActive: 3, activeCount: 3);

    test('new project: allowed only with a free slot', () {
      expect(canChooseActive(free), isTrue);
      expect(canChooseActive(full), isFalse);
      expect(canChooseActive(const ProjectLimits(maxActive: 3, activeCount: 4)), isFalse);
    });

    test('editing a project that is already active: allowed even when full', () {
      expect(canChooseActive(full, editing: original), isTrue);
    });

    test('editing a non-active project: follows the limit', () {
      for (final status in [ProjectStatus.onHold, ProjectStatus.someday, ProjectStatus.completed]) {
        final p = original.copyWith(status: status);
        expect(canChooseActive(full, editing: p), isFalse, reason: '$status');
        expect(canChooseActive(free, editing: p), isTrue, reason: '$status');
      }
    });

    test('default status: active with a free slot, on hold when full', () {
      expect(defaultNewProjectStatus(free), ProjectStatus.active);
      expect(defaultNewProjectStatus(full), ProjectStatus.onHold);
    });
  });

  group('computeProjectChanges', () {
    ProjectChanges diff({
      String? title,
      String? description,
      ProjectStatus? status,
      DateTime? startDate,
      DateTime? targetDate,
      bool keepStart = true,
      bool keepTarget = true,
    }) => computeProjectChanges(
      original,
      title: title ?? original.title,
      description: description ?? original.description ?? '',
      status: status ?? original.status,
      startDate: keepStart ? (startDate ?? original.startDate) : startDate,
      targetDate: keepTarget ? (targetDate ?? original.targetDate) : targetDate,
    );

    test('nothing changed -> isEmpty (no request)', () {
      final c = diff();
      expect(c.isEmpty, isTrue);
      expect(c.toBody(), isEmpty);
    });

    test('whitespace-only differences in title/description are not changes', () {
      expect(diff(title: '  Yeni proje  ', description: ' Açıklama metni\n').isEmpty, isTrue);
    });

    test('same day with another time of day is not a change', () {
      expect(diff(startDate: DateTime(2026, 11, 1, 13, 45)).isEmpty, isTrue);
    });

    test('title change -> set (trimmed)', () {
      final c = diff(title: '  Başka ad ');
      expect(c, const ProjectChanges(title: PlanField.set('Başka ad')));
      expect(c.toBody(), {'title': 'Başka ad'});
    });

    test('status change -> set with wire value', () {
      final c = diff(status: ProjectStatus.someday);
      expect(c, const ProjectChanges(status: PlanField.set(ProjectStatus.someday)));
      expect(c.toBody(), {'status': 'someday'});
    });

    test('description changed -> set; emptied -> clear (explicit null)', () {
      expect(diff(description: 'Yeni').description, const PlanField<String>.set('Yeni'));
      final cleared = diff(description: '   ');
      expect(cleared, const ProjectChanges(description: PlanField.clear()));
      expect(cleared.toBody(), {'description': null});
      expect(cleared.toBody().containsKey('description'), isTrue);
    });

    test('description added to a project that had none -> set', () {
      final none = original.copyWith(description: null);
      final c = computeProjectChanges(
        none,
        title: none.title,
        description: 'Not',
        status: none.status,
        startDate: none.startDate,
        targetDate: none.targetDate,
      );
      expect(c, const ProjectChanges(description: PlanField.set('Not')));
      final unchanged = computeProjectChanges(
        none,
        title: none.title,
        description: '  ',
        status: none.status,
        startDate: none.startDate,
        targetDate: none.targetDate,
      );
      expect(unchanged.isEmpty, isTrue);
    });

    test('date changed -> set as YYYY-MM-DD; removed -> clear (explicit null)', () {
      final moved = diff(targetDate: DateTime(2027, 1, 31));
      expect(moved.targetDate, PlanField<DateTime>.set(DateTime(2027, 1, 31)));
      expect(moved.toBody(), {'target_date': '2027-01-31'});

      final cleared = diff(keepStart: false, keepTarget: false);
      expect(cleared.startDate, const PlanField<DateTime>.clear());
      expect(cleared.targetDate, const PlanField<DateTime>.clear());
      expect(cleared.toBody(), {'start_date': null, 'target_date': null});
    });

    test('date added where there was none -> set', () {
      final none = original.copyWith(startDate: null);
      final c = computeProjectChanges(
        none,
        title: none.title,
        description: none.description ?? '',
        status: none.status,
        startDate: DateTime(2026, 10, 1),
        targetDate: none.targetDate,
      );
      expect(c, ProjectChanges(startDate: PlanField.set(DateTime(2026, 10, 1))));
    });

    test('several fields at once: body holds exactly those, JSON-encodable', () {
      final c = diff(
        title: 'X',
        status: ProjectStatus.completed,
        description: '',
        keepTarget: false,
      );
      final body = c.toBody();
      expect(body, {'title': 'X', 'status': 'completed', 'description': null, 'target_date': null});
      expect(jsonDecode(jsonEncode(body)), body);
    });
  });

  group('ProjectDraft', () {
    test('body has every field, dates as YYYY-MM-DD, empty description null', () {
      final body = ProjectDraft(
        title: ' P ',
        description: '',
        status: ProjectStatus.onHold,
        targetDate: DateTime(2026, 2, 3, 22),
      ).toBody();
      expect(body, {
        'title': 'P',
        'description': null,
        'status': 'on_hold',
        'start_date': null,
        'target_date': '2026-02-03',
      });
      expect(jsonDecode(jsonEncode(body)), body);
    });
  });

  test('status labels are the Turkish names in section order', () {
    expect(projectStatusLabels.values, ['Aktif', 'Beklemede', 'İleride', 'Tamamlanan']);
  });
}
