/// Auth state sealed class for Riverpod state management.
///
/// Represents all possible authentication states in the app.
sealed class AuthState {
  const AuthState();
}

/// Initial state - checking for stored token on app startup.
class AuthInitial extends AuthState {
  const AuthInitial();
}

/// Loading state - login request in progress.
class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Authenticated state - user has valid JWT token.
class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.token);

  final String token;
}

/// Unauthenticated state - no valid token (needs login).
class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated({this.sessionExpired = false});

  /// Whether this unauthenticated state was caused by session expiration (401).
  /// When true, the login screen shows a "session expired" message.
  final bool sessionExpired;
}

/// Error state - login failed with error message.
class AuthError extends AuthState {
  const AuthError(this.message);

  final String message;
}