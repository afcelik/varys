// Session token flow: real ApiClient (from apiClientProvider) + fake HTTP
// adapter. Verifies 401 handling against the CURRENT session token and that
// the client follows the auth state across logout / login.
//
// "Login" is simulated with AuthNotifier.updateToken: login() builds its own
// ApiClient.forLogin (no adapter injection point) and ends with the same two
// steps (write token to storage, set AuthAuthenticated(token)).

import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/core/storage/secure_storage.dart';
import 'package:varys/features/auth/domain/auth_notifier.dart';
import 'package:varys/features/auth/domain/auth_state.dart';

const _oldToken = 'old.jwt.token';
const _newToken = 'new.jwt.token';

/// Records each request's Authorization header and answers with a status.
/// When [gate] is set, the next response waits for it.
class _FakeAdapter implements HttpClientAdapter {
  final List<String?> authHeaders = [];
  int status = 200;
  Completer<int>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    authHeaders.add(options.headers['Authorization'] as String?);
    final pending = gate;
    gate = null;
    final code = pending != null ? await pending.future : status;
    return ResponseBody.fromString(
      '{}',
      code,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Counts handleSessionExpired calls; behavior is the real one.
class _CountingAuthNotifier extends AuthNotifier {
  int expiredCalls = 0;

  @override
  Future<bool> handleSessionExpired(dynamic ref, {required String requestToken}) {
    expiredCalls++;
    return super.handleSessionExpired(ref, requestToken: requestToken);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _CountingAuthNotifier auth;

  Future<void> settleAuth() async {
    for (var i = 0; i < 50 && container.read(authNotifierProvider) is AuthInitial; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Reads the current client from the provider and installs a fake adapter.
  Future<(ApiClient, _FakeAdapter)> currentClient() async {
    final client = await container.read(apiClientProvider.future);
    final adapter = _FakeAdapter();
    client.dio.httpClientAdapter = adapter;
    return (client, adapter);
  }

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': _oldToken});
    auth = _CountingAuthNotifier();
    container = ProviderContainer(
      overrides: [authNotifierProvider.overrideWith((ref) => auth)],
    );
    container.read(authNotifierProvider);
    await settleAuth();
    expect(container.read(authNotifierProvider), const TypeMatcher<AuthAuthenticated>());
  });

  tearDown(() => container.dispose());

  test('(a) late 401 carrying the old token does not close the new session', () async {
    final (oldClient, oldAdapter) = await currentClient();
    // Keep the old client alive (as if a screen still held it): only the
    // token check in handleSessionExpired can stop this 401.
    final sub = container.listen(apiClientProvider, (_, _) {});
    addTearDown(sub.close);

    final gate = Completer<int>();
    oldAdapter.gate = gate;
    final inFlight = oldClient.get<Map<String, dynamic>>('/tasks');

    // Simulate the same old token getting a late 401 via the CURRENT client
    // after re-login: both clients' callbacks end in handleSessionExpired.
    await auth.updateToken(_newToken);
    final (newClient, newAdapter) = await currentClient();
    newAdapter.status = 401;
    newClient.dio.options.headers['Authorization'] = 'Bearer $_oldToken';
    await expectLater(newClient.get<Map<String, dynamic>>('/tasks'),
        throwsA(isA<DioException>()));

    expect(auth.expiredCalls, 1, reason: 'live client reports the 401');
    expect(container.read(authNotifierProvider), const TypeMatcher<AuthAuthenticated>());
    expect((container.read(authNotifierProvider) as AuthAuthenticated).token, _newToken);
    expect(await SecureStorage.getAuthToken(), _newToken);

    gate.complete(200);
    await inFlight;
  });

  test("(a') 401 for the current token expires the session once", () async {
    final (client, adapter) = await currentClient();
    adapter.status = 401;

    await expectLater(client.get<Map<String, dynamic>>('/tasks'), throwsA(isA<DioException>()));

    expect(auth.expiredCalls, 1);
    final state = container.read(authNotifierProvider);
    expect(state, const TypeMatcher<AuthUnauthenticated>());
    expect((state as AuthUnauthenticated).sessionExpired, isTrue);
    expect(await SecureStorage.getAuthToken(), isNull);

    // Second report for the same token: no longer authenticated -> false.
    final again = await auth.handleSessionExpired(container, requestToken: _oldToken);
    expect(again, isFalse);
    expect((container.read(authNotifierProvider) as AuthUnauthenticated).sessionExpired, isTrue);
  });

  test('(b) logout then login with a different token: next request carries the new token',
      () async {
    final (oldClient, oldAdapter) = await currentClient();
    await oldClient.get<Map<String, dynamic>>('/tasks');
    expect(oldAdapter.authHeaders.single, 'Bearer $_oldToken');

    await auth.logout(container.invalidate);
    expect((container.read(authNotifierProvider) as AuthUnauthenticated).sessionExpired, isFalse);
    await auth.updateToken(_newToken);

    final (newClient, newAdapter) = await currentClient();
    expect(identical(newClient, oldClient), isFalse);
    await newClient.get<Map<String, dynamic>>('/tasks');
    expect(newAdapter.authHeaders.single, 'Bearer $_newToken');
  });

  test('(c) client read between logout and login still sends the new token after login',
      () async {
    await auth.logout(container.invalidate);

    // Something reads the client on the login screen: built without a token.
    final (loggedOutClient, loggedOutAdapter) = await currentClient();
    expect(loggedOutClient.hasAuthToken, isFalse);
    await loggedOutClient.get<Map<String, dynamic>>('/health');
    expect(loggedOutAdapter.authHeaders.single, isNull);

    await auth.updateToken(_newToken);

    final (client, adapter) = await currentClient();
    await client.get<Map<String, dynamic>>('/tasks');
    expect(adapter.authHeaders.single, 'Bearer $_newToken');
  });

  test('(d) 401 on /auth/login or without Authorization header does not expire the session',
      () async {
    final (client, adapter) = await currentClient();
    adapter.status = 401;

    await expectLater(client.login('wrong'), throwsA(isA<DioException>()));
    client.clearAuthToken();
    await expectLater(client.get<Map<String, dynamic>>('/tasks'), throwsA(isA<DioException>()));

    expect(auth.expiredCalls, 0);
    expect(container.read(authNotifierProvider), const TypeMatcher<AuthAuthenticated>());
  });

  test('(e) late 401 on a client replaced by a token change: no error, no logout, no call',
      () async {
    final uncaught = <Object>[];
    await runZonedGuarded(() async {
      final (oldClient, oldAdapter) = await currentClient();
      final gate = Completer<int>();
      oldAdapter.gate = gate;
      final inFlight = oldClient.get<Map<String, dynamic>>('/tasks');

      // Token change rebuilds apiClientProvider; the old instance is disposed.
      await auth.updateToken(_newToken);
      final (newClient, _) = await currentClient();
      expect(identical(newClient, oldClient), isFalse);

      gate.complete(401);
      await expectLater(inFlight, throwsA(isA<DioException>()));
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => uncaught.add(error));

    expect(uncaught, isEmpty);
    expect(auth.expiredCalls, 0);
    final state = container.read(authNotifierProvider);
    expect(state, const TypeMatcher<AuthAuthenticated>());
    expect((state as AuthAuthenticated).token, _newToken);
    expect(await SecureStorage.getAuthToken(), _newToken);
  });
}
