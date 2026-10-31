import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/planning/domain/task.dart';

/// Failure class for handling errors in a functional way
sealed class DailyPlanFailure {
  const DailyPlanFailure();

  String get message => switch (this) {
        DailyPlanServerFailure(:final message) => message,
        DailyPlanNetworkFailure(:final message) => 'Bağlantı hatası: $message',
        DailyPlanUnknownFailure(:final message) => 'Bilinmeyen hata: $message',
      };
}

/// Server-side error (HTTP errors, validation errors, etc.)
class DailyPlanServerFailure extends DailyPlanFailure {
  const DailyPlanServerFailure(this.message, {this.statusCode});

  @override
  final String message;
  final int? statusCode;
}

/// Network connectivity error
class DailyPlanNetworkFailure extends DailyPlanFailure {
  const DailyPlanNetworkFailure(this.message);

  @override
  final String message;
}

/// Unknown/unexpected error
class DailyPlanUnknownFailure extends DailyPlanFailure {
  const DailyPlanUnknownFailure(this.message);

  @override
  final String message;
}

/// Repository for DailyPlan operations
class DailyPlanRepository {
  final ApiClient _apiClient;

  DailyPlanRepository(this._apiClient);

  static const String _basePath = '/daily-plans';

  /// Fetches the daily plan for the given date
  Future<Either<DailyPlanFailure, DailyPlan>> getPlan(DateTime day) async {
    try {
      final dateStr = formatDateForApi(day);
      final response = await _apiClient.get<Map<String, dynamic>>('$_basePath/$dateStr');

      // Parse tasks
      final tasksJson = response.data?['tasks'] as List<dynamic>? ?? [];
      final tasks = tasksJson
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();

      // Parse main focus
      Task? mainFocus;
      final mainFocusJson = response.data?['main_focus'] as Map<String, dynamic>?;
      if (mainFocusJson != null) {
        mainFocus = Task.fromJson(mainFocusJson);
      }

      // Parse side focus
      Task? sideFocus;
      final sideFocusJson = response.data?['side_focus'] as Map<String, dynamic>?;
      if (sideFocusJson != null) {
        sideFocus = Task.fromJson(sideFocusJson);
      }

      final plan = DailyPlan(
        planDate: day,
        mainFocus: mainFocus,
        sideFocus: sideFocus,
        sayNoText: response.data?['say_no_text'] as String?,
        tasks: tasks,
      );

      return Right(plan);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(DailyPlanUnknownFailure(e.toString()));
    }
  }

  /// Updates the daily plan with the given fields.
  /// Only non-null fields are included in the request.
  /// To clear a field, explicitly pass null.
  /// Returns the updated plan from the server response.
  Future<Either<DailyPlanFailure, DailyPlan>> updatePlan(
    DateTime day, {
    int? mainFocusTaskId,
    int? sideFocusTaskId,
    String? sayNoText,
  }) async {
    try {
      final dateStr = formatDateForApi(day);

      // Build request body with only explicitly provided fields
      // We use a Map and only add keys that were explicitly passed
      final Map<String, dynamic> requestBody = {};

      // Note: The way Dart works, we can't distinguish between "not provided" and "explicitly null"
      // from the caller's perspective without using a special sentinel value.
      // The API expects fields to be present to update them, and null to clear them.
      // The caller (DailyPlanNotifier) will only call this with fields that actually changed.

      if (mainFocusTaskId != null) {
        requestBody['main_focus_task_id'] = mainFocusTaskId;
      }
      if (sideFocusTaskId != null) {
        requestBody['side_focus_task_id'] = sideFocusTaskId;
      }
      if (sayNoText != null) {
        requestBody['say_no_text'] = sayNoText;
      }

      final response = await _apiClient.put<Map<String, dynamic>>(
        '$_basePath/$dateStr',
        data: requestBody,
      );

      // Parse response same as getPlan
      final tasksJson = response.data?['tasks'] as List<dynamic>? ?? [];
      final tasks = tasksJson
          .map((json) => Task.fromJson(json as Map<String, dynamic>))
          .toList();

      Task? mainFocus;
      final mainFocusJson = response.data?['main_focus'] as Map<String, dynamic>?;
      if (mainFocusJson != null) {
        mainFocus = Task.fromJson(mainFocusJson);
      }

      Task? sideFocus;
      final sideFocusJson = response.data?['side_focus'] as Map<String, dynamic>?;
      if (sideFocusJson != null) {
        sideFocus = Task.fromJson(sideFocusJson);
      }

      final plan = DailyPlan(
        planDate: day,
        mainFocus: mainFocus,
        sideFocus: sideFocus,
        sayNoText: response.data?['say_no_text'] as String?,
        tasks: tasks,
      );

      return Right(plan);
    } on DioException catch (e) {
      return Left(_handleDioError(e));
    } catch (e) {
      return Left(DailyPlanUnknownFailure(e.toString()));
    }
  }

  DailyPlanFailure _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return DailyPlanNetworkFailure('İstek zaman aşımına uğradı');
      case DioExceptionType.badResponse:
        final statusCode = e.response?.statusCode;
        final message = e.response?.data?['detail'] ?? 'Sunucu hatası: $statusCode';
        return DailyPlanServerFailure(message, statusCode: statusCode);
      case DioExceptionType.cancel:
        return DailyPlanNetworkFailure('İstek iptal edildi');
      case DioExceptionType.connectionError:
        return DailyPlanNetworkFailure('Sunucuya bağlanılamıyor');
      default:
        return DailyPlanNetworkFailure(e.message ?? 'Bilinmeyen ağ hatası');
    }
  }
}

/// Riverpod provider for DailyPlanRepository
final dailyPlanRepositoryProvider = FutureProvider<DailyPlanRepository>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return DailyPlanRepository(apiClient);
});