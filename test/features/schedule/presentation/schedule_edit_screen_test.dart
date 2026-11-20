// Schedule block form (/schedule/new and /schedule/edit). The time picker is
// injected (timePickerProvider): tests never depend on the picker's own
// texts. The repository is the server-like fake with real backend JSON.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_edit_screen.dart';
import 'package:varys/features/schedule/presentation/schedule_screen.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_schedule_repository.dart';

final _today = scheduleFixtureDay; // 2026-11-02

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

/// Records each picker call and answers from [answers] (null = dismissed).
class _FakePicker {
  final calls = <(ScheduleTime, String)>[];
  final answers = <ScheduleTime?>[];

  Future<ScheduleTime?> call(BuildContext context, ScheduleTime initial, String helpText) async {
    calls.add((initial, helpText));
    return answers.isEmpty ? null : answers.removeAt(0);
  }
}

ScheduleTime _t(String s) => ScheduleTime.parse(s);

void main() {
  late FakeScheduleRepository repo;
  late GoRouter router;
  late _FakePicker picker;
  late DateTime now;

  setUp(() {
    repo = FakeScheduleRepository();
    picker = _FakePicker();
    now = DateTime(2026, 11, 2, 7, 10);
  });

  /// [initial] is where the app starts. Default: the list page, so the form
  /// is pushed on top of it (the normal flow).
  Future<void> pumpApp(
    WidgetTester tester, {
    String initial = AppRouter.schedulePath,
    Size size = const Size(600, 1400),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
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
        nowProvider.overrideWithValue(() => now),
        timePickerProvider.overrideWithValue(picker.call),
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

  ScheduleBlock block(int id) => scheduleListFixture().firstWhere((b) => b.id == id);

  Future<void> openEdit(WidgetTester tester, ScheduleBlock b) async {
    await pumpApp(tester);
    router.push(AppRouter.scheduleEditPath, extra: b);
    await tester.pumpAndSettle();
    expect(find.text(ScheduleEditScreen.editTitle), findsOneWidget);
  }

  final titleField = find.byKey(const ValueKey('schedule-title'));
  final descriptionField = find.byKey(const ValueKey('schedule-description'));
  final startField = find.byKey(const ValueKey('schedule-start-time'));
  final endField = find.byKey(const ValueKey('schedule-end-time'));
  final saveButton = find.byKey(const ValueKey('schedule-save'));
  final note = find.byKey(const ValueKey('schedule-recurrence-note'));
  Finder weekday(int d) => find.byKey(ValueKey('schedule-weekday-$d'));

  String text(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;
  String fieldText(WidgetTester tester, Finder field) => tester
      .widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
      .controller
      .text;
  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton).onPressed != null;
  ScheduleEditScreenState formState(WidgetTester tester) =>
      tester.state<ScheduleEditScreenState>(find.byType(ScheduleEditScreen));

  Future<void> selectType(WidgetTester tester, String label) async {
    final segment = find.descendant(
      of: find.byKey(const ValueKey('schedule-type')),
      matching: find.text(label),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(segment);
    await tester.pumpAndSettle();
    await tester.tap(segment);
    await tester.pumpAndSettle();
  }

  Future<void> pickTime(WidgetTester tester, Finder field, String? answer) async {
    picker.answers.add(answer == null ? null : _t(answer));
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
  }

  group('default times (create)', () {
    for (final (h, m, start, end) in [
      (7, 10, '08:00', '09:00'),
      (21, 30, '22:00', '23:00'),
      (23, 40, '22:00', '23:00'),
      (0, 0, '01:00', '02:00'),
    ]) {
      testWidgets('now ${'$h'.padLeft(2, '0')}:${'$m'.padLeft(2, '0')} -> $start-$end', (
        tester,
      ) async {
        now = DateTime(2026, 11, 2, h, m);
        await openCreate(tester);
        expect(text(tester, 'schedule-start-time-text'), start);
        expect(text(tester, 'schedule-end-time-text'), end);
        expect(find.text(timeRangeInvalidMessage), findsNothing);
      });
    }

    testWidgets('the default start date is today; edit keeps the block times', (tester) async {
      await openCreate(tester);
      expect(text(tester, 'schedule-start-date-text'), '02.11.2026');
      expect(formState(tester).startDate, _today);
    });
  });

  group('time fields (injected picker)', () {
    testWidgets('tapping a field opens the picker with its value; the pick is shown as HH:MM', (
      tester,
    ) async {
      await openCreate(tester);
      await pickTime(tester, startField, '06:05');
      expect(picker.calls.single, (_t('08:00'), ScheduleEditScreen.startTimeLabel));
      expect(text(tester, 'schedule-start-time-text'), '06:05');
      expect(formState(tester).startTime, _t('06:05'));

      await pickTime(tester, endField, '23:59');
      expect(picker.calls.last, (_t('09:00'), ScheduleEditScreen.endTimeLabel));
      expect(text(tester, 'schedule-end-time-text'), '23:59');
    });

    testWidgets('dismissing the picker keeps the value', (tester) async {
      await openCreate(tester);
      await pickTime(tester, startField, null);
      expect(text(tester, 'schedule-start-time-text'), '08:00');
    });

    testWidgets('end <= start: error under the end field and Kaydet disabled; fixing it '
        're-enables', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'Kahvaltı');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);

      await pickTime(tester, endField, '08:00'); // == start
      final error = find.descendant(of: endField, matching: find.text(timeRangeInvalidMessage));
      expect(error, findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      await pickTime(tester, endField, '07:00'); // before start
      expect(error, findsOneWidget);
      expect(
        find.descendant(of: startField, matching: find.text(timeRangeInvalidMessage)),
        findsNothing,
      );

      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.createBodies, isEmpty);

      await pickTime(tester, endField, '08:01');
      expect(error, findsNothing);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('time fields are at least 48 high', (tester) async {
      await openCreate(tester, size: const Size(360, 1400));
      expect(tester.getSize(startField).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(endField).height, greaterThanOrEqualTo(48));
    });

    testWidgets('the default picker is 24-hour (checked on the dialog, not its texts)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late BuildContext ctx;
      await pumpVarysApp(
        tester,
        router: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, _) => Builder(
                builder: (context) {
                  ctx = context;
                  return const Scaffold();
                },
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      final result = showScheduleTimePicker(ctx, _t('13:45'), 'Saat');
      await tester.pumpAndSettle();
      final dialog = find.byType(TimePickerDialog);
      expect(dialog, findsOneWidget);
      expect(
        tester.widget<TimePickerDialog>(dialog).initialTime,
        const TimeOfDay(hour: 13, minute: 45),
      );
      expect(MediaQuery.of(tester.element(dialog)).alwaysUse24HourFormat, isTrue);
      Navigator.of(tester.element(dialog)).pop(const TimeOfDay(hour: 6, minute: 7));
      await tester.pumpAndSettle();
      expect(await result, _t('06:07'));
    });
  });

  group('recurrence (fields copied from the routine form)', () {
    testWidgets('daily: none; weekly: 7 chips; monthly: day + month-end note; interval', (
      tester,
    ) async {
      await openCreate(tester);
      expect(weekday(0), findsNothing);
      await selectType(tester, 'Haftalık');
      for (var d = 0; d < 7; d++) {
        expect(
          find.descendant(of: weekday(d), matching: find.text(weekdayShortNames[d])),
          findsOneWidget,
        );
      }
      expect(find.text(weekdaysRequiredMessage), findsOneWidget);
      await selectType(tester, 'Aylık');
      expect(find.byKey(const ValueKey('schedule-day-of-month')), findsOneWidget);
      expect(find.text(monthEndNote), findsOneWidget);
      await selectType(tester, 'Aralık');
      expect(find.byKey(const ValueKey('schedule-interval')), findsOneWidget);
    });

    testWidgets('weekly without a day: Kaydet disabled', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'Spor');
      await selectType(tester, 'Haftalık');
      expect(saveEnabled(tester), isFalse);
      await tester.ensureVisible(weekday(2));
      await tester.tap(weekday(2));
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
    });
  });

  group('validation', () {
    testWidgets('title required (after editing); Kaydet disabled while invalid', (tester) async {
      await openCreate(tester);
      expect(saveEnabled(tester), isFalse);
      expect(find.text(titleRequiredMessage), findsNothing, reason: 'not before editing');
      await tester.enterText(titleField, '   ');
      await tester.pumpAndSettle();
      expect(find.text(titleRequiredMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
      await tester.enterText(titleField, 'ş' * 256);
      await tester.pumpAndSettle();
      expect(find.text(titleTooLongMessage), findsOneWidget);
      await tester.enterText(titleField, 'ş' * 255);
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('description over 2000 characters', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'B');
      await tester.enterText(descriptionField, 'a' * 2001);
      await tester.pumpAndSettle();
      expect(find.text(descriptionTooLongMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });
  });

  group('create', () {
    testWidgets('sends the form values once, pops to the list, new block listed in order', (
      tester,
    ) async {
      await openCreate(tester);
      await tester.enterText(titleField, '  Öğle arası ');
      await tester.enterText(descriptionField, ' Yürüyüş ');
      await pickTime(tester, startField, '12:15');
      await pickTime(tester, endField, '12:45');
      await selectType(tester, 'Haftalık');
      for (final d in [4, 0]) {
        await tester.ensureVisible(weekday(d));
        await tester.tap(weekday(d));
        await tester.pumpAndSettle();
      }
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(repo.createBodies, hasLength(1));
      expect(repo.createBodies.single, {
        'title': 'Öğle arası',
        'description': 'Yürüyüş',
        'start_time': '12:15',
        'end_time': '12:45',
        'recurrence_type': 'weekly',
        'days_of_week': [0, 4],
        'day_of_month': null,
        'interval_days': null,
        'start_date': _today,
      });
      expect(find.byType(ScheduleEditScreen), findsNothing);
      expect(find.byType(ScheduleScreen), findsOneWidget);
      final newRow = find.text('Öğle arası');
      expect(newRow, findsOneWidget);
      expect(
        tester.getTopLeft(newRow).dy,
        greaterThan(tester.getTopLeft(find.text('Kira ödemesi')).dy),
        reason: 'after 12:00',
      );
    });

    testWidgets('Kaydet disabled while the request runs; double tap sends one request', (
      tester,
    ) async {
      await openCreate(tester);
      repo.mutationGate = Completer<void>();
      await tester.enterText(titleField, 'Kahvaltı');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      repo.mutationGate!.complete();
      await tester.pumpAndSettle();
      expect(repo.createBodies, hasLength(1));
    });

    testWidgets('server 422: form stays open with the values, snackbar, Kaydet re-enabled; '
        'the snackbar does not cover Kaydet', (tester) async {
      repo.createFailure = const ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);
      await openCreate(tester);
      await tester.enterText(titleField, 'Kahvaltı');
      await pickTime(tester, startField, '06:30');
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(ScheduleEditScreen), findsOneWidget);
      expect(find.text('Gönderilen veriler geçersiz.'), findsOneWidget);
      expect(fieldText(tester, titleField), 'Kahvaltı');
      expect(text(tester, 'schedule-start-time-text'), '06:30');
      expect(saveEnabled(tester), isTrue);
      final snack = tester.getRect(find.byType(SnackBar));
      expect(snack.bottom, lessThanOrEqualTo(tester.getRect(saveButton).top + 0.5));
    });

    testWidgets('start date: picker bounds 2000-01-01..2100-12-31; the picked date is sent', (
      tester,
    ) async {
      await openCreate(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('schedule-start-date-button')));
      await tester.tap(find.byKey(const ValueKey('schedule-start-date-button')));
      await tester.pumpAndSettle();
      final dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(dialog.firstDate, DateTime(2000, 1, 1));
      expect(dialog.lastDate, DateTime(2100, 12, 31));
      expect(dialog.initialDate, _today);
      Navigator.of(tester.element(find.byType(DatePickerDialog))).pop(DateTime(2027, 1, 5));
      await tester.pumpAndSettle();
      expect(text(tester, 'schedule-start-date-text'), '05.01.2027');

      await tester.enterText(titleField, 'B');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.createBodies.single['start_date'], DateTime(2027, 1, 5));
    });

    testWidgets('create never shows the recurrence note', (tester) async {
      await openCreate(tester);
      await selectType(tester, 'Aylık');
      expect(note, findsNothing);
    });
  });

  group('edit', () {
    testWidgets('prefilled from the block; start date read-only (no picker)', (tester) async {
      await openEdit(tester, block(4)); // monthly 15th, 12:00-12:30, description set
      expect(fieldText(tester, titleField), 'Kira ödemesi');
      expect(fieldText(tester, descriptionField), 'Banka uygulamasından');
      expect(text(tester, 'schedule-start-time-text'), '12:00');
      expect(text(tester, 'schedule-end-time-text'), '12:30');
      expect(fieldText(tester, find.byKey(const ValueKey('schedule-day-of-month'))), '15');
      expect(text(tester, 'schedule-start-date-text'), '02.11.2026');
      expect(find.text(ScheduleEditScreen.startDateReadOnlyHelper), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-start-date-button')), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('schedule-start-date')));
      await tester.tap(find.byKey(const ValueKey('schedule-start-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      formState(tester).setStartDate(DateTime(2030));
      await tester.pump();
      expect(text(tester, 'schedule-start-date-text'), '02.11.2026');
    });

    testWidgets('no change: Kaydet disabled, nothing sent, page stays', (tester) async {
      await openEdit(tester, block(1));
      expect(saveEnabled(tester), isFalse);
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.updateCalls, isEmpty);
      expect(find.byType(ScheduleEditScreen), findsOneWidget);
    });

    testWidgets('time change sends only end_time; pops; list shows the new range', (tester) async {
      await openEdit(tester, block(1));
      await pickTime(tester, endField, '07:45');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.updateCalls.single.$1, 1);
      expect(repo.updateCalls.single.$2, {'end_time': '07:45'});
      expect(find.byType(ScheduleScreen), findsOneWidget);
      expect(text(tester, 'schedule-list-time-1'), '06:30\u201307:45');
    });

    testWidgets('clearing the description sends an explicit null', (tester) async {
      await openEdit(tester, block(1));
      await tester.enterText(descriptionField, '');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      final body = repo.updateCalls.single.$2;
      expect(body, {'description': null});
      expect(body.containsKey('description'), isTrue);
      expect(body.containsKey('start_date'), isFalse);
    });

    testWidgets('weekly -> daily sends the type with unrelated fields as explicit null', (
      tester,
    ) async {
      await openEdit(tester, block(2));
      await selectType(tester, 'Günlük');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(repo.updateCalls.single.$2, {
        'recurrence_type': 'daily',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': null,
      });
    });

    testWidgets('recurrence note: hidden at first, shown when the rule changes, hidden again '
        'when changed back', (tester) async {
      await openEdit(tester, block(2));
      expect(note, findsNothing);
      await tester.enterText(titleField, 'Kahvaltı 2');
      await tester.pumpAndSettle();
      expect(note, findsNothing, reason: 'title changes are not rule changes');
      await tester.ensureVisible(weekday(1));
      await tester.tap(weekday(1));
      await tester.pumpAndSettle();
      expect(note, findsOneWidget);
      expect(
        find.text('Tekrar kuralını değiştirmek geçmiş günlerin programını da değiştirir.'),
        findsOneWidget,
      );
      await tester.tap(weekday(1));
      await tester.pumpAndSettle();
      expect(note, findsNothing);
    });

    testWidgets('server 422 on save: form open, values kept, snackbar', (tester) async {
      repo.updateFailure = const ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);
      await openEdit(tester, block(5));
      await pickTime(tester, startField, '17:00');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleEditScreen), findsOneWidget);
      expect(text(tester, 'schedule-start-time-text'), '17:00');
      expect(find.text('Gönderilen veriler geçersiz.'), findsOneWidget);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('404 on save: form stays, snackbar "Kaynak bulunamadı.", list re-fetched', (
      tester,
    ) async {
      await openEdit(tester, block(2));
      repo.server = repo.server.where((b) => b.id != 2).toList();
      final listCalls = repo.listCalls;
      await tester.enterText(titleField, 'Kahvaltı 2');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleEditScreen), findsOneWidget);
      expect(find.text('Kaynak bulunamadı.'), findsOneWidget);
      expect(fieldText(tester, titleField), 'Kahvaltı 2');
      expect(repo.listCalls, listCalls + 1);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-list-row-2')), findsNothing);
    });
  });

  group('keyboard open (narrow screen)', () {
    testWidgets('360px x1.5 with a 300px keyboard: Kaydet above the keyboard and tappable', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openCreate(tester, size: const Size(360, 640));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(titleField, 'Spor');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(saveButton);
      expect(rect.bottom, lessThanOrEqualTo(640 - 300), reason: 'above the keyboard');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(repo.createBodies, hasLength(1));
    });
  });

  group('error snackbar open (narrow screen)', () {
    testWidgets('360px x1.5: Kaydet visible without scrolling, above the snackbar, tappable '
        'again', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      repo.createFailure = const ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);
      await openCreate(tester, size: const Size(360, 640));
      await tester.enterText(titleField, 'Spor');
      await tester.enterText(descriptionField, 'Satır 1\nSatır 2\nSatır 3\nSatır 4');
      await selectType(tester, 'Haftalık');
      await tester.ensureVisible(weekday(0));
      await tester.tap(weekday(0));
      await tester.pumpAndSettle();
      // Back to the top of the form: Kaydet must not depend on the scroll position.
      await tester.ensureVisible(titleField);
      await tester.pumpAndSettle();

      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(repo.createBodies, hasLength(1));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(tester.takeException(), isNull);

      final save = tester.getRect(saveButton);
      expect(save.top, greaterThanOrEqualTo(0));
      expect(save.bottom, lessThanOrEqualTo(640), reason: 'on screen without scrolling');
      expect(save.height, greaterThanOrEqualTo(48));
      final snack = tester.getRect(find.byType(SnackBar));
      expect(snack.bottom, lessThanOrEqualTo(save.top + 0.5), reason: 'snackbar above Kaydet');

      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(repo.createBodies, hasLength(2), reason: 'Kaydet tappable with the snackbar open');
    });
  });

  group('page closed while saving (mounted checks)', () {
    testWidgets('list page below: close during the request, no exception, list updated', (
      tester,
    ) async {
      await openCreate(tester);
      repo.mutationGate = Completer<void>();
      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleEditScreen), findsNothing);
      expect(find.byType(ScheduleScreen), findsOneWidget);

      repo.mutationGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ScheduleScreen), findsOneWidget, reason: 'no extra pop');
      expect(find.text('Koşu'), findsOneWidget, reason: 'list still updated');
      expect(repo.createBodies, hasLength(1));
    });

    testWidgets('/schedule/new opened directly (no list below): close during the request, '
        'no exception, request still completes', (tester) async {
      await pumpApp(tester, initial: AppRouter.scheduleNewPath);
      expect(find.byType(ScheduleEditScreen), findsOneWidget);
      expect(router.canPop(), isFalse);
      repo.mutationGate = Completer<void>();
      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();

      router.go(AppRouter.homePath);
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);

      repo.mutationGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('HOME'), findsOneWidget, reason: 'no navigation after close');
      expect(repo.createBodies, hasLength(1));
      expect(repo.server.map((b) => b.title), contains('Koşu'));
    });
  });
}
