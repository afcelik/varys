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

/// Client-side validation failure (no request was sent).
/// [message] must be a fixed Turkish text, never backend output.
class ValidationFailure extends Failure {
  const ValidationFailure(this.message);
  final String message;

  @override
  String get userMessage => message;
}

/// 409 with the backend code `active_project_limit_reached`: activating a
/// project would exceed the active project limit. Only that exact code maps
/// here; the backend text is never stored or shown.
class ActiveProjectLimitFailure extends Failure {
  const ActiveProjectLimitFailure();

  static const String message =
      'Aktif proje sınırına ulaşıldı. Önce bir projeyi beklemeye ya da ileriye al.';

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