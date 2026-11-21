// Schedule block form with the one-time ('once') type: the wrapping type
// chips (semantics, tap size, no overflow), hidden recurrence fields, the
// 'Gün' label, the edit note and the request bodies. The repository is the
// server-like fake with real backend JSON; the time picker is never opened.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/presentation/schedule_edit_screen.dart';
import 'package:varys/features/schedule/presentation/schedule_screen.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_schedule_repository.dart';

final _today = scheduleFixtureDay; // 2026-11-02

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

/// The real once block (schedule_list_with_once.json id 2, 2026-11-25),
/// renumbered so it does not clash with schedule_list.json ids.
ScheduleBlock _onceBlock() =>
    (jsonDecode(File('test/fixtures/schedule_list_with_once.json').readAsStringSync()) as List)
        .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
        .firstWhere((b) => b.recurrenceType == RecurrenceType.once)
        .copyWith(id: 50);

const _typeOrder = ['daily', 'weekly', 'monthly', 'interval', 'once'];
const _typeTexts = ['Günlük', 'Haftalık', 'Aylık', 'Aralık', 'Tek sefer'];

void main() {
  late FakeScheduleRepository repo;
  late GoRouter router;

  setUp(() => repo = FakeScheduleRepository([...scheduleListFixture(), _onceBlock()]));

  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(600, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.schedulePath,
      routes: [
        GoRoute(path: AppRouter.schedulePath, builder: (_, _) => const ScheduleScreen()),
        GoRoute(path: AppRouter.scheduleNewPath, builder: (_, _) => const ScheduleEditScreen()),
        GoRoute(
          path: AppRouter.scheduleEditPath,
          builder: (_, state) => ScheduleEditScreen(block: state.extra! as ScheduleBlock),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        nowProvider.overrideWithValue(() => DateTime(2026, 11, 2, 7, 10)),
        scheduleRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCreate(WidgetTester tester, {Size size = const Size(600, 1400)}) async {
    await pumpApp(tester, size: size);
    router.push(AppRouter.scheduleNewPath);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditScreen.createTitle), findsOneWidget);
  }

  ScheduleBlock block(int id) => repo.server.firstWhere((b) => b.id == id);

  Future<void> openEdit(WidgetTester tester, ScheduleBlock b) async {
    await pumpApp(tester);
    router.push(AppRouter.scheduleEditPath, extra: b);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditScreen.editTitle), findsOneWidget);
  }

  final typeSelector = find.byKey(const ValueKey('schedule-type'));
  Finder chip(String type) => find.byKey(ValueKey('schedule-type-$type'));
  final titleField = find.byKey(const ValueKey('schedule-title'));
  final saveButton = find.byKey(const ValueKey('schedule-save'));
  final recurrenceNote = find.byKey(const ValueKey('schedule-recurrence-note'));
  final onceNote = find.byKey(const ValueKey('schedule-once-note'));
  final dayOfMonthField = find.byKey(const ValueKey('schedule-day-of-month'));
  final intervalField = find.byKey(const ValueKey('schedule-interval'));
  Finder weekday(int d) => find.byKey(ValueKey('schedule-weekday-$d'));

  String startDateLabel(WidgetTester tester) => tester
      .widget<InputDecorator>(find.byKey(const ValueKey('schedule-start-date')))
      .decoration
      .labelText!;

  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton).onPressed != null;

  // Same helper as schedule_edit_screen_test.dart: taps the label inside the
  // selector, whatever widget the selector is.
  Future<void> selectType(WidgetTester tester, String label) async {
    final segment = find.descendant(of: typeSelector, matching: find.text(label));
    await tester.pumpAndSettle();
    await tester.ensureVisible(segment);
    await tester.pumpAndSettle();
    await tester.tap(segment);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  group('type chips', () {
    testWidgets('five chips in order, Tek sefer last; each label inside its chip', (tester) async {
      await openCreate(tester);
      final wrap = tester.widget<Wrap>(typeSelector);
      expect(wrap.children.map((c) => (c.key! as ValueKey<String>).value), [
        for (final t in _typeOrder) 'schedule-type-$t',
      ]);
      for (var i = 0; i < _typeOrder.length; i++) {
        expect(
          find.descendant(of: chip(_typeOrder[i]), matching: find.text(_typeTexts[i])),
          findsOneWidget,
        );
      }
    });

    testWidgets('the selected chip reads as selected in semantics, the others not', (tester) async {
      final semantics = tester.ensureSemantics();
      await openCreate(tester);
      void expectSelected(String selected) {
        for (final t in _typeOrder) {
          expect(
            tester.getSemantics(chip(t)),
            isSemantics(isSelected: t == selected, isButton: true),
            reason: '$t (selected: $selected)',
          );
        }
      }

      expectSelected('daily');
      await selectType(tester, 'Tek sefer');
      expectSelected('once');
      await selectType(tester, 'Aylık');
      expectSelected('monthly');
      semantics.dispose();
    });

    testWidgets('tapping the selected chip keeps it selected (never none)', (tester) async {
      await openCreate(tester);
      await selectType(tester, 'Tek sefer');
      await selectType(tester, 'Tek sefer');
      expect(tester.widget<ChoiceChip>(chip('once')).selected, isTrue);
      expect(
        tester.state<ScheduleEditScreenState>(find.byType(ScheduleEditScreen)).mounted,
        isTrue,
      );
      expect(startDateLabel(tester), 'Gün');
    });

    for (final (size, scale) in [(const Size(600, 1400), 1.0), (const Size(360, 800), 1.5)]) {
      testWidgets('${size.width.toInt()}px x$scale: every chip at least 48x48, inside the '
          'screen, label on one line and not truncated, no overflow', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await openCreate(tester, size: size);
        expect(tester.takeException(), isNull);
        for (var i = 0; i < _typeOrder.length; i++) {
          final rect = tester.getRect(chip(_typeOrder[i]));
          expect(rect.height, greaterThanOrEqualTo(48), reason: _typeOrder[i]);
          expect(rect.width, greaterThanOrEqualTo(48), reason: _typeOrder[i]);
          expect(rect.left, greaterThanOrEqualTo(0), reason: _typeOrder[i]);
          expect(rect.right, lessThanOrEqualTo(size.width), reason: _typeOrder[i]);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.descendant(of: chip(_typeOrder[i]), matching: find.text(_typeTexts[i])),
          );
          expect(paragraph.didExceedMaxLines, isFalse, reason: '${_typeTexts[i]} truncated');
          expect(
            paragraph
                .getBoxesForSelection(
                  TextSelection(baseOffset: 0, extentOffset: _typeTexts[i].length),
                )
                .map((b) => b.top)
                .toSet(),
            hasLength(1),
            reason: '${_typeTexts[i]} on one line',
          );
        }
        // Every chip stays tappable at this size.
        await selectType(tester, 'Tek sefer');
        expect(tester.widget<ChoiceChip>(chip('once')).selected, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('once selected', () {
    testWidgets('weekly, monthly and interval fields are hidden; label becomes Gün and back', (
      tester,
    ) async {
      await openCreate(tester);
      expect(startDateLabel(tester), 'Başlangıç tarihi');

      await selectType(tester, 'Haftalık');
      expect(weekday(0), findsOneWidget);
      await selectType(tester, 'Tek sefer');
      expect(weekday(0), findsNothing);
      expect(startDateLabel(tester), 'Gün');

      await selectType(tester, 'Aylık');
      expect(dayOfMonthField, findsOneWidget);
      await selectType(tester, 'Tek sefer');
      expect(dayOfMonthField, findsNothing);
      expect(find.text(monthEndNote), findsNothing);

      await selectType(tester, 'Aralık');
      expect(intervalField, findsOneWidget);
      await selectType(tester, 'Tek sefer');
      expect(intervalField, findsNothing);

      await selectType(tester, 'Günlük');
      expect(startDateLabel(tester), 'Başlangıç tarihi');
    });

    testWidgets('create: sends once, the three fields explicit null, start_date the day; '
        'values typed for other types are dropped; no note on create', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'Doktor');
      await selectType(tester, 'Haftalık');
      await tester.ensureVisible(weekday(2));
      await tester.tap(weekday(2));
      await tester.pumpAndSettle();
      await selectType(tester, 'Tek sefer');
      expect(onceNote, findsNothing, reason: 'the note is for edits only');
      expect(recurrenceNote, findsNothing);
      expect(saveEnabled(tester), isTrue);

      await tapSave(tester);
      final body = repo.createBodies.single;
      expect(body['title'], 'Doktor');
      expect(body['recurrence_type'], 'once');
      expect(body.containsKey('days_of_week'), isTrue);
      expect(body['days_of_week'], isNull);
      expect(body['day_of_month'], isNull);
      expect(body['interval_days'], isNull);
      expect(body['start_date'], _today);
      expect(find.byType(ScheduleScreen), findsOneWidget, reason: 'popped back to the list');
    });
  });

  group('edit', () {
    testWidgets('monthly -> once: once note with the start day, recurrence note too, '
        'no overlap; both hidden again when changed back', (tester) async {
      final monthly = block(4); // day 15, start 2026-11-02
      await openEdit(tester, monthly);
      expect(onceNote, findsNothing);

      await selectType(tester, 'Tek sefer');
      expect(onceNote, findsOneWidget);
      expect(
        tester.widget<Text>(onceNote).data,
        'Tek sefer, bloğun başlangıç gününde olur (2 Kasım).',
      );
      expect(
        ScheduleEditScreen.onceNote(DateTime(2026, 11, 25)),
        'Tek sefer, bloğun başlangıç gününde olur (25 Kasım).',
      );
      expect(recurrenceNote, findsOneWidget);
      final a = tester.getRect(recurrenceNote);
      final b = tester.getRect(onceNote);
      expect(a.overlaps(b), isFalse);
      expect(b.top, greaterThanOrEqualTo(a.bottom), reason: 'once note below the rule note');
      expect(startDateLabel(tester), 'Gün');

      await selectType(tester, 'Aylık');
      expect(onceNote, findsNothing);
      expect(recurrenceNote, findsNothing);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('monthly -> once saves the type with three explicit nulls and no start_date', (
      tester,
    ) async {
      await openEdit(tester, block(4));
      await selectType(tester, 'Tek sefer');
      await tapSave(tester);
      final (id, body) = repo.updateCalls.single;
      expect(id, 4);
      expect(body, {
        'recurrence_type': 'once',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': null,
      });
      expect(body.containsKey('start_date'), isFalse);
    });

    testWidgets('an existing once block: Tek sefer selected, no notes, label Gün, read-only '
        'day; a title edit sends only the title', (tester) async {
      await openEdit(tester, block(50));
      expect(tester.widget<ChoiceChip>(chip('once')).selected, isTrue);
      expect(onceNote, findsNothing);
      expect(recurrenceNote, findsNothing);
      expect(startDateLabel(tester), 'Gün');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('schedule-start-date-text'))).data,
        '25.11.2026',
      );
      expect(find.byKey(const ValueKey('schedule-start-date-button')), findsNothing);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(titleField, 'Diş hekimi');
      await tester.pumpAndSettle();
      await tapSave(tester);
      expect(repo.updateCalls.single.$2, {'title': 'Diş hekimi'});
    });

    testWidgets('once -> weekly: once note never shown, rule note shown, body sends days', (
      tester,
    ) async {
      await openEdit(tester, block(50));
      await selectType(tester, 'Haftalık');
      await tester.ensureVisible(weekday(0));
      await tester.tap(weekday(0));
      await tester.pumpAndSettle();
      expect(onceNote, findsNothing);
      expect(recurrenceNote, findsOneWidget);
      expect(startDateLabel(tester), 'Başlangıç tarihi');
      await tapSave(tester);
      expect(repo.updateCalls.single.$2, {
        'recurrence_type': 'weekly',
        'days_of_week': [0],
        'day_of_month': null,
        'interval_days': null,
      });
    });
  });

  group('list summary', () {
    // Like the other summaries, the line may end in an ellipsis on the
    // narrowest width at 1.5x (the overflow matrix allows 1 line, no wrap).
    for (final (size, scale, whole) in [
      (const Size(360, 900), 1.0, true),
      (const Size(320, 900), 1.5, false),
    ]) {
      testWidgets("${size.width.toInt()}px x$scale: the once row reads 'Tek sefer, 25 Kasım' "
          'on one line', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpApp(tester, size: size);
        final summary = find.byKey(const ValueKey('schedule-list-summary-50'));
        await tester.scrollUntilVisible(summary, 200);
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(summary).data, 'Tek sefer, 25 Kasım');
        expect(tester.widget<Text>(summary).maxLines, 1);
        final paragraph = tester.renderObject<RenderParagraph>(summary);
        expect(paragraph.size.height, lessThan(2 * paragraph.preferredLineHeight));
        if (whole) expect(paragraph.didExceedMaxLines, isFalse, reason: 'not truncated');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
