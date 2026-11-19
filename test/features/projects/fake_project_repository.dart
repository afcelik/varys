import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';
import 'package:varys/features/projects/domain/project_repository.dart';

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// Real GET /projects: ids 1..5; 1 and 2 active, 3 on hold, 4 someday,
/// 5 completed. Progress: 1 -> 25%, 2 -> null (no tasks), 5 -> 100%.
List<Project> projectsFixture() => (_read('projects_list.json') as List)
    .map((e) => Project.fromJson(e as Map<String, dynamic>))
    .toList();

/// Real POST /projects 201 body.
Project createdProjectFixture() =>
    Project.fromJson(_read('project_created.json') as Map<String, dynamic>);

/// In-memory stand-in for the backend behind [ProjectRepository], used by
/// widget, route and integration tests. It behaves like the server: lists
/// come from [server], limits are counted from it (max [maxActive]),
/// activating beyond the limit answers [ActiveProjectLimitFailure], unknown
/// ids answer 404. Every request is recorded. The `on*` hooks replace an
/// answer (e.g. a parked Completer or a forced failure).
class FakeProjectRepository implements ProjectRepository {
  FakeProjectRepository([List<Project>? initial]) : server = initial ?? projectsFixture();

  List<Project> server;
  int maxActive = 3;

  /// When set, limits answer this instead of the count from [server]
  /// (a stale or out-of-band server value).
  ProjectLimits? limitsOverride;

  /// When set, `GET /projects` without a filter (the projects page) waits on it.
  Completer<void>? listGate;

  /// When set, `GET /projects` without a filter answers this failure.
  Failure? listFailure;

  Future<Either<Failure, Project>> Function(ProjectDraft draft)? onCreate;
  Future<Either<Failure, Project>> Function(int id, ProjectChanges changes)? onUpdate;
  Future<Either<Failure, void>> Function(int id)? onDelete;

  int listCalls = 0;
  int activeCalls = 0;
  int limitsCalls = 0;
  final createBodies = <Map<String, dynamic>>[];
  final updateCalls = <(int, Map<String, dynamic>)>[];
  final deleteIds = <int>[];

  int _nextId = 100;

  static const notFound = ServerFailure('Kaynak bulunamadı.', statusCode: 404);

  int get activeCount => server.where((p) => p.status == ProjectStatus.active).length;

  @override
  Future<Either<Failure, List<Project>>> getProjects({ProjectStatus? status}) async {
    if (status != null) {
      activeCalls++;
      return Right(server.where((p) => p.status == status).toList());
    }
    listCalls++;
    final gate = listGate;
    if (gate != null) await gate.future;
    final failure = listFailure;
    if (failure != null) return Left(failure);
    return Right(List.of(server));
  }

  @override
  Future<Either<Failure, ProjectLimits>> getLimits() async {
    limitsCalls++;
    return Right(limitsOverride ?? ProjectLimits(maxActive: maxActive, activeCount: activeCount));
  }

  @override
  Future<Either<Failure, Project>> createProject(ProjectDraft draft) {
    createBodies.add(draft.toBody());
    final hook = onCreate;
    if (hook != null) return hook(draft);
    if (draft.status == ProjectStatus.active && activeCount >= maxActive) {
      return Future.value(const Left(ActiveProjectLimitFailure()));
    }
    final body = draft.toBody();
    final created = createdProjectFixture().copyWith(
      id: _nextId++,
      title: body['title'] as String,
      description: body['description'] as String?,
      status: draft.status,
      startDate: draft.startDate,
      targetDate: draft.targetDate,
    );
    server = [...server, created];
    return Future.value(Right(created));
  }

  @override
  Future<Either<Failure, Project>> updateProject(int id, ProjectChanges changes) {
    updateCalls.add((id, changes.toBody()));
    final hook = onUpdate;
    if (hook != null) return hook(id, changes);
    final index = server.indexWhere((p) => p.id == id);
    if (index < 0) return Future.value(const Left(notFound));
    var p = server[index];
    final newStatus = switch (changes.status) {
      PlanFieldSet<ProjectStatus>(:final value) => value,
      _ => p.status,
    };
    if (newStatus == ProjectStatus.active &&
        p.status != ProjectStatus.active &&
        activeCount >= maxActive) {
      return Future.value(const Left(ActiveProjectLimitFailure()));
    }
    T? pick<T>(PlanField<T> f, T? current) => switch (f) {
      PlanFieldUnset<T>() => current,
      PlanFieldSet<T>(:final value) => value,
      PlanFieldClear<T>() => null,
    };
    p = p.copyWith(
      title: pick(changes.title, p.title)!,
      status: newStatus,
      description: pick(changes.description, p.description),
      startDate: pick(changes.startDate, p.startDate),
      targetDate: pick(changes.targetDate, p.targetDate),
    );
    server = [...server]..[index] = p;
    return Future.value(Right(p));
  }

  @override
  Future<Either<Failure, void>> deleteProject(int id) {
    deleteIds.add(id);
    final hook = onDelete;
    if (hook != null) return hook(id);
    if (!server.any((p) => p.id == id)) return Future.value(const Left(notFound));
    server = server.where((p) => p.id != id).toList();
    return Future.value(const Right(null));
  }
}
