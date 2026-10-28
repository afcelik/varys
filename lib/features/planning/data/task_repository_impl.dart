import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Task>>> getTasksByFilter(TaskFilter filter) async {
    try {
      String queryParam;
      switch (filter) {
        case TaskFilter.all:
          queryParam = '';
          break;
        case TaskFilter.inProgress:
          queryParam = '?filter=in_progress';
          break;
        case TaskFilter.completed:
          queryParam = '?filter=completed';
          break;
      }

      final response = await _apiClient.get<List<dynamic>>('$_basePath$queryParam');
      final tasks = (response.data as List)
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();
      return Right(tasks);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Task>> createTask(Task task) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        _basePath,
        data: task.toJson(),
      );
      final createdTask = Task.fromJson(response.data!);
      return Right(createdTask);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Task>> updateTask(Task task) async {
    try {
      final response = await _apiClient.put<Map<String, dynamic>>(
        '$_basePath/${task.id}',
        data: task.toJson(),
      );
      final updatedTask = Task.fromJson(response.data!);
      return Right(updatedTask);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> deleteTask(String id) async {
    try {
      await _apiClient.delete<void>('$_basePath/$id');
      return const Right(null);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Task>> toggleCompletion(String id) async {
    try {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '$_basePath/$id/toggle',
      );
      final updatedTask = Task.fromJson(response.data!);
      return Right(updatedTask);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(UnknownFailure(e.toString()));
    }
  }

  Failure _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkFailure('İstek zaman aşımına uğradı');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final message = e.response?.data?['message'] ?? 'Sunucu hatası: $statusCode';
        return ServerFailure(message, statusCode: statusCode);
      case DioExceptionType.cancel:
        return NetworkFailure('İstek iptal edildi');
      case DioExceptionType.connectionError:
        return NetworkFailure('Sunucuya bağlanılamıyor');
      default:
        return NetworkFailure(e.message ?? 'Bilinmeyen ağ hatası');
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