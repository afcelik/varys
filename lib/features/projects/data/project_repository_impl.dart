import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';
import 'package:varys/features/projects/domain/project_repository.dart';

/// API implementation of [ProjectRepository].
///
/// Error text comes only from `core/errors` (`userMessage`), mapped by
/// exception type and status code. The only backend `detail` ever compared
/// is the fixed machine code [activeLimitCode] (409); it is never shown.
class ProjectRepositoryImpl implements ProjectRepository {
  ProjectRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  static const String _basePath = '/projects';

  /// 409 `detail` of the active project limit (backend `ACTIVE_LIMIT_DETAIL`).
  static const String activeLimitCode = 'active_project_limit_reached';

  @override
  Future<Either<Failure, List<Project>>> getProjects({ProjectStatus? status}) {
    return _guard('getProjects', () async {
      final response = await _apiClient.get<List<dynamic>>(
        _basePath,
        queryParameters: status == null ? null : {'status': status.apiValue},
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

  @override
  Future<Either<Failure, Project>> createProject(ProjectDraft draft) {
    return _guard('createProject', () async {
      final response = await _apiClient.post<Map<String, dynamic>>(_basePath, data: draft.toBody());
      return Project.fromJson(response.data!);
    });
  }

  @override
  Future<Either<Failure, Project>> updateProject(int id, ProjectChanges changes) {
    return _guard('updateProject', () async {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '$_basePath/$id',
        data: changes.toBody(),
      );
      return Project.fromJson(response.data!);
    });
  }

  @override
  Future<Either<Failure, void>> deleteProject(int id) {
    return _guard('deleteProject', () async {
      await _apiClient.delete<dynamic>('$_basePath/$id');
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
      final response = e.response;
      final data = response?.data;
      if (response?.statusCode == 409 && data is Map && data['detail'] == activeLimitCode) {
        return const ActiveProjectLimitFailure();
      }
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
