// Settings "Bağlantıyı Test Et": the result is always a fixed Turkish text
// (success / failure) or "Bağlantı hatası: " + userMessage(error); never
// toString() output. The tester gets the entered (not saved) address and the
// stored token.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/features/settings/presentation/settings_screen.dart';

import '../../helpers/varys_app_harness.dart';

const _savedUrl = 'http://192.168.1.10:8000';
const _enteredUrl = 'http://10.0.0.5:9000';
const _token = 'a.b.c';

const _success = 'Bağlantı başarılı! Sunucu yanıt verdi.';
const _failure = 'Bağlantı başarısız. Sunucu yanıt vermedi.';

void main() {
  late List<(String, String?)> calls;

  setUp(() {
    calls = [];
    FlutterSecureStorage.setMockInitialValues({'server_url': _savedUrl, 'auth_token': _token});
  });

  Future<void> pumpSettings(WidgetTester tester, ConnectionTester connect) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: SettingsScreen.routePath,
      routes: [
        GoRoute(path: '/home', builder: (_, _) => const Scaffold(body: Text('HOME'))),
        GoRoute(path: SettingsScreen.routePath, builder: (_, _) => const SettingsScreen()),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: [
        connectionTesterProvider.overrideWithValue((baseUrl, token) {
          calls.add((baseUrl, token));
          return connect(baseUrl, token);
        }),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Ayarlar'), findsOneWidget);
  }

  final urlField = find.byType(TextFormField).first;

  Future<void> runTest(WidgetTester tester) async {
    await tester.tap(find.text('Bağlantıyı Test Et'));
    await tester.pumpAndSettle();
  }

  void expectNoRawError() {
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.textContaining('Instance of'), findsNothing);
    expect(find.textContaining('DioException'), findsNothing);
    expect(find.textContaining('Error'), findsNothing);
  }

  testWidgets('helper text is Turkish', (tester) async {
    await pumpSettings(tester, (_, _) async => true);
    expect(find.text('Sunucu adresini girin'), findsOneWidget);
    expect(find.textContaining('Backend API'), findsNothing);
  });

  testWidgets('success: fixed Turkish text; entered address and stored token are used', (
    tester,
  ) async {
    await pumpSettings(tester, (_, _) async => true);
    expect(find.text(_savedUrl), findsOneWidget, reason: 'saved address loaded');
    await tester.enterText(urlField, '  $_enteredUrl  ');
    await runTest(tester);

    expect(find.text(_success), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(calls, [(_enteredUrl, _token)]);
    expectNoRawError();
  });

  testWidgets('no answer (false): fixed Turkish failure text', (tester) async {
    await pumpSettings(tester, (_, _) async => false);
    await runTest(tester);

    expect(find.text(_failure), findsOneWidget);
    expect(find.text(_success), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(calls, hasLength(1));
    expectNoRawError();
  });

  testWidgets('thrown Exception: userMessage text, no exception detail', (tester) async {
    await pumpSettings(tester, (_, _) async => throw Exception('secret detail 123'));
    await runTest(tester);

    expect(find.text('Bağlantı hatası: Beklenmeyen bir hata oluştu'), findsOneWidget);
    expect(find.textContaining('secret detail'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expectNoRawError();
  });

  testWidgets('thrown DioException (connection error): mapped userMessage text', (tester) async {
    final error = DioException(
      requestOptions: RequestOptions(path: '/health'),
      type: DioExceptionType.connectionError,
      message: 'SocketException: raw detail',
    );
    await pumpSettings(tester, (_, _) async => throw error);
    await runTest(tester);

    expect(find.text('Bağlantı hatası: ${userMessage(error)}'), findsOneWidget);
    expect(
      userMessage(error),
      'Sunucuya bağlanılamıyor. Lütfen adresi ve bağlantınızı kontrol edin.',
    );
    expect(find.textContaining('SocketException'), findsNothing);
    expectNoRawError();
  });

  testWidgets('while running: button disabled with "Test Ediliyor..."; result after', (
    tester,
  ) async {
    final pending = Completer<bool>();
    await pumpSettings(tester, (_, _) => pending.future);
    await tester.tap(find.text('Bağlantıyı Test Et'));
    await tester.pump();

    expect(find.text('Test Ediliyor...'), findsOneWidget);
    await tester.tap(find.text('Test Ediliyor...'), warnIfMissed: false);
    await tester.pump();
    expect(calls, hasLength(1), reason: 'disabled while running');

    pending.complete(true);
    await tester.pumpAndSettle();
    expect(find.text(_success), findsOneWidget);
    expect(find.text('Bağlantıyı Test Et'), findsOneWidget);
  });

  testWidgets('invalid address: validation error, tester not called', (tester) async {
    await pumpSettings(tester, (_, _) async => true);
    await tester.enterText(urlField, 'gecersiz');
    await runTest(tester);

    expect(find.text('Geçerli bir URL girin (örn: http://host:port)'), findsOneWidget);
    expect(calls, isEmpty);
    expect(find.text(_success), findsNothing);
  });
}
