// Contract tests for Project / ProjectLimits against real backend JSON
// (test/fixtures/projects_list.json, projects_limits.json), produced by the
// real FastAPI app: GET /projects (one deleted project created and deleted
// before the call) and GET /projects/limits.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/projects/domain/project.dart';

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
}
