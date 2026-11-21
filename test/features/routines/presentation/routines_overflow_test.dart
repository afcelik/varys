// Overflow guard for /routines and /routines/edit (and the edit error page)
// at every layout breakpoint width and two text scales. Long titles, long
// descriptions, all seven weekday chips, error states, an open error
// snackbar and an open keyboard. Every case: no exception (RenderFlex
// overflow is reported as one) and, on the form, Kaydet can be reached and
// hit. The one-time group (an existing 'Tek sefer' routine, the only case
// where the form offers it) draws the form filled, saving, with the error
// snackbar, with validation messages and with the keyboard open, plus the
// list row, using fixed pump steps (no pumpAndSettle).

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routine_edit_screen.dart';
import 'package:varys/features/routines/presentation/routines_screen.dart';

import '../../../helpers/varys_app_harness.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 1);
const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _scales = [1.0, 1.5];

final _longTitle = List.filled(40, 'Uzunbaşlıklırutin').join(' ').substring(0, 255);
final _longWord = 'A' * 255; // no break opportunity at all
final _longDescription = List.filled(250, 'açıklama').join(' ').substring(0, 2000);

/// Real GET /routines data, with long titles/descriptions added.
List<Routine> _routines() {
  final base =
      (jsonDecode(File('test/fixtures/routines_list.json').readAsStringSync()) as List<dynamic>)
          .map((e) => Routine.fromJson(e as Map<String, dynamic>))
          .toList();
  return [
    base[0].copyWith(title: _longTitle, description: _longDescription),
    base[1].copyWith(title: _longWord, daysOfWeek: [0, 1, 2, 3, 4, 5, 6]),
    base[2],
    base[3].copyWith(intervalDays: 9999),
  ];
}

/// Weekly, all seven days, long title and long description.
Routine _weeklyAllDays() => _routines()[1].copyWith(
  title: _longTitle,
  description: _longDescription,
  daysOfWeek: [0, 1, 2, 3, 4, 5, 6],
);

