import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/features/planning/domain/task.dart';

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
  Future<Either<Failure, void>> deleteTask(String id);

  /// Toggles task completion status
  Future<Either<Failure, Task>> toggleCompletion(String id);
}

/// Failure class for handling errors in a functional way
sealed class Failure {
  const Failure();

  String get message => switch (this) {
        ServerFailure(:final message) => message,
        NetworkFailure(:final message) => 'Bağlantı hatası: $message',
        CacheFailure(:final message) => 'Önbellek hatası: $message',
        UnknownFailure(:final message) => 'Bilinmeyen hata: $message',
      };
}

/// Server-side error (HTTP errors, validation errors, etc.)
class ServerFailure extends Failure {
  const ServerFailure(this.message, {this.statusCode});

  @override
  final String message;
  final int? statusCode;
}

/// Network connectivity error
class NetworkFailure extends Failure {
  const NetworkFailure(this.message);

  @override
  final String message;
}

/// Local cache/storage error
class CacheFailure extends Failure {
  const CacheFailure(this.message);

  @override
  final String message;
}

/// Unknown/unexpected error
class UnknownFailure extends Failure {
  const UnknownFailure(this.message);

  @override
  final String message;
}