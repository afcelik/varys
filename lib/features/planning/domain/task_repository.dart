import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/planning/domain/task.dart' show Task, TaskFilter, TaskStatus;

/// Abstract repository interface for Task operations
///
/// This defines the contract for task data operations, allowing
/// different implementations (API, local database, mock, etc.)
abstract class TaskRepository {
  /// Fetches all tasks from the data source
  Future<Either<Failure, List<Task>>> getTasks();

  /// Fetches tasks filtered by completion status
  Future<Either<Failure, List<Task>>> getTasksByFilter(TaskFilter filter);

  /// Creates a new task
  Future<Either<Failure, Task>> createTask(Task task);

  /// Updates an existing task
  Future<Either<Failure, Task>> updateTask(Task task);

  /// Deletes a task by ID
  Future<Either<Failure, void>> deleteTask(int id);

  /// Updates task status
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status);
}