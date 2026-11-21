import 'dart:async';

import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';

/// In-memory task server behind [TaskRepository] for calendar tests: filtered
/// lists, create (newest first), PATCH honouring PlanField (unset / set /
/// clear), status change, delete and plan-for-day. Records list fetches and
/// PATCH calls.
class FakeTaskServer implements TaskRepository {
  FakeTaskServer(this.server);

  List<Task> server;

  /// When set, list fetches wait for it (a parked answer).
  Completer<void>? listGate;
  int listCalls = 0;
  final updateCalls = <int>[];
  int _nextId = 100;

  @override
  Future<Either<Failure, List<Task>>> getTasks() async {
    listCalls++;
    await Future<void>.delayed(Duration.zero);
    await listGate?.future;
    return Right(List.of(server));
  }

  @override
  Future<Either<Failure, List<Task>>> getTasksByFilter(TaskFilter filter) async {
    listCalls++;
    await Future<void>.delayed(Duration.zero);
    await listGate?.future;
    return Right([
      for (final t in server)
        if (switch (filter) {
          TaskFilter.all => true,
          TaskFilter.inProgress => t.status != TaskStatus.done,
          TaskFilter.completed => t.status == TaskStatus.done,
        })
          t,
    ]);
  }

  @override
  Future<Either<Failure, Task>> createTask(Task task) async {
    final created = task.copyWith(id: _nextId++);
    server = [created, ...server];
    return Right(created);
  }

  static T? _apply<T>(PlanField<T> field, T? current) => switch (field) {
    PlanFieldUnset<T>() => current,
    PlanFieldSet<T>(:final value) => value,
    PlanFieldClear<T>() => null,
  };

  @override
  Future<Either<Failure, Task>> updateTask(
    int id, {
    String? title,
    PlanField<String> description = const PlanField.unset(),
    TaskStatus? status,
    PlanField<DateTime> plannedDate = const PlanField.unset(),
    PlanField<DateTime> dueDate = const PlanField.unset(),
    PlanField<int> projectId = const PlanField.unset(),
    bool? isImportant,
    bool? isUrgent,
  }) async {
    updateCalls.add(id);
    final old = server.firstWhere((t) => t.id == id);
    final updated = old.copyWith(
      title: title ?? old.title,
      description: _apply(description, old.description),
      status: status ?? old.status,
      plannedDate: _apply(plannedDate, old.plannedDate),
      dueDate: _apply(dueDate, old.dueDate),
      projectId: _apply(projectId, old.projectId),
      isImportant: isImportant ?? old.isImportant,
      isUrgent: isUrgent ?? old.isUrgent,
    );
    server = [for (final t in server) t.id == id ? updated : t];
    return Right(updated);
  }

  @override
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status) =>
      updateTask(id, status: status);

  @override
  Future<Either<Failure, void>> deleteTask(int id) async {
    server = server.where((t) => t.id != id).toList();
    return const Right(null);
  }

  @override
  Future<Either<Failure, Task>> planForDay(int id, DateTime day) =>
      updateTask(id, plannedDate: PlanField.set(day));
}
