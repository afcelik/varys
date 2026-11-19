import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_repository.dart';

/// API implementation of [ProjectRepository].
///
/// Error text comes only from `core/errors` (`userMessage`), mapped by
/// exception type and status code; backend `detail` is never read.
class ProjectRepositoryImpl implements ProjectRepository {
  ProjectRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  static const String _basePath = '/projects';

  /// Backend value of each status for the `?status=` query.
  static const Map<ProjectStatus, String> statusQueryValue = {
    ProjectStatus.active: 'active',
    ProjectStatus.onHold: 'on_hold',
    ProjectStatus.someday: 'someday',
    ProjectStatus.completed: 'completed',
  };

  @override
  Future<Either<Failure, List<Project>>> getProjects({ProjectStatus? status}) {
    return _guard('getProjects', () async {
      final response = await _apiClient.get<List<dynamic>>(
        _basePath,
        queryParameters: status == null ? null : {'status': statusQueryValue[status]!},
      );
      final data = response.data ?? const <dynamic>[];
      return data.map((e) => Project.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  @override
  Future<Either<Failure, ProjectLimits>> getLimits() {
    return _guard('getLimits', () async {
      final response = await _apiClient.get<Map<String, dynamic>>('$_basePath/limits');
      return ProjectLimits.fromJson(response.data!);
    });
  }

  Future<Either<Failure, T>> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return Right(await body());
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('ProjectRepository.$op error: ${e.runtimeType} - $e\n$stackTrace');
      }
      return Left(UnknownFailure(e.runtimeType.toString()));
    }
  }

  static Failure _mapDioError(DioException e) {
    if (e.type == DioExceptionType.badResponse) {
      return ServerFailure(userMessage(e), statusCode: e.response?.statusCode);
    }
    return NetworkFailure(userMessage(e));
  }
}

/// Riverpod provider for [ProjectRepository].
final projectRepositoryProvider = FutureProvider<ProjectRepository>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return ProjectRepositoryImpl(apiClient);
});
