// Contract tests for Project / ProjectLimits against real backend JSON
// (test/fixtures/projects_list.json, projects_limits.json), produced by the
// real FastAPI app: GET /projects (one deleted project created and deleted
// before the call) and GET /projects/limits. The mutation fixtures
// (project_created/updated, project_limit_409, project_*_422) come from the
// same app: POST 201, PATCH 200 (title/status set, description/target
// cleared), POST 409 with the limit full, POST and PATCH 422 with
// target_date before start_date.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  late List<Map<String, dynamic>> raw;
  late List<Project> projects;

  setUpAll(() {
    raw = (_read('projects_list.json') as List).cast<Map<String, dynamic>>();
    projects = raw.map(Project.fromJson).toList();
  });

  Project byId(int id) => projects.firstWhere((p) => p.id == id);

  group('Project fromJson (GET /projects)', () {
    test('parses every project; the deleted project (id 6) is not returned', () {
      expect(projects.map((p) => p.id), [1, 2, 3, 4, 5]);
      expect(projects.any((p) => p.title == 'Silinecek proje'), isFalse);
    });

    test('all four statuses map to ProjectStatus', () {
      expect(projects.map((p) => p.status).toSet(), ProjectStatus.values.toSet());
      expect(byId(1).status, ProjectStatus.active);
      expect(byId(2).status, ProjectStatus.active);
      expect(byId(3).status, ProjectStatus.onHold);
      expect(byId(4).status, ProjectStatus.someday);
      expect(byId(5).status, ProjectStatus.completed);
    });

    test('filled project: every field, 1/4 done -> 25%', () {
      final p = byId(1);
      expect(p.title, 'Ev taşıma');
      expect(p.description, 'Yeni eve geçiş işleri');
      expect(p.startDate, DateTime(2026, 11, 1));
      expect(p.targetDate, DateTime(2026, 11, 20));
      expect(p.createdAt, DateTime.parse('2026-11-19T03:21:52'));
      expect(p.updatedAt, DateTime.parse('2026-11-19T03:21:52'));
      expect(p.totalTasks, 4);
      expect(p.doneTasks, 1);
      expect(p.progressPercent, 25);
    });

    test('project without tasks: progress null, null description and dates', () {
      final p = byId(2);
      expect(raw[1]['progress_percent'], isNull);
      expect(p.description, isNull);
      expect(p.startDate, isNull);
      expect(p.targetDate, isNull);
      expect(p.totalTasks, 0);
      expect(p.doneTasks, 0);
      expect(p.progressPercent, isNull);
    });

    test('all tasks done -> 100%', () {
      final p = byId(5);
      expect(p.totalTasks, 2);
      expect(p.doneTasks, 2);
      expect(p.progressPercent, 100);
    });

    test('only one of the dates set', () {
      final p = byId(3);
      expect(p.startDate, isNull);
      expect(p.targetDate, DateTime(2027, 3, 15));
    });

    test('DATE fields are local calendar days, never instants', () {
      for (final p in projects) {
        for (final d in [p.startDate, p.targetDate].whereType<DateTime>()) {
          expect(d.isUtc, isFalse);
          expect((d.hour, d.minute, d.second), (0, 0, 0));
        }
      }
    });

    for (final value in ['2026-11-20T00:00:00Z', '2026-11-20T00:00:00+03:00']) {
      test('a time zone suffix "$value" does not shift the day', () {
        final p = Project.fromJson({...raw[0], 'target_date': value});
        expect(p.targetDate, DateTime(2026, 11, 20));
        expect(p.targetDate!.isUtc, isFalse);
      });
    }

    test('unknown status fails to parse', () {
      expect(() => Project.fromJson({...raw[0], 'status': 'archived'}), throwsArgumentError);
    });

    test('toJson uses backend values and round-trips', () {
      for (final p in projects) {
        final json = p.toJson();
        expect(json['status'], raw.firstWhere((r) => r['id'] == p.id)['status']);
        expect(json.containsKey('progress_percent'), isTrue);
        expect(Project.fromJson(json), p);
      }
    });
  });

  group('ProjectLimits fromJson (GET /projects/limits)', () {
    test('parses max_active and active_count', () {
      final limits = ProjectLimits.fromJson(_read('projects_limits.json') as Map<String, dynamic>);
      expect(limits.maxActive, 3);
      expect(limits.activeCount, 2);
      expect(limits.activeCount, projects.where((p) => p.status == ProjectStatus.active).length);
      expect(ProjectLimits.fromJson(limits.toJson()), limits);
      expect(limits.toJson(), {'max_active': 3, 'active_count': 2});
    });
  });

  group('mutation responses', () {
    test('POST /projects 201: every field; new project has no tasks -> progress null', () {
      final raw = _read('project_created.json') as Map<String, dynamic>;
      final p = Project.fromJson(raw);
      expect(p.id, 1);
      expect(p.title, 'Yeni proje');
      expect(p.description, 'Açıklama metni');
      expect(p.status, ProjectStatus.active);
      expect(p.startDate, DateTime(2026, 11, 1));
      expect(p.targetDate, DateTime(2026, 12, 15));
      expect((p.totalTasks, p.doneTasks), (0, 0));
      expect(raw.containsKey('progress_percent'), isTrue);
      expect(p.progressPercent, isNull);
      expect(Project.fromJson(p.toJson()), p);
    });

    test('PATCH 200: cleared fields come back as explicit null, set ones updated', () {
      final raw = _read('project_updated.json') as Map<String, dynamic>;
      final p = Project.fromJson(raw);
      expect(p.title, 'Yeni proje (güncel)');
      expect(p.status, ProjectStatus.onHold);
      expect(raw.containsKey('description'), isTrue);
      expect(p.description, isNull);
      expect(raw.containsKey('target_date'), isTrue);
      expect(p.targetDate, isNull);
      expect(p.startDate, DateTime(2026, 11, 1));
    });

    test('409 body is exactly the fixed limit code', () {
      expect(_read('project_limit_409.json'), {'detail': 'active_project_limit_reached'});
    });

    test('POST 422 (target before start) is a pydantic error list', () {
      final body = _read('project_invalid_dates_422.json') as Map<String, dynamic>;
      final detail = body['detail'] as List;
      expect(detail, hasLength(1));
      expect((detail.single as Map)['type'], 'value_error');
      expect((detail.single as Map)['msg'], contains('target_date cannot be before start_date'));
    });

    test('PATCH 422 (merged dates invalid) is a plain string detail', () {
      expect(_read('project_update_422.json'), {
        'detail': 'target_date cannot be before start_date',
      });
    });

    test('status wire values equal the JSON values', () {
      for (final status in ProjectStatus.values) {
        final json = Project.fromJson({
          ...(_read('project_created.json') as Map<String, dynamic>),
          'status': status.apiValue,
        }).toJson();
        expect(json['status'], status.apiValue);
      }
      expect(projectStatusLabels.keys, ProjectStatus.values);
    });
  });
}
