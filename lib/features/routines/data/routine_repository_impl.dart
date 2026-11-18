import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
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

  @override
  Future<Either<Failure, List<Routine>>> getRoutines() {
    return _guard('getRoutines', () async {
      final response = await _apiClient.get<List<dynamic>>(_basePath);
      final data = response.data ?? const <dynamic>[];
      return data.map((e) => Routine.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  @override
  Future<Either<Failure, Routine>> createRoutine({
    required String title,
    String? description,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
  }) {
    return _guard('createRoutine', () async {
      final body = <String, dynamic>{
        'title': title,
        'description': description,
        'recurrence_type': recurrenceType.apiValue,
        'days_of_week': daysOfWeek == null ? null : (List<int>.of(daysOfWeek)..sort()),
        'day_of_month': dayOfMonth,
        'interval_days': intervalDays,
        'start_date': formatDateForApi(startDate),
      };
      final response = await _apiClient.post<Map<String, dynamic>>(_basePath, data: body);
      return Routine.fromJson(response.data!);
    });
  }

  @override
  Future<Either<Failure, Routine>> updateRoutine(int id, RoutineChanges changes) {
    return _guard('updateRoutine', () async {
      final response =
          await _apiClient.patch<Map<String, dynamic>>('$_basePath/$id', data: changes.toBody());
      return Routine.fromJson(response.data!);
    });
  }

  @override
  Future<Either<Failure, void>> deleteRoutine(int id) {
    return _guard('deleteRoutine', () async {
      await _apiClient.delete<dynamic>('$_basePath/$id');
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
