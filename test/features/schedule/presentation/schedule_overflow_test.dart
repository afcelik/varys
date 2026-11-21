// Overflow matrix for the /schedule page and the block form: 8 window widths
// x text scale 1.0 and 1.5, every state. /schedule: filled (unbroken
// 255-character title, 00:00-23:59, every recurrence summary), empty,
// loading and error. Form: long title and description with all 7 weekday
// chips, the error snackbar open, and the keyboard open. Each test checks
// takeException, drawn line counts of maxLines texts, 48x48 tap targets and
// that Kaydet is reachable. The one-time ('Tek sefer') group draws the form
// with Tek sefer selected (long block switched to it with both notes; empty,
// saving, error snackbar and keyboard on a create from the calendar) and the
// list with a one-time block. pumpAndSettle is never used.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/presentation/schedule_edit_screen.dart';
import 'package:varys/features/schedule/presentation/schedule_new_args.dart';
import 'package:varys/features/schedule/presentation/schedule_screen.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_schedule_repository.dart';

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _textScales = [1.0, 1.5];
const _height = 900.0;
const _editTestPath = '/schedule-edit-test';
const _onceNewTestPath = '/schedule-once-new-test';
final _onceDay = DateTime(2026, 11, 25);
const _typeKeys = ['daily', 'weekly', 'monthly', 'interval', 'once'];
const _typeTexts = ['Günlük', 'Haftalık', 'Aylık', 'Aralık', 'Tek sefer'];

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => scheduleFixtureDay;
}

/// The worst-case block for the form: unbroken 255-character title, a
/// 2000-character description with line breaks, weekly on all 7 days.
ScheduleBlock _longBlock() {
  final base = scheduleListFixture().firstWhere((b) => b.id == 3);
  final description = ('Uzun açıklama satırı ğüşiöç İIı\n' * 80).substring(0, 2000);
  assert(description.runes.length == 2000);
  return base.copyWith(
    description: description,
    recurrenceType: RecurrenceType.weekly,
    daysOfWeek: const [0, 1, 2, 3, 4, 5, 6],
  );
}

