import 'failure.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Centralized error message generator.
/// UI screens MUST use this instead of error.toString().
String userMessage(Object error) {
  if (error is Failure) {
    return error.userMessage;
  }

  if (error is DioException) {
    return _mapDioError(error);
  }

  if (error is Exception) {
    // Log the actual error for debugging, show fixed message to user
    if (kDebugMode) {
      debugPrint('Exception caught: ${error.runtimeType} - $error');
    }
    return 'Beklenmeyen bir hata oluştu';
  }

  if (kDebugMode) {
    debugPrint('Unknown error type: ${error.runtimeType} - $error');
  }
  return 'Beklenmeyen bir hata oluştu';
}

String _mapDioError(DioException e) {
  final statusCode = e.response?.statusCode;

  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'İstek zaman aşımına uğradı';
    case DioExceptionType.badResponse:
      // Map status codes to fixed Turkish messages, never expose backend detail
      switch (statusCode) {
        case 401:
          return 'Oturum süresi doldu. Lütfen tekrar giriş yapın.';
        case 403:
          return 'Yetkisiz erişim.';
        case 404:
          return 'Kaynak bulunamadı.';
        case 422:
          return 'Gönderilen veriler geçersiz.';
        case 429:
          return 'Çok fazla deneme. Lütfen 15 dakika bekleyin.';
        default:
          if (statusCode != null && statusCode >= 500) {
            return 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.';
          }
          return 'Bir hata oluştu. Lütfen tekrar deneyin.';
      }
    case DioExceptionType.cancel:
      return 'İstek iptal edildi';
    case DioExceptionType.connectionError:
      return 'Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.';
    case DioExceptionType.badCertificate:
      return 'Güvenlik sertifikası hatası';
    case DioExceptionType.unknown:
    case DioExceptionType.transformTimeout:
      return 'Beklenmeyen bir hata oluştu';
  }
}