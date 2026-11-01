import 'package:dio/dio.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/planning/domain/task.dart';

/// Repository for DailyPlan operations
class DailyPlanRepository {
  final ApiClient _apiClient;

  DailyPlanRepository(this._apiClient);

  static const String _basePath = '/daily-plans';

  /// Fetches the daily plan for the given date
  Future<Either<Failure, DailyPlan>> getPlan(DateTime day) async {
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
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('DailyPlanRepository.getPlan error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return Left(UnknownFailure(e.toString()));
    }
  }

  /// Updates the daily plan with the given fields.
  /// Only non-null fields are included in the request.
  /// To clear a field, explicitly pass null.
  /// Returns the updated plan from the server response.
  Future<Either<Failure, DailyPlan>> updatePlan(
    DateTime day, {
    int? mainFocusTaskId,
    int? sideFocusTaskId,
    String? sayNoText,
  }) async {
    try {
      final dateStr = formatDateForApi(day);

      // Build request body with only explicitly provided fields
      final Map<String, dynamic> requestBody = {};

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
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('DailyPlanRepository.updatePlan error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
      return Left(UnknownFailure(e.toString()));
    }
  }

  Failure _handleDioError(DioException e) {
    final statusCode = e.response?.statusCode;

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NetworkFailure('İstek zaman aşımına uğradı');
      case DioExceptionType.badResponse:
        // For 422 on DailyPlan PUT, the backend may return specific messages
        // about task already being main/side focus. We preserve those.
        if (statusCode == 422) {
          final detail = e.response?.data?['detail'];
          if (detail is String && detail.isNotEmpty) {
            // Check if it's a specific task assignment conflict message
            if (detail.contains('main focus') || detail.contains('ana odak') ||
                detail.contains('side focus') || detail.contains('yan odak') ||
                detail.contains('already assigned') || detail.contains('zaten atanmış')) {
              return ServerFailure(detail, statusCode: 422);
            }
          }
        }
        // Use fixed Turkish messages for all other cases
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

/// Riverpod provider for DailyPlanRepository
final dailyPlanRepositoryProvider = FutureProvider<DailyPlanRepository>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return DailyPlanRepository(apiClient);
});