void main() {
  late FakeScheduleRepository repo;

  setUp(() => repo = FakeScheduleRepository());

  Future<void> steps(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// [initial]: /schedule, /schedule/new or the edit test route (long block).
  Future<void> pumpAt(
    WidgetTester tester,
    String initial,
    double width,
    double scale, {
    bool wait = true,
  }) async {
    tester.view.physicalSize = Size(width, _height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.schedulePath, builder: (_, _) => const ScheduleScreen()),
        GoRoute(path: AppRouter.scheduleNewPath, builder: (_, _) => const ScheduleEditScreen()),
        GoRoute(
          path: _editTestPath,
          builder: (_, _) => ScheduleEditScreen(block: _longBlock()),
        ),
        // As /schedule/new with ScheduleNewArgs(day: 25 Kasım, once: true).
        GoRoute(
          path: _onceNewTestPath,
          builder: (_, _) {
            final args = ScheduleNewArgs(day: _onceDay, once: true);
            return ScheduleEditScreen(initialDay: args.day, initialOnce: args.once);
          },
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
        nowProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9, 10)),
        scheduleRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    if (wait) await steps(tester);
  }

  /// Lines the text at [finder] really draws ('Ağ' line-height reference).
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

  void expectTarget(WidgetTester tester, Finder f, String what) {
    expect(f, findsOneWidget, reason: what);
    final size = tester.getSize(f);
    expect(size.width, greaterThanOrEqualTo(48), reason: '$what width');
    expect(size.height, greaterThanOrEqualTo(48), reason: '$what height');
  }

  void expectAddButton(WidgetTester tester, String label) =>
      expectTarget(tester, find.byKey(const ValueKey('schedule-add')), '$label add');

  /// Kaydet: drawn inside the window, at least 48 high, never under a snackbar.
  void expectSaveReachable(WidgetTester tester, String label, {double bottomLimit = _height}) {
    final save = find.byKey(const ValueKey('schedule-save'));
    expect(save, findsOneWidget, reason: label);
    final rect = tester.getRect(save);
    expect(rect.top, greaterThanOrEqualTo(0), reason: '$label Kaydet top');
    expect(rect.bottom, lessThanOrEqualTo(bottomLimit), reason: '$label Kaydet bottom');
    expect(rect.height, greaterThanOrEqualTo(48), reason: '$label Kaydet height');
    final snack = find.byType(SnackBar);
    if (snack.evaluate().isNotEmpty) {
      expect(
        tester.getRect(snack).bottom,
        lessThanOrEqualTo(rect.top + 0.5),
        reason: '$label snackbar above Kaydet',
      );
    }
  }

  group('/schedule page', () {
    for (final width in _widths) {
      for (final scale in _textScales) {
        final label = '${width.toInt()}px x$scale';

        testWidgets('filled (255 unbroken title, 00:00-23:59, every summary), $label', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 2400); // the whole list on screen
          await pumpAt(tester, AppRouter.schedulePath, width, scale);
          tester.view.physicalSize = Size(width, 2400);
          await steps(tester, 2);
          expect(tester.takeException(), isNull, reason: label);

          final long = find.byKey(const ValueKey('schedule-list-title-3'));
          expect(tester.widget<Text>(long).data!.runes.length, 255);
          expect(drawnLines(tester, long), 2, reason: '$label long title lines');
          expect(tester.renderObject<RenderParagraph>(long).didExceedMaxLines, isTrue);
          for (final id in [6, 1, 2, 3, 7, 4, 5]) {
            for (final (key, max) in [('time', 1), ('summary', 1), ('title', 2)]) {
              final f = find.byKey(ValueKey('schedule-list-$key-$id'));
              expect(drawnLines(tester, f), inInclusiveRange(1, max), reason: '$label $key $id');
            }
            expectTarget(tester, find.byKey(ValueKey('schedule-delete-$id')), '$label delete $id');
            expect(
              tester.getSize(find.byKey(ValueKey('schedule-list-tap-$id'))).height,
              greaterThanOrEqualTo(48),
            );
            final row = tester.getRect(find.byKey(ValueKey('schedule-list-row-$id')));
            expect(row.right, lessThanOrEqualTo(width + 0.5), reason: '$label row $id');
          }
          expect(find.text('00:00\u201323:59'), findsOneWidget);
          expectAddButton(tester, label);
        });

        testWidgets('empty, $label', (tester) async {
          repo.server = [];
          await pumpAt(tester, AppRouter.schedulePath, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expect(find.text(ScheduleScreen.emptyText), findsOneWidget);
          expectTarget(tester, find.byKey(const ValueKey('schedule-empty-add')), label);
          expectAddButton(tester, label);
        });

        testWidgets('loading, $label', (tester) async {
          repo.listGate = Completer<void>();
          addTearDown(() {
            if (!repo.listGate!.isCompleted) repo.listGate!.complete();
          });
          await pumpAt(tester, AppRouter.schedulePath, width, scale, wait: false);
          await tester.pump();
          await tester.pump();
          expect(tester.takeException(), isNull, reason: label);
          expect(find.byKey(const ValueKey('schedule-loading')), findsOneWidget);
          expectAddButton(tester, label);
          repo.listGate!.complete();
          await steps(tester, 2);
        });

        testWidgets('error, $label', (tester) async {
          const failure = ServerFailure(
            'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
            statusCode: 500,
          );
          repo.listFailure = failure;
          await pumpAt(tester, AppRouter.schedulePath, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expect(find.text(userMessage(failure)), findsOneWidget);
          expectTarget(tester, find.byKey(const ValueKey('schedule-retry')), label);
          expectAddButton(tester, label);
        });
      }
    }
  });

  group('block form', () {
    for (final width in _widths) {
      for (final scale in _textScales) {
        final label = '${width.toInt()}px x$scale';

        testWidgets('edit, long title + 2000-char description + 7 weekday chips, $label', (
          tester,
        ) async {
          await pumpAt(tester, _editTestPath, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expect(find.text(ScheduleEditScreen.editTitle), findsOneWidget);
          for (var d = 0; d < 7; d++) {
            final chip = find.byKey(ValueKey('schedule-weekday-$d'));
            await tester.ensureVisible(chip);
            await tester.pump();
            expect(tester.widget<FilterChip>(chip).selected, isTrue);
            expect(tester.getSize(chip).height, greaterThanOrEqualTo(48), reason: '$label chip');
            expect(tester.getRect(chip).right, lessThanOrEqualTo(width + 0.5));
          }
          for (final key in ['schedule-start-time', 'schedule-end-time']) {
            await tester.ensureVisible(find.byKey(ValueKey(key)));
            await tester.pump();
            expect(tester.getSize(find.byKey(ValueKey(key))).height, greaterThanOrEqualTo(48));
            expect(drawnLines(tester, find.byKey(ValueKey('$key-text'))), 1, reason: key);
          }
          await tester.ensureVisible(find.byKey(const ValueKey('schedule-start-date-text')));
          await tester.pump();
          expect(drawnLines(tester, find.byKey(const ValueKey('schedule-start-date-text'))), 1);
          expect(tester.takeException(), isNull, reason: label);
          expectSaveReachable(tester, label);
        });

        testWidgets('create, error snackbar open, $label', (tester) async {
          repo.createFailure = const ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);
          await pumpAt(tester, AppRouter.scheduleNewPath, width, scale);
          await tester.enterText(find.byKey(const ValueKey('schedule-title')), 'ş' * 255);
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('schedule-save')));
          await steps(tester, 4);
          expect(repo.createBodies, hasLength(1));
          expect(find.byType(SnackBar), findsOneWidget);
          expect(tester.takeException(), isNull, reason: label);
          expectSaveReachable(tester, label);
          await tester.pump(const Duration(seconds: 5));
        });

        testWidgets('create, keyboard open (300px), $label', (tester) async {
          await pumpAt(tester, AppRouter.scheduleNewPath, width, scale);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.enterText(find.byKey(const ValueKey('schedule-title')), 'Spor');
          await steps(tester, 2);
          expect(tester.takeException(), isNull, reason: label);
          expectSaveReachable(tester, label, bottomLimit: _height - 300);
          await tester.tap(find.byKey(const ValueKey('schedule-save')));
          await steps(tester, 4);
          expect(repo.createBodies, hasLength(1), reason: '$label Kaydet tappable');
        });
      }
    }
  });

  group('Tek sefer (once)', () {
    final save = find.byKey(const ValueKey('schedule-save'));
    final onceNote = find.byKey(const ValueKey('schedule-once-note'));
    final ruleNote = find.byKey(const ValueKey('schedule-recurrence-note'));
    Finder chip(String type) => find.byKey(ValueKey('schedule-type-$type'));

    /// Every type chip: >= 48x48, inside the window, its label on one line;
    /// Tek sefer selected; the start date field labelled 'Gün', one line.
    Future<void> expectOnceForm(WidgetTester tester, double width, String label) async {
      for (var i = 0; i < _typeKeys.length; i++) {
        final c = chip(_typeKeys[i]);
        await tester.ensureVisible(c);
        await tester.pump();
        expectTarget(tester, c, '$label chip ${_typeKeys[i]}');
        expect(tester.getRect(c).left, greaterThanOrEqualTo(0), reason: label);
        expect(tester.getRect(c).right, lessThanOrEqualTo(width + 0.5), reason: label);
        final text = find.descendant(of: c, matching: find.text(_typeTexts[i]));
        expect(drawnLines(tester, text), 1, reason: '$label ${_typeTexts[i]} lines');
      }
      expect(tester.widget<ChoiceChip>(chip('once')).selected, isTrue, reason: label);
      for (final key in ['schedule-weekday-0', 'schedule-day-of-month', 'schedule-interval']) {
        expect(find.byKey(ValueKey(key)), findsNothing, reason: '$label $key hidden');
      }
      final date = find.byKey(const ValueKey('schedule-start-date'));
      await tester.ensureVisible(date);
      await tester.pump();
      expect(
        tester.widget<InputDecorator>(date).decoration.labelText,
        ScheduleEditScreen.onceDayLabel,
      );
      expect(drawnLines(tester, find.byKey(const ValueKey('schedule-start-date-text'))), 1);
      for (final key in ['schedule-start-time', 'schedule-end-time']) {
        await tester.ensureVisible(find.byKey(ValueKey(key)));
        await tester.pump();
        expect(tester.getSize(find.byKey(ValueKey(key))).height, greaterThanOrEqualTo(48));
        expect(drawnLines(tester, find.byKey(ValueKey('$key-text'))), 1, reason: key);
      }
    }

    for (final width in _widths) {
      for (final scale in _textScales) {
        final label = '${width.toInt()}px x$scale';

        testWidgets('edit, long block switched to Tek sefer: both notes apart, $label', (
          tester,
        ) async {
          await pumpAt(tester, _editTestPath, width, scale);
          await tester.ensureVisible(chip('once'));
          await tester.pump();
          await tester.tap(chip('once'));
          await steps(tester, 2);
          expect(tester.takeException(), isNull, reason: label);
          await expectOnceForm(tester, width, label);
          await tester.ensureVisible(onceNote);
          await tester.pump();
          expect(ruleNote, findsOneWidget, reason: label);
          expect(tester.getRect(onceNote).overlaps(tester.getRect(ruleNote)), isFalse);
          expect(tester.getRect(onceNote).right, lessThanOrEqualTo(width + 0.5));
          expect(tester.widget<Text>(onceNote).data, ScheduleEditScreen.onceNote(DateTime(2026, 11, 2)));
          expect(tester.takeException(), isNull, reason: label);
          expectSaveReachable(tester, label);
          expect(tester.widget<FilledButton>(save).onPressed, isNotNull, reason: label);
        });

        testWidgets('create from the calendar, empty title: Kaydet disabled, $label', (
          tester,
        ) async {
          await pumpAt(tester, _onceNewTestPath, width, scale);
          expect(tester.takeException(), isNull, reason: label);
          expect(find.text(ScheduleEditScreen.createTitle), findsOneWidget);
          await expectOnceForm(tester, width, label);
          expect(
            tester.widget<Text>(find.byKey(const ValueKey('schedule-start-date-text'))).data,
            '25.11.2026',
          );
          expect(onceNote, findsNothing, reason: 'create shows no once note');
          expectSaveReachable(tester, label);
          expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: label);
        });

        testWidgets('create once, saving (request parked), $label', (tester) async {
          final gate = repo.mutationGate = Completer<void>();
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
          await pumpAt(tester, _onceNewTestPath, width, scale);
          await tester.enterText(find.byKey(const ValueKey('schedule-title')), 'ş' * 255);
          await tester.pump();
          await tester.tap(save);
          await steps(tester, 2);
          expect(repo.createBodies.single['recurrence_type'], 'once');
          expect(tester.takeException(), isNull, reason: label);
          expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: '$label saving');
          expect(tester.widget<ChoiceChip>(chip('once')).onSelected, isNull, reason: label);
          expectSaveReachable(tester, label);
          gate.complete();
          await steps(tester, 2);
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('create once, error snackbar open, 255 title, $label', (tester) async {
          repo.createFailure = const ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);
          await pumpAt(tester, _onceNewTestPath, width, scale);
          await tester.enterText(find.byKey(const ValueKey('schedule-title')), 'ş' * 255);
          await tester.pump();
          await tester.tap(save);
          await steps(tester, 4);
          expect(repo.createBodies.single['recurrence_type'], 'once');
          expect(find.byType(SnackBar), findsOneWidget);
          expect(find.text('Gönderilen veriler geçersiz.'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: label);
          await expectOnceForm(tester, width, label);
          expectSaveReachable(tester, label);
          await tester.pump(const Duration(seconds: 5));
        });

        testWidgets('create once, keyboard open (300px), $label', (tester) async {
          await pumpAt(tester, _onceNewTestPath, width, scale);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.enterText(find.byKey(const ValueKey('schedule-title')), 'Doktor');
          await steps(tester, 2);
          expect(tester.takeException(), isNull, reason: label);
          expectSaveReachable(tester, label, bottomLimit: _height - 300);
          await tester.tap(save);
          await steps(tester, 4);
          final body = repo.createBodies.single;
          expect(body['recurrence_type'], 'once', reason: '$label Kaydet tappable');
          expect(body['start_date'], _onceDay);
        });

        testWidgets('/schedule with a one-time block (255 title): summary one line, $label', (
          tester,
        ) async {
          final once = scheduleListFixture().first.copyWith(
            id: 90,
            title: 'Ö' * 255,
            recurrenceType: RecurrenceType.once,
            startDate: _onceDay,
          );
          repo.server = [...scheduleListFixture(), once];
          tester.view.physicalSize = Size(width, 2400);
          await pumpAt(tester, AppRouter.schedulePath, width, scale);
          tester.view.physicalSize = Size(width, 2400);
          await steps(tester, 2);
          final summary = find.byKey(const ValueKey('schedule-list-summary-90'));
          await tester.ensureVisible(summary);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: label);
          expect(tester.widget<Text>(summary).data, 'Tek sefer, 25 Kasım');
          expect(drawnLines(tester, summary), 1, reason: '$label summary lines');
          final title = find.byKey(const ValueKey('schedule-list-title-90'));
          expect(drawnLines(tester, title), 2, reason: '$label title lines');
          expectTarget(tester, find.byKey(const ValueKey('schedule-delete-90')), label);
          expect(
            tester.getSize(find.byKey(const ValueKey('schedule-list-tap-90'))).height,
            greaterThanOrEqualTo(48),
          );
          final row = tester.getRect(find.byKey(const ValueKey('schedule-list-row-90')));
          expect(row.right, lessThanOrEqualTo(width + 0.5), reason: label);
        });
      }
    }
  });
}
