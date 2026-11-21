import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';
import 'package:varys/features/calendar/domain/calendar_repository.dart';

/// API implementation of [CalendarRepository].
///
/// Error text comes only from `core/errors` (`userMessage`), mapped by
/// exception type and status code; backend `detail` is never read.
class CalendarRepositoryImpl implements CalendarRepository {
  CalendarRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  static const String monthPath = '/calendar/month';

  @override
  Future<Either<Failure, CalendarMonth>> getMonth(int year, int month) async {
    try {
      final response = await _apiClient.get<Map<String, dynamic>>(
        monthPath,
        queryParameters: {'year': year, 'month': month},
      );
      return Right(CalendarMonth.fromJson(response.data!));
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        return Left(ServerFailure(userMessage(e), statusCode: e.response?.statusCode));
      }
      return Left(NetworkFailure(userMessage(e)));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('CalendarRepository.getMonth error: ${e.runtimeType} - $e\n$stackTrace');
      }
      return Left(UnknownFailure(e.runtimeType.toString()));
    }
  }
}

/// Riverpod provider for [CalendarRepository].
final calendarRepositoryProvider = FutureProvider<CalendarRepository>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return CalendarRepositoryImpl(apiClient);
});
