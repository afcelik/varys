import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';

void main() {
  group('userMessage helper', () {
    test('NetworkFailure returns fixed Turkish message', () {
      final failure = NetworkFailure('Sunucuya bağlanılamıyor');
      expect(userMessage(failure), equals('Bağlantı hatası'));
    });

    test('ServerFailure returns its message', () {
      final failure = ServerFailure('Custom server error', statusCode: 500);
      expect(userMessage(failure), equals('Custom server error'));
    });

    test('UnknownFailure with detailed error text returns fixed message', () {
      final failure = UnknownFailure("type 'Null' is not a subtype of type 'String'");
      expect(userMessage(failure), equals('Beklenmeyen bir hata oluştu'));
      expect(userMessage(failure), isNot(contains('type')));
      expect(userMessage(failure), isNot(contains('Null')));
      expect(userMessage(failure), isNot(contains('subtype')));
    });

    test('CacheFailure returns fixed Turkish message', () {
      final failure = CacheFailure('Disk write failed');
      expect(userMessage(failure), equals('Önbellek hatası'));
    });

    test('DioException connectionError returns connection message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionError,
      );
      expect(userMessage(dioError), equals('Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.'));
    });

    test('DioException connectionTimeout returns timeout message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.connectionTimeout,
      );
      expect(userMessage(dioError), equals('İstek zaman aşımına uğradı'));
    });

    test('DioException sendTimeout returns timeout message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.sendTimeout,
      );
      expect(userMessage(dioError), equals('İstek zaman aşımına uğradı'));
    });

    test('DioException receiveTimeout returns timeout message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.receiveTimeout,
      );
      expect(userMessage(dioError), equals('İstek zaman aşımına uğradı'));
    });

    test('DioException badResponse 401 returns session expired message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 401,
          data: {'detail': 'Invalid credentials'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Oturum süresi doldu. Lütfen tekrar giriş yapın.'));
    });

    test('DioException badResponse 403 returns unauthorized message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 403,
          data: {'detail': 'Forbidden'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Yetkisiz erişim.'));
    });

    test('DioException badResponse 404 returns not found message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 404,
          data: {'detail': 'Not found'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Kaynak bulunamadı.'));
    });

    test('DioException badResponse 422 returns invalid data message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 422,
          data: {'detail': 'Validation error'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Gönderilen veriler geçersiz.'));
    });

    test('DioException badResponse 429 returns rate limit message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 429,
          data: {'detail': 'Too many requests'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Çok fazla deneme. Lütfen 15 dakika bekleyin.'));
    });

    test('DioException badResponse 500 returns server error message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 500,
          data: {'detail': 'Internal server error'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Sunucu hatası. Lütfen daha sonra tekrar deneyin.'));
    });

    test('DioException badResponse 503 returns server error message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 503,
          data: {'detail': 'Service unavailable'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Sunucu hatası. Lütfen daha sonra tekrar deneyin.'));
    });

    test('DioException badResponse with non-Map response body returns fixed message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 422,
          data: ['error1', 'error2'], // List instead of Map
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Gönderilen veriler geçersiz.'));
    });

    test('DioException badResponse with detail as list returns fixed message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 422,
          data: {'detail': ['error1', 'error2']}, // detail is a list
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Gönderilen veriler geçersiz.'));
    });

    test('DioException badResponse with null response body returns fixed message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 500,
          data: null,
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Sunucu hatası. Lütfen daha sonra tekrar deneyin.'));
    });

    test('DioException badResponse with unknown status code returns generic message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        response: Response(
          requestOptions: RequestOptions(path: '/test'),
          statusCode: 418, // I'm a teapot
          data: {'detail': 'Teapot'},
        ),
        type: DioExceptionType.badResponse,
      );
      expect(userMessage(dioError), equals('Bir hata oluştu. Lütfen tekrar deneyin.'));
    });

    test('DioException unknown returns generic message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.unknown,
      );
      expect(userMessage(dioError), equals('Beklenmeyen bir hata oluştu'));
    });

    test('DioException cancel returns cancel message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.cancel,
      );
      expect(userMessage(dioError), equals('İstek iptal edildi'));
    });

    test('DioException badCertificate returns certificate error message', () {
      final dioError = DioException(
        requestOptions: RequestOptions(path: '/test'),
        type: DioExceptionType.badCertificate,
      );
      expect(userMessage(dioError), equals('Güvenlik sertifikası hatası'));
    });

    test('Generic Exception returns fixed message without Exception prefix', () {
      final exception = Exception('Some detailed error message');
      expect(userMessage(exception), equals('Beklenmeyen bir hata oluştu'));
      expect(userMessage(exception), isNot(contains('Exception:')));
      expect(userMessage(exception), isNot(contains('Some detailed')));
    });

    test('FormatException returns fixed message', () {
      final exception = FormatException('Invalid format');
      expect(userMessage(exception), equals('Beklenmeyen bir hata oluştu'));
    });

    test('Random object returns fallback message', () {
      expect(userMessage('just a string'), equals('Beklenmeyen bir hata oluştu'));
      expect(userMessage(123), equals('Beklenmeyen bir hata oluştu'));
      // Note: null can't be passed as Object in Dart, so we skip testing null directly
    });
  });
}