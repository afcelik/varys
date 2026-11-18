import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';

/// API implementation of TaskRepository
///
/// Communicates with the Varys backend to perform task operations.
class TaskRepositoryImpl implements TaskRepository {
  final ApiClient _apiClient;

  TaskRepositoryImpl(this._apiClient);

  static const String _basePath = '/tasks';

  @override
  Future<Either<Failure, List<Task>>> getTasks() async {
    try {
      final response = await _apiClient.get<List<dynamic>>(_basePath);
      final tasks = (response.data as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();
      return Right(tasks);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('TaskRepositoryImpl.getTasks error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Task>>> getTasksByFilter(TaskFilter filter) async {
    try {
      final response = await _apiClient.get<List<dynamic>>(_basePath);
      final allTasks = (response.data as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();

      final filteredTasks = switch (filter) {
        TaskFilter.all => allTasks,
        TaskFilter.inProgress =>
            allTasks.where((t) => t.status == TaskStatus.todo || t.status == TaskStatus.inProgress).toList(),
        TaskFilter.completed =>
            allTasks.where((t) => t.status == TaskStatus.done).toList(),
      };

      return Right(filteredTasks);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('TaskRepositoryImpl.getTasksByFilter error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Task>> createTask(Task task) async {
    try {
      // Build request body manually - only include fields that should be sent
      // Exclude server-generated fields: id, created_at, updated_at, deleted_at
      final Map<String, dynamic> requestBody = {
        'title': task.title,
      };

      if (task.description != null) {
        requestBody['description'] = task.description;
      }
      if (task.status != TaskStatus.todo) {
        requestBody['status'] = task.status.name;
      }
      if (task.plannedDate != null) {
        requestBody['planned_date'] = plannedDateForApi(task.plannedDate!);
      }
      if (task.dueDate != null) {
        requestBody['due_date'] = plannedDateForApi(task.dueDate!);
      }

      final response = await _apiClient.post<Map<String, dynamic>>(
        _basePath,
        data: requestBody,
      );
      final createdTask = Task.fromJson(response.data!);
      return Right(createdTask);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('TaskRepositoryImpl.createTask error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Task>> updateTask(
    int id, {
    String? title,
    PlanField<String> description = const PlanField.unset(),
    TaskStatus? status,
    PlanField<DateTime> plannedDate = const PlanField.unset(),
    PlanField<DateTime> dueDate = const PlanField.unset(),
  }) async {
    try {
      // Only explicitly given fields are sent; clear → explicit null.
      final Map<String, dynamic> requestBody = {};
      if (title != null) requestBody['title'] = title;
      description.writeTo(requestBody, 'description');
      if (status != null) requestBody['status'] = status.name;
      _writeDay(requestBody, 'planned_date', plannedDate);
      _writeDay(requestBody, 'due_date', dueDate);

      final response = await _apiClient.patch<Map<String, dynamic>>(
        '$_basePath/$id',
        data: requestBody,
      );
      final updatedTask = Task.fromJson(response.data!);
      return Right(updatedTask);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('TaskRepositoryImpl.updateTask error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteTask(int id) async {
    try {
      await _apiClient.delete<void>('$_basePath/$id');
      return const Right(null);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('TaskRepositoryImpl.deleteTask error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status) async {
    try {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '$_basePath/$id',
        data: {'status': status.name},
      );
      final updatedTask = Task.fromJson(response.data!);
      return Right(updatedTask);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('TaskRepositoryImpl.updateTaskStatus error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Task>> planForDay(int id, DateTime day) async {
    try {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '$_basePath/$id',
        data: {'planned_date': plannedDateForApi(day)},
      );
      return Right(Task.fromJson(response.data!));
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('TaskRepositoryImpl.planForDay error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return Left(UnknownFailure(e.toString()));
    }
  }

  /// Writes a task-day field: set → `YYYY-MM-DDT00:00:00`, clear → explicit
  /// `null`, unset → key absent.
  static void _writeDay(Map<String, dynamic> body, String key, PlanField<DateTime> field) {
    switch (field) {
      case PlanFieldUnset<DateTime>():
        break;
      case PlanFieldSet<DateTime>(:final value):
        body[key] = plannedDateForApi(value);
      case PlanFieldClear<DateTime>():
        body[key] = null;
    }
  }

  Failure _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkFailure('İstek zaman aşımına uğradı');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        // Use fixed Turkish messages, never expose backend detail
        switch (statusCode) {
          case 401:
            return const ServerFailure('Oturum süresi doldu. Lütfen tekrar giriş yapın.', statusCode: 401);
          case 403:
            return const ServerFailure('Yetkisiz erişim.', statusCode: 403);
          case 404:
            return const ServerFailure('Kaynak bulunamadı.', statusCode: 404);
          case 422:
            return const ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);
          case 429:
            return const ServerFailure('Çok fazla deneme. Lütfen 15 dakika bekleyin.', statusCode: 429);
          default:
            if (statusCode != null && statusCode >= 500) {
              return ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: statusCode);
            }
            return ServerFailure('Bir hata oluştu. Lütfen tekrar deneyin.', statusCode: statusCode);
        }
      case DioExceptionType.cancel:
        return const NetworkFailure('İstek iptal edildi');
      case DioExceptionType.connectionError:
        return const NetworkFailure('Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.');
      case DioExceptionType.badCertificate:
        return const NetworkFailure('Güvenlik sertifikası hatası');
      case DioExceptionType.unknown:
      case DioExceptionType.transformTimeout:
        return const NetworkFailure('Beklenmeyen bir hata oluştu');
    }
  }
}

/// Riverpod provider for TaskRepository
///
/// Uses FutureProvider since it depends on ApiClient which is async.
final taskRepositoryProvider = FutureProvider<TaskRepository>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return TaskRepositoryImpl(apiClient);
});