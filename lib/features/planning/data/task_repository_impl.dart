import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
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
        requestBody['planned_date'] = task.plannedDate!.toIso8601String();
      }
      if (task.dueDate != null) {
        requestBody['due_date'] = task.dueDate!.toIso8601String();
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
  Future<Either<Failure, Task>> updateTask(Task task) async {
    try {
      // Build request body manually - only include non-null fields that should be updated
      // Exclude server-generated fields: id, created_at, updated_at, deleted_at
      final Map<String, dynamic> requestBody = {};

      if (task.title.isNotEmpty) {
        requestBody['title'] = task.title;
      }
      // description can be explicitly set to null to clear it
      if (task.description != null) {
        requestBody['description'] = task.description;
      }
      if (task.status != TaskStatus.todo) {
        requestBody['status'] = task.status.name;
      }
      if (task.plannedDate != null) {
        requestBody['planned_date'] = task.plannedDate!.toIso8601String();
      }
      if (task.dueDate != null) {
        requestBody['due_date'] = task.dueDate!.toIso8601String();
      }

      final response = await _apiClient.patch<Map<String, dynamic>>(
        '$_basePath/${task.id}',
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