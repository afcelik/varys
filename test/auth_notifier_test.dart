// Unit tests for AuthNotifier error mapping logic

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:varys/features/auth/domain/auth_notifier.dart';

// Custom exception class for testing
class _CustomError implements Exception {
  @override
  String toString() => 'Custom error';
}

void main() {
  group('AuthNotifier.mapErrorToTurkish', () {
    group('DioException - HTTP status codes', () {
      test('401 status code maps to "Yanlış şifre"', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/login'),
            statusCode: 401,
          ),
          type: DioExceptionType.badResponse,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Yanlış şifre'));
      });

      test('429 status code maps to "Çok fazla deneme. Lütfen 15 dakika bekleyin."', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/login'),
            statusCode: 429,
          ),
          type: DioExceptionType.badResponse,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Çok fazla deneme. Lütfen 15 dakika bekleyin.'));
      });

      test('500 status code maps to "Sunucu hatası (500)"', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/login'),
            statusCode: 500,
          ),
          type: DioExceptionType.badResponse,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Sunucu hatası (500)'));
      });

      test('404 status code maps to "Sunucu hatası (404)"', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/login'),
            statusCode: 404,
          ),
          type: DioExceptionType.badResponse,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Sunucu hatası (404)'));
      });

      test('403 status code maps to "Sunucu hatası (403)"', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          response: Response(
            requestOptions: RequestOptions(path: '/auth/login'),
            statusCode: 403,
          ),
          type: DioExceptionType.badResponse,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Sunucu hatası (403)'));
      });
    });

    group('DioException - Connection and timeout errors', () {
      test('connectionError type maps to connection error message', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.connectionError,
          error: Exception('Connection refused'),
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.'));
      });

      test('connectionTimeout type maps to connection error message', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.connectionTimeout,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.'));
      });

      test('sendTimeout type maps to connection error message', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.sendTimeout,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.'));
      });

      test('receiveTimeout type maps to connection error message', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.receiveTimeout,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.'));
      });

      test('unknown type maps to connection error message', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.unknown,
          error: Exception('SocketException: Failed host lookup'),
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.'));
      });

      test('badCertificate type maps to certificate error message', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.badCertificate,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('Güvenlik sertifikası hatası'));
      });

      test('cancel type maps to cancelled message', () {
        final dioError = DioException(
          requestOptions: RequestOptions(path: '/auth/login'),
          type: DioExceptionType.cancel,
        );

        final result = AuthNotifier.mapErrorToTurkish(dioError);

        expect(result, equals('İstek iptal edildi'));
      });
    });

    group('PlatformException', () {
      test('PlatformException maps to secure storage error message', () {
        final platformError = PlatformException(
          code: '-34018',
          message: 'Keychain error -34018',
          details: 'User canceled',
        );

        final result = AuthNotifier.mapErrorToTurkish(platformError);

        expect(result, equals('Güvenli depolama erişilemiyor. Lütfen uygulama izinlerini kontrol edin.'));
      });

      test('PlatformException with different code still maps correctly', () {
        final platformError = PlatformException(
          code: 'UNAVAILABLE',
          message: 'Secure storage unavailable',
        );

        final result = AuthNotifier.mapErrorToTurkish(platformError);

        expect(result, equals('Güvenli depolama erişilemiyor. Lütfen uygulama izinlerini kontrol edin.'));
      });
    });

    group('Other exceptions', () {
      test('Generic Exception maps to generic error message', () {
        final genericError = Exception('Some unexpected error');

        final result = AuthNotifier.mapErrorToTurkish(genericError);

        expect(result, equals('Giriş sırasında bir hata oluştu'));
      });

      test('Custom Exception subclass maps to generic error message', () {
        final customError = _CustomError();

        final result = AuthNotifier.mapErrorToTurkish(customError);

        expect(result, equals('Giriş sırasında bir hata oluştu'));
      });

      test('FormatException maps to generic error message', () {
        final formatError = FormatException('Invalid format');

        final result = AuthNotifier.mapErrorToTurkish(formatError);

        expect(result, equals('Giriş sırasında bir hata oluştu'));
      });
    });
  });
}