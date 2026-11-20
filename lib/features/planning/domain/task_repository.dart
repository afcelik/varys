import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
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

  /// Partially updates task [id] (PATCH). Only explicitly given fields are
  /// sent: `title`/`status` null → not sent; for [PlanField] fields
  /// unset → key absent, set → value, clear → explicit `null`.
  /// Dates are sent as `YYYY-MM-DDT00:00:00` (no timezone).
  /// A 404 while [projectId] is set means the project is missing or deleted
  /// ("Seçilen proje bulunamadı."); otherwise a 404 is the generic message.
  /// [isImportant]/[isUrgent]: null → not sent (the backend rejects null
  /// with 422); a value → sent as is.
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
  });

  /// Deletes a task by ID
  Future<Either<Failure, void>> deleteTask(int id);

  /// Updates task status
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status);

  /// Plans a task for [day]. Sends ONLY `planned_date` (as
  /// `YYYY-MM-DDT00:00:00`, no timezone); no other field is touched.
  Future<Either<Failure, Task>> planForDay(int id, DateTime day);
}