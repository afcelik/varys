sealed class Failure {
  const Failure();

  /// Returns the user-facing Turkish error message
  String get userMessage;
}

class ServerFailure extends Failure {
  const ServerFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String get userMessage => message;
}

class NetworkFailure extends Failure {
  const NetworkFailure(this.message);
  final String message;

  @override
  String get userMessage => 'Bağlantı hatası';
}

class CacheFailure extends Failure {
  const CacheFailure(this.message);
  final String message;

  @override
  String get userMessage => 'Önbellek hatası';
}

class UnknownFailure extends Failure {
  const UnknownFailure(this.message);
  final String message;

  @override
  String get userMessage => 'Beklenmeyen bir hata oluştu';
}