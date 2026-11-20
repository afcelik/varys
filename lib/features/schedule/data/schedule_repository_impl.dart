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
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/domain/schedule_repository.dart';

/// API implementation of [ScheduleRepository].
///
/// Error text comes only from `core/errors` (`userMessage`), mapped by
/// exception type and status code; backend `detail` is never read.
class ScheduleRepositoryImpl implements ScheduleRepository {
  ScheduleRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  static const String _basePath = '/schedule';

  @override
  Future<Either<Failure, List<ScheduleBlock>>> getBlocks() {
    return _guard('getBlocks', () async {
      final response = await _apiClient.get<List<dynamic>>(_basePath);
      return _parseList(response.data);
    });
  }

  @override
  Future<Either<Failure, List<ScheduleBlock>>> getBlocksForDay(DateTime day) {
    return _guard('getBlocksForDay', () async {
      final response = await _apiClient.get<List<dynamic>>(
        '$_basePath/day/${formatDateForApi(day)}',
      );
      return _parseList(response.data);
    });
  }

  @override
  Future<Either<Failure, ScheduleBlock>> createBlock({
    required String title,
    String? description,
    required ScheduleTime startTime,
    required ScheduleTime endTime,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
  }) {
    return _guard('createBlock', () async {
      final body = <String, dynamic>{
        'title': title,
        'description': description,
        'start_time': startTime.hhmm,
        'end_time': endTime.hhmm,
        'recurrence_type': recurrenceType.apiValue,
        'days_of_week': daysOfWeek == null ? null : (List<int>.of(daysOfWeek)..sort()),
        'day_of_month': dayOfMonth,
        'interval_days': intervalDays,
        'start_date': formatDateForApi(startDate),
      };
      final response = await _apiClient.post<Map<String, dynamic>>(_basePath, data: body);
      return ScheduleBlock.fromJson(response.data!);
    });
  }

  @override
  Future<Either<Failure, ScheduleBlock>> updateBlock(int id, ScheduleChanges changes) {
    return _guard('updateBlock', () async {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '$_basePath/$id',
        data: changes.toBody(),
      );
      return ScheduleBlock.fromJson(response.data!);
    });
  }

  @override
  Future<Either<Failure, void>> deleteBlock(int id) {
    return _guard('deleteBlock', () async {
      await _apiClient.delete<dynamic>('$_basePath/$id');
    });
  }

  static List<ScheduleBlock> _parseList(List<dynamic>? data) => (data ?? const <dynamic>[])
      .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
      .toList();

  Future<Either<Failure, T>> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return Right(await body());
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('ScheduleRepository.$op error: ${e.runtimeType} - $e\n$stackTrace');
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

/// Riverpod provider for [ScheduleRepository].
final scheduleRepositoryProvider = FutureProvider<ScheduleRepository>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return ScheduleRepositoryImpl(apiClient);
});
