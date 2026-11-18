import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routine_edit_screen.dart';
import 'package:varys/features/routines/presentation/routines_screen.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 1);
const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);
const _notFound = ServerFailure('Kaynak bulunamadı.', statusCode: 404);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

/// Real backend JSON (GET /routines): ids 1..4, one per recurrence type.
List<Routine> _fixture() =>
    (jsonDecode(File('test/fixtures/routines_list.json').readAsStringSync()) as List<dynamic>)
        .map((e) => Routine.fromJson(e as Map<String, dynamic>))
        .toList();

void main() {
  late _MockRoutineRepository repo;
  late List<Routine> base;

  setUpAll(() => registerFallbackValue(DateTime(2000)));

  setUp(() {
    repo = _MockRoutineRepository();
    base = _fixture();
    when(() => repo.getRoutines()).thenAnswer((_) async => Right(base));
    when(() => repo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(600, 1000),
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRouter.routinesPath,
      routes: [
        GoRoute(path: AppRouter.homePath, builder: (_, _) => const Scaffold()),
        GoRoute(path: AppRouter.routinesPath, builder: (_, _) => const RoutinesScreen()),
        GoRoute(path: AppRouter.routinesNewPath, builder: (_, _) => const RoutineEditScreen()),
        GoRoute(
          path: AppRouter.routinesEditPath,
          builder: (_, state) => RoutineEditScreen(routine: state.extra! as Routine),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          routineRepositoryProvider.overrideWith((ref) async => repo),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Finder row(int id) => find.byKey(ValueKey('routine-row-$id'));
  Finder deleteButton(int id) => find.byKey(ValueKey('routine-delete-$id'));
  Finder dialogButton(String text) =>
      find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

  group('list', () {
    testWidgets('shows title and Turkish recurrence summary per routine, no streaks', (
      tester,
    ) async {
      await pump(tester);
      expect(find.widgetWithText(AppBar, 'Rutinler'), findsOneWidget);
      final expected = {
        1: ('Su iç', 'Her gün'),
        2: ('Spor', 'Pzt, Çar, Cum'),
        3: ('Fatura öde', "Ayın 31'i"),
        4: ('Bitki sula', 'Her 3 günde bir'),
      };
      for (final e in expected.entries) {
        expect(find.descendant(of: row(e.key), matching: find.text(e.value.$1)), findsOneWidget);
        expect(find.descendant(of: row(e.key), matching: find.text(e.value.$2)), findsOneWidget);
      }
      expect(find.textContaining('seri'), findsNothing);
      verify(() => repo.getRoutines()).called(1);
    });

    testWidgets('loading shows a progress indicator, no rows', (tester) async {
      final c = Completer<Either<Failure, List<Routine>>>();
      when(() => repo.getRoutines()).thenAnswer((_) => c.future);
      await pump(tester, settle: false);
      expect(find.byKey(const ValueKey('routines-loading')), findsOneWidget);
      expect(row(1), findsNothing);
      c.complete(Right(base));
      await tester.pumpAndSettle();
      expect(row(1), findsOneWidget);
    });

    testWidgets('empty: "Henüz rutin yok" and "Rutin ekle" opens the create form', (tester) async {
      when(() => repo.getRoutines()).thenAnswer((_) async => const Right([]));
      await pump(tester);
      expect(find.text('Henüz rutin yok'), findsOneWidget);
      final add = find.byKey(const ValueKey('routines-empty-add'));
      expect(find.descendant(of: add, matching: find.text('Rutin ekle')), findsOneWidget);
      final size = tester.getSize(add);
      expect(size.width >= 48 && size.height >= 48, isTrue, reason: '$size');

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(RoutineEditScreen), findsOneWidget);
      expect(find.text(RoutineEditScreen.createTitle), findsOneWidget);
    });

    testWidgets('error shows userMessage text and "Tekrar dene" reloads', (tester) async {
      when(() => repo.getRoutines()).thenAnswer((_) async => const Left(_serverError));
      await pump(tester);
      expect(find.text('Sunucu hatası. Lütfen daha sonra tekrar deneyin.'), findsOneWidget);
      expect(find.textContaining('ServerFailure'), findsNothing);
      expect(row(1), findsNothing);

      when(() => repo.getRoutines()).thenAnswer((_) async => Right(base));
      await tester.tap(find.text('Tekrar dene'));
      await tester.pumpAndSettle();
      expect(row(1), findsOneWidget);
      expect(find.text('Tekrar dene'), findsNothing);
      verify(() => repo.getRoutines()).called(2);
    });
  });

  group('tap targets (at least 48x48)', () {
    testWidgets('AppBar "Rutin ekle": tooltip, >= 48x48, opens the create form', (tester) async {
      await pump(tester);
      final add = find.byKey(const ValueKey('routines-add'));
      expect(find.byTooltip('Rutin ekle'), findsOneWidget);
      final size = tester.getSize(add);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text(RoutineEditScreen.createTitle), findsOneWidget);
    });

    testWidgets('row and its delete button are >= 48x48; row tap opens the edit form', (
      tester,
    ) async {
      await pump(tester, size: const Size(360, 800));
      for (final id in [1, 2, 3, 4]) {
        final rowSize = tester.getSize(row(id));
        expect(rowSize.height, greaterThanOrEqualTo(48), reason: 'row $id');
        expect(rowSize.width, greaterThanOrEqualTo(48), reason: 'row $id');
        final del = tester.getSize(deleteButton(id));
        expect(del.width, greaterThanOrEqualTo(48), reason: 'delete $id');
        expect(del.height, greaterThanOrEqualTo(48), reason: 'delete $id');
      }

      await tester.tap(find.text('Spor'));
      await tester.pumpAndSettle();
      expect(find.text(RoutineEditScreen.editTitle), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('routine-title')),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Spor',
      );
    });
  });

  group('delete', () {
    testWidgets('"Vazgeç" closes the dialog and deletes nothing', (tester) async {
      await pump(tester);
      await tester.tap(deleteButton(2));
      await tester.pumpAndSettle();
      expect(find.text('Bu rutin silinsin mi?'), findsOneWidget);

      await tester.tap(dialogButton('Vazgeç'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(row(2), findsOneWidget);
      verifyNever(() => repo.deleteRoutine(any()));
    });

    testWidgets('"Sil" deletes: row disappears after the server answers', (tester) async {
      await pump(tester);
      when(() => repo.deleteRoutine(any())).thenAnswer((_) async => const Right(null));
      when(() => repo.getRoutines()).thenAnswer((_) async => Right([base[0], base[2], base[3]]));

      await tester.tap(deleteButton(2));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('Sil'));
      await tester.pumpAndSettle();

      verify(() => repo.deleteRoutine(2)).called(1);
      expect(row(2), findsNothing);
      expect(row(1), findsOneWidget);
      expect(find.byType(RoutinesScreen), findsOneWidget);
    });

    testWidgets('double tap on "Sil": exactly one DELETE, page stays open', (tester) async {
      await pump(tester);
      when(() => repo.deleteRoutine(any())).thenAnswer((_) async => const Right(null));

      await tester.tap(deleteButton(2));
      await tester.pumpAndSettle();
      final sil = dialogButton('Sil');
      await tester.tap(sil);
      await tester.tap(sil, warnIfMissed: false);
      await tester.pump();
      await tester.tap(sil, warnIfMissed: false);
      await tester.pumpAndSettle();

      verify(() => repo.deleteRoutine(2)).called(1);
      expect(find.byType(RoutinesScreen), findsOneWidget, reason: 'list page not popped');
      expect(tester.takeException(), isNull);
    });

    testWidgets('failure: snackbar with userMessage, row stays', (tester) async {
      await pump(tester);
      when(() => repo.deleteRoutine(any())).thenAnswer((_) async => const Left(_serverError));

      await tester.tap(deleteButton(3));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('Sil'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Sunucu hatası. Lütfen daha sonra tekrar deneyin.'),
        ),
        findsOneWidget,
      );
      expect(row(3), findsOneWidget);
    });

    testWidgets('404 (deleted elsewhere): snackbar "Kaynak bulunamadı." and the stale row '
        'disappears after a silent re-fetch', (tester) async {
      await pump(tester);
      when(() => repo.deleteRoutine(any())).thenAnswer((_) async => const Left(_notFound));
      when(() => repo.getRoutines()).thenAnswer((_) async => Right([base[0], base[1], base[3]]));

      await tester.tap(deleteButton(3));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('Sil'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.text('Kaynak bulunamadı.')),
        findsOneWidget,
      );
      expect(row(3), findsNothing);
      expect(find.byKey(const ValueKey('routines-loading')), findsNothing);
    });

    testWidgets('delete button is disabled while its request runs', (tester) async {
      await pump(tester);
      final c = Completer<Either<Failure, void>>();
      when(() => repo.deleteRoutine(any())).thenAnswer((_) => c.future);

      await tester.tap(deleteButton(4));
      await tester.pumpAndSettle();
      await tester.tap(dialogButton('Sil'));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(deleteButton(4)).onPressed, isNull);

      c.complete(const Right(null));
      await tester.pumpAndSettle();
      verify(() => repo.deleteRoutine(4)).called(1);
    });
  });
}