void main() {
  late _MockRoutineRepository repo;

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(const RoutineChanges());
  });

  setUp(() {
    repo = _MockRoutineRepository();
    when(() => repo.getRoutines()).thenAnswer((_) async => Right(_routines()));
    when(() => repo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
    when(() => repo.updateRoutine(any(), any())).thenAnswer((_) async => const Left(_serverError));
  });

  late GoRouter router;

  Future<void> pumpApp(
    WidgetTester tester,
    Size size,
    double scale, {
    String initial = AppRouter.routinesPath,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: AppRouter.homePath, builder: (_, _) => const Scaffold()),
        GoRoute(path: AppRouter.routinesPath, builder: (_, _) => const RoutinesScreen()),
        GoRoute(path: AppRouter.routinesNewPath, builder: (_, _) => const RoutineEditScreen()),
        GoRoute(
          path: AppRouter.routinesEditPath,
          builder: (_, state) => state.extra is Routine
              ? RoutineEditScreen(routine: state.extra! as Routine)
              : const RoutineEditUnavailablePage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      textScale: scale,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        routineRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    await tester.pumpAndSettle();
  }

  final saveButton = find.byKey(const ValueKey('routine-save'));

  void expectNoException(WidgetTester tester, String label) {
    expect(tester.takeException(), isNull, reason: label);
  }

  /// [finder] is on screen, above [bottomInset] and actually receives a tap
  /// at its center (not covered by a snackbar or the keyboard area).
  Future<void> expectReachableAndHittable(
    WidgetTester tester,
    Finder finder,
    String label, {
    double bottomInset = 0,
  }) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    final viewHeight = tester.view.physicalSize.height;
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(0), reason: '$label: top');
    expect(rect.bottom, lessThanOrEqualTo(viewHeight - bottomInset), reason: '$label: bottom');

    final target = tester.renderObject(finder);
    final hit = tester.hitTestOnBinding(rect.center);
    final hits = hit.path.any((entry) {
      RenderObject? node = entry.target is RenderObject ? entry.target as RenderObject : null;
      while (node != null) {
        if (identical(node, target)) return true;
        node = node.parent;
      }
      return false;
    });
    expect(hits, isTrue, reason: '$label: Kaydet is covered at its center');
  }

  Future<void> openEditWeeklyAllDays(WidgetTester tester) async {
    router.push(AppRouter.routinesEditPath, extra: _weeklyAllDays());
    await tester.pumpAndSettle();
    for (var d = 0; d < 7; d++) {
      expect(tester.widget<FilterChip>(find.byKey(ValueKey('weekday-$d'))).selected, isTrue);
    }
  }

  for (final width in _widths) {
    for (final scale in _scales) {
      final label = '${width.toInt()}px x$scale';
      final size = Size(width, width <= 400 ? 740 : 900);

      testWidgets('/routines: long titles, empty and error states — $label', (tester) async {
        await pumpApp(tester, size, scale);
        expect(find.byKey(const ValueKey('routine-row-1')), findsOneWidget);
        expectNoException(tester, '$label list');

        // Delete dialog with a long title.
        await tester.tap(find.byKey(const ValueKey('routine-delete-2')));
        await tester.pumpAndSettle();
        expect(find.text('Bu rutin silinsin mi?'), findsOneWidget);
        expectNoException(tester, '$label delete dialog');
        await tester.tap(
          find.descendant(of: find.byType(AlertDialog), matching: find.text('Vazgeç')),
        );
        await tester.pumpAndSettle();

        // Error state.
        when(() => repo.getRoutines()).thenAnswer((_) async => const Left(_serverError));
        router.go(AppRouter.homePath);
        await tester.pumpAndSettle();
        router.go(AppRouter.routinesPath);
        await tester.pumpAndSettle();
        expect(find.text('Tekrar dene'), findsOneWidget);
        expectNoException(tester, '$label error');

        // Empty state.
        when(() => repo.getRoutines()).thenAnswer((_) async => const Right([]));
        await tester.tap(find.text('Tekrar dene'));
        await tester.pumpAndSettle();
        expect(find.text('Henüz rutin yok'), findsOneWidget);
        expectNoException(tester, '$label empty');
      });

      testWidgets('/routines/edit: weekly, 7 chips, long title/description, error snackbar '
          '— $label', (tester) async {
        await pumpApp(tester, size, scale);
        await openEditWeeklyAllDays(tester);
        expectNoException(tester, '$label edit weekly');

        // Change the rule (recurrence note shown) and save -> server error.
        await tester.ensureVisible(find.byKey(const ValueKey('weekday-6')));
        await tester.tap(find.byKey(const ValueKey('weekday-6')));
        await tester.pumpAndSettle();
        expect(find.text(recurrenceChangeNote), findsOneWidget);
        await tester.ensureVisible(saveButton);
        await tester.tap(saveButton);
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.byType(RoutineEditScreen), findsOneWidget);
        expectNoException(tester, '$label snackbar');
        await expectReachableAndHittable(tester, saveButton, '$label snackbar');

        // Validation messages at the same time.
        await tester.enterText(find.byKey(const ValueKey('routine-title')), '');
        await tester.pumpAndSettle();
        expect(find.text(titleRequiredMessage), findsOneWidget);
        expectNoException(tester, '$label validation');
      });

      testWidgets('/routines/new: monthly and interval fields — $label', (tester) async {
        await pumpApp(tester, size, scale, initial: AppRouter.routinesNewPath);
        await tester.enterText(find.byKey(const ValueKey('routine-title')), _longTitle);
        for (final type in ['Aylık', 'Aralık', 'Haftalık']) {
          await tester.tap(
            find.descendant(
              of: find.byKey(const ValueKey('routine-type')),
              matching: find.text(type),
            ),
          );
          await tester.pumpAndSettle();
          expectNoException(tester, '$label $type');
        }
        await tester.tap(
          find.descendant(
            of: find.byKey(const ValueKey('routine-type')),
            matching: find.text('Aylık'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const ValueKey('routine-day-of-month')), '1234');
        await tester.pumpAndSettle();
        expect(find.text(dayOfMonthInvalidMessage), findsOneWidget);
        expect(find.text(monthEndNote), findsOneWidget);
        expectNoException(tester, '$label monthly invalid');
        await expectReachableAndHittable(tester, saveButton, '$label new');
      });

      testWidgets('/routines/edit without a Routine: error page — $label', (tester) async {
        await pumpApp(tester, size, scale);
        router.push(AppRouter.routinesEditPath, extra: 'x');
        await tester.pumpAndSettle();
        expect(find.text('Bu sayfa doğrudan açılamaz.'), findsOneWidget);
        expectNoException(tester, '$label unavailable');
      });
    }
  }

  group('keyboard open (viewInsets.bottom = 300)', () {
    for (final (width, scale) in [(360.0, 1.5), (360.0, 1.0), (600.0, 1.5)]) {
      final label = '${width.toInt()}px x$scale';
      testWidgets('edit form, weekly with 7 chips, long text, snackbar open — $label', (
        tester,
      ) async {
        await pumpApp(tester, Size(width, 740), scale);
        await openEditWeeklyAllDays(tester);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expectNoException(tester, '$label keyboard');

        await tester.ensureVisible(find.byKey(const ValueKey('weekday-0')));
        await tester.tap(find.byKey(const ValueKey('weekday-0')));
        await tester.pumpAndSettle();
        await expectReachableAndHittable(tester, saveButton, '$label keyboard', bottomInset: 300);

        await tester.tap(saveButton);
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);
        expectNoException(tester, '$label keyboard + snackbar');
        await expectReachableAndHittable(
          tester,
          saveButton,
          '$label keyboard + snackbar',
          bottomInset: 300,
        );
        verify(() => repo.updateRoutine(2, any())).called(1);
      });
    }
  });

  group('Tek sefer (once) routine', () {
    /// The real once routine (routines_list_with_once.json), worst-case texts.
    Routine onceRoutine() =>
        (jsonDecode(File('test/fixtures/routines_list_with_once.json').readAsStringSync())
                as List<dynamic>)
            .map((e) => Routine.fromJson(e as Map<String, dynamic>))
            .firstWhere((r) => r.recurrenceType == RecurrenceType.once)
            .copyWith(title: _longWord, description: _longDescription);

    const typeTexts = ['Günlük', 'Haftalık', 'Aylık', 'Aralık', 'Tek sefer'];
    final typeSelector = find.byKey(const ValueKey('routine-type'));

    Future<void> steps(WidgetTester tester, [int n = 6]) async {
      for (var i = 0; i < n; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// The edit form for the once routine, pushed over /routines.
    Future<void> pumpOnceForm(WidgetTester tester, Size size, double scale) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      router = GoRouter(
        initialLocation: AppRouter.routinesPath,
        routes: [
          GoRoute(path: AppRouter.routinesPath, builder: (_, _) => const RoutinesScreen()),
          GoRoute(
            path: AppRouter.routinesEditPath,
            builder: (_, state) => RoutineEditScreen(routine: state.extra! as Routine),
          ),
        ],
      );
      addTearDown(router.dispose);
      await pumpVarysApp(
        tester,
        router: router,
        textScale: scale,
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          routineRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
      await steps(tester);
      unawaited(router.push(AppRouter.routinesEditPath, extra: onceRoutine()));
      await steps(tester);
    }

    int drawnLines(WidgetTester tester, Finder finder) {
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final oneLine = TextPainter(
        text: TextSpan(text: 'Ağ', style: (paragraph.text as TextSpan).style),
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      final lines = (tester.getSize(finder).height / oneLine.height).round();
      oneLine.dispose();
      return lines;
    }

    /// Kaydet inside the window above [inset], at least 48 high, not under a
    /// snackbar.
    void expectSave(WidgetTester tester, String label, {double inset = 0}) {
      final rect = tester.getRect(saveButton);
      expect(rect.top, greaterThanOrEqualTo(0), reason: label);
      expect(rect.bottom, lessThanOrEqualTo(tester.view.physicalSize.height - inset), reason: label);
      expect(rect.height, greaterThanOrEqualTo(48), reason: label);
      final snack = find.byType(SnackBar);
      if (snack.evaluate().isNotEmpty) {
        expect(tester.getRect(snack).bottom, lessThanOrEqualTo(rect.top + 0.5), reason: label);
      }
    }

    /// Five segments with Tek sefer selected; the selector at least 48 high and
    /// inside the window; every label one line; no recurrence field.
    Future<void> expectOnceSelector(WidgetTester tester, double width, String label) async {
      await tester.ensureVisible(typeSelector);
      await tester.pump();
      final selector = tester.widget<SegmentedButton<RecurrenceType>>(typeSelector);
      expect(selector.segments, hasLength(5), reason: label);
      expect(selector.selected, {RecurrenceType.once}, reason: label);
      final rect = tester.getRect(typeSelector);
      expect(rect.height, greaterThanOrEqualTo(48), reason: '$label selector height');
      expect(rect.right, lessThanOrEqualTo(width + 0.5), reason: label);
      for (final text in typeTexts) {
        final f = find.descendant(of: typeSelector, matching: find.text(text));
        expect(drawnLines(tester, f), 1, reason: '$label $text lines');
        expect(tester.getRect(f).right, lessThanOrEqualTo(rect.right + 0.5), reason: label);
      }
      for (final key in ['weekday-0', 'routine-day-of-month', 'routine-interval']) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: '$label $key');
      }
    }

    for (final width in _widths) {
      for (final scale in _scales) {
        final label = '${width.toInt()}px x$scale';
        final size = Size(width, width <= 400 ? 740 : 900);

        testWidgets('/routines/edit once, long title/description (filled) — $label', (
          tester,
        ) async {
          await pumpOnceForm(tester, size, scale);
          expectNoException(tester, label);
          expect(find.text(RoutineEditScreen.editTitle), findsOneWidget);
          await expectOnceSelector(tester, width, label);
          await tester.ensureVisible(find.byKey(const ValueKey('routine-start-date-text')));
          await tester.pump();
          expect(drawnLines(tester, find.byKey(const ValueKey('routine-start-date-text'))), 1);
          await tester.ensureVisible(saveButton);
          await tester.pump();
          expectSave(tester, label);
          expect(tester.widget<FilledButton>(saveButton).onPressed, isNull, reason: 'no change');
          expectNoException(tester, label);
        });

        testWidgets('/routines/edit once, saving (request parked) — $label', (tester) async {
          final gate = Completer<Either<Failure, Routine>>();
          addTearDown(() {
            if (!gate.isCompleted) gate.complete(const Left(_serverError));
          });
          when(() => repo.updateRoutine(any(), any())).thenAnswer((_) => gate.future);
          await pumpOnceForm(tester, size, scale);
          await tester.enterText(find.byKey(const ValueKey('routine-title')), 'Vergi');
          await tester.pump();
          await tester.ensureVisible(saveButton);
          await tester.pump();
          await tester.tap(saveButton);
          await steps(tester, 2);
          expectNoException(tester, label);
          expect(tester.widget<FilledButton>(saveButton).onPressed, isNull, reason: 'saving');
          await expectOnceSelector(tester, width, label);
          await tester.ensureVisible(saveButton);
          await tester.pump();
          expectSave(tester, label);
          gate.complete(const Left(_serverError));
          await steps(tester, 2);
          expectNoException(tester, label);
          await tester.pump(const Duration(seconds: 5));
        });

        testWidgets('/routines/edit once, error snackbar open — $label', (tester) async {
          await pumpOnceForm(tester, size, scale);
          await tester.enterText(find.byKey(const ValueKey('routine-title')), _longTitle);
          await tester.pump();
          await tester.ensureVisible(saveButton);
          await tester.pump();
          await tester.tap(saveButton);
          await steps(tester, 4);
          expect(find.byType(SnackBar), findsOneWidget, reason: label);
          expect(find.text(_serverError.userMessage), findsOneWidget);
          expectNoException(tester, label);
          await expectOnceSelector(tester, width, label);
          await tester.ensureVisible(saveButton);
          await tester.pump();
          expectSave(tester, label);
          verify(() => repo.updateRoutine(any(), any())).called(1);
          await tester.pump(const Duration(seconds: 5));
        });

        testWidgets('/routines/edit once, validation message (empty title) — $label', (
          tester,
        ) async {
          await pumpOnceForm(tester, size, scale);
          await tester.enterText(find.byKey(const ValueKey('routine-title')), '');
          await steps(tester, 2);
          expect(find.text(titleRequiredMessage), findsOneWidget, reason: label);
          expectNoException(tester, label);
          await expectOnceSelector(tester, width, label);
          await tester.ensureVisible(saveButton);
          await tester.pump();
          expectSave(tester, label);
          expect(tester.widget<FilledButton>(saveButton).onPressed, isNull, reason: label);
        });

        testWidgets('/routines/edit once, keyboard open (300px) — $label', (tester) async {
          await pumpOnceForm(tester, size, scale);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.enterText(find.byKey(const ValueKey('routine-title')), 'Vergi');
          await steps(tester, 2);
          expectNoException(tester, label);
          await tester.ensureVisible(saveButton);
          await tester.pump();
          expectSave(tester, label, inset: 300);
          await tester.tap(saveButton);
          await steps(tester, 4);
          verify(() => repo.updateRoutine(any(), any())).called(1);
          expectNoException(tester, label);
          await tester.pump(const Duration(seconds: 5));
        });

        testWidgets('/routines list with the once routine: summary one line — $label', (
          tester,
        ) async {
          when(() => repo.getRoutines()).thenAnswer((_) async => Right([onceRoutine()]));
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          router = GoRouter(
            initialLocation: AppRouter.routinesPath,
            routes: [
              GoRoute(path: AppRouter.routinesPath, builder: (_, _) => const RoutinesScreen()),
            ],
          );
          addTearDown(router.dispose);
          await pumpVarysApp(
            tester,
            router: router,
            textScale: scale,
            overrides: [
              todayProvider.overrideWith(_FixedToday.new),
              routineRepositoryProvider.overrideWith((ref) async => repo),
            ],
          );
          await steps(tester);
          expectNoException(tester, label);
          final summary = find.text('Tek sefer, 25 Kasım');
          expect(summary, findsOneWidget, reason: label);
          expect(drawnLines(tester, summary), 1, reason: '$label summary lines');
          expect(tester.getRect(summary).right, lessThanOrEqualTo(width + 0.5));
          final delete = find.byKey(const ValueKey('routine-delete-2'));
          expect(tester.getSize(delete).width, greaterThanOrEqualTo(48), reason: label);
          expect(tester.getSize(delete).height, greaterThanOrEqualTo(48), reason: label);
        });
      }
    }
  });
}
