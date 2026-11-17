import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

/// API implementation of [RoutineRepository].
///
/// Error text comes only from `core/errors` (`userMessage`), mapped by
/// exception type and status code; backend `detail` is never read.
class RoutineRepositoryImpl implements RoutineRepository {
  RoutineRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  static const String _basePath = '/routines';

  @override
  Future<Either<Failure, List<RoutineDayItem>>> getRoutinesForDay(DateTime day) {
    return _guard('getRoutinesForDay', () async {
      final response =
          await _apiClient.get<List<dynamic>>('$_basePath/day/${formatDateForApi(day)}');
      final data = response.data ?? const <dynamic>[];
      return data.map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  @override
  Future<Either<Failure, void>> markDone(int routineId, DateTime day) {
    return _guard('markDone', () async {
      // 201 (created) and 200 (already completed) are both success;
      // the RoutineLogRead body carries no streaks, so it is not used.
      await _apiClient.put<dynamic>(_logPath(routineId, day));
    });
  }

  @override
  Future<Either<Failure, void>> undo(int routineId, DateTime day) {
    return _guard('undo', () async {
      await _apiClient.delete<dynamic>(_logPath(routineId, day));
    });
  }

  String _logPath(int routineId, DateTime day) =>
      '$_basePath/$routineId/logs/${formatDateForApi(day)}';

  Future<Either<Failure, T>> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return Right(await body());
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('RoutineRepository.$op error: ${e.runtimeType} - $e\n$stackTrace');
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

/// Riverpod provider for [RoutineRepository].
final routineRepositoryProvider = FutureProvider<RoutineRepository>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return RoutineRepositoryImpl(apiClient);
});
