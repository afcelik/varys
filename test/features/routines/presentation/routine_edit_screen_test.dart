import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
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

/// Real POST /routines 201 body, renamed.
Routine _created(String title) => Routine.fromJson(
  jsonDecode(File('test/fixtures/routine_created.json').readAsStringSync()) as Map<String, dynamic>,
).copyWith(id: 9, title: title);

typedef _RoutineResult = Either<Failure, Routine>;

void main() {
  late _MockRoutineRepository repo;
  late List<Routine> base;
  late GoRouter router;

  setUpAll(() {
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(RecurrenceType.daily);
    registerFallbackValue(const RoutineChanges());
  });

  setUp(() {
    repo = _MockRoutineRepository();
    base = _fixture();
    when(() => repo.getRoutines()).thenAnswer((_) async => Right(base));
    when(() => repo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
  });

  /// Named arguments of every createRoutine call, by name.
  late List<Map<String, Object?>> createCalls;

  void whenCreate(Future<_RoutineResult> Function() answer) {
    createCalls = [];
    when(
      () => repo.createRoutine(
        title: any(named: 'title'),
        description: any(named: 'description'),
        recurrenceType: any(named: 'recurrenceType'),
        daysOfWeek: any(named: 'daysOfWeek'),
        dayOfMonth: any(named: 'dayOfMonth'),
        intervalDays: any(named: 'intervalDays'),
        startDate: any(named: 'startDate'),
      ),
    ).thenAnswer((inv) {
      createCalls.add({
        for (final e in inv.namedArguments.entries)
          e.key.toString().replaceAll('Symbol("', '').replaceAll('")', ''): e.value,
      });
      return answer();
    });
  }

  /// The single createRoutine call's arguments.
  Map<String, Object?> createdOnce() {
    expect(createCalls, hasLength(1), reason: 'exactly one POST');
    return createCalls.single;
  }

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// [initial] is where the app starts. Default: the list page, so the form
  /// is pushed on top of it (the normal flow).
  Future<void> pumpApp(
    WidgetTester tester, {
    String initial = AppRouter.routinesPath,
    Size size = const Size(600, 1400),
  }) async {
    setSize(tester, size);
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.routinesPath, builder: (_, _) => const RoutinesScreen()),
        GoRoute(path: AppRouter.routinesNewPath, builder: (_, _) => const RoutineEditScreen()),
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
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        routineRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCreate(WidgetTester tester, {Size size = const Size(600, 1400)}) async {
    await pumpApp(tester, size: size);
    router.push(AppRouter.routinesNewPath);
    await tester.pumpAndSettle();
    expect(find.text(RoutineEditScreen.createTitle), findsOneWidget);
  }

  Future<void> openEdit(WidgetTester tester, Routine routine) async {
    await pumpApp(tester);
    router.push(AppRouter.routinesEditPath, extra: routine);
    await tester.pumpAndSettle();
    expect(find.text(RoutineEditScreen.editTitle), findsOneWidget);
  }

  final titleField = find.byKey(const ValueKey('routine-title'));
  final descriptionField = find.byKey(const ValueKey('routine-description'));
  final dayOfMonthField = find.byKey(const ValueKey('routine-day-of-month'));
  final intervalField = find.byKey(const ValueKey('routine-interval'));
  final saveButton = find.byKey(const ValueKey('routine-save'));
  final note = find.text(recurrenceChangeNote);
  Finder weekday(int d) => find.byKey(ValueKey('weekday-$d'));

  String fieldText(WidgetTester tester, Finder field) => tester
      .widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
      .controller
      .text;
  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton).onPressed != null;
  String startDateText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('routine-start-date-text'))).data!;
  RoutineEditScreenState formState(WidgetTester tester) =>
      tester.state<RoutineEditScreenState>(find.byType(RoutineEditScreen));

  Future<void> selectType(WidgetTester tester, String label) async {
    final segment = find.descendant(
      of: find.byKey(const ValueKey('routine-type')),
      matching: find.text(label),
    );
    // Let a pending "show caret on screen" scroll (from enterText) run first,
    // otherwise it scrolls back after ensureVisible.
    await tester.pumpAndSettle();
    await tester.ensureVisible(segment);
    await tester.pumpAndSettle();
    await tester.tap(segment);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
  }

  group('recurrence type shows the right fields', () {
    testWidgets('daily: no extra fields; weekly: 7 chips; monthly: day + note; interval', (
      tester,
    ) async {
      await openCreate(tester);
      // Default type is daily.
      expect(weekday(0), findsNothing);
      expect(dayOfMonthField, findsNothing);
      expect(intervalField, findsNothing);

      await selectType(tester, 'Haftalık');
      for (var d = 0; d < 7; d++) {
        expect(weekday(d), findsOneWidget);
      }
      expect(find.text('Pzt'), findsOneWidget);
      expect(find.text('Paz'), findsOneWidget);
      expect(dayOfMonthField, findsNothing);
      expect(intervalField, findsNothing);

      await selectType(tester, 'Aylık');
      expect(dayOfMonthField, findsOneWidget);
      expect(find.text('Ay kısaysa ayın son günü'), findsOneWidget);
      expect(weekday(0), findsNothing);
      expect(intervalField, findsNothing);

      await selectType(tester, 'Aralık');
      expect(intervalField, findsOneWidget);
      expect(dayOfMonthField, findsNothing);
      expect(weekday(0), findsNothing);
    });

    testWidgets('values typed for another type are kept when switching back', (tester) async {
      await openCreate(tester);
      await selectType(tester, 'Haftalık');
      await tester.tap(weekday(2));
      await tester.pumpAndSettle();
      await selectType(tester, 'Aylık');
      await tester.enterText(dayOfMonthField, '15');
      await tester.pumpAndSettle();
      await selectType(tester, 'Haftalık');
      expect(tester.widget<FilterChip>(weekday(2)).selected, isTrue);
      await selectType(tester, 'Aylık');
      expect(fieldText(tester, dayOfMonthField), '15');
    });
  });

  group('validation', () {
    testWidgets('title: required after editing, trimmed; Kaydet disabled while invalid', (
      tester,
    ) async {
      await openCreate(tester);
      expect(saveEnabled(tester), isFalse, reason: 'empty title');
      expect(find.text(titleRequiredMessage), findsNothing, reason: 'not shown before typing');

      await tester.enterText(titleField, '   ');
      await tester.pumpAndSettle();
      expect(find.text(titleRequiredMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(titleField, 'Spor');
      await tester.pumpAndSettle();
      expect(find.text(titleRequiredMessage), findsNothing);
      expect(saveEnabled(tester), isTrue);

      await tester.enterText(titleField, 'a' * 256);
      await tester.pumpAndSettle();
      expect(find.text(titleTooLongMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('description over 2000 characters', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'Spor');
      await tester.enterText(descriptionField, 'a' * 2001);
      await tester.pumpAndSettle();
      expect(find.text(descriptionTooLongMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('weekly needs at least one day', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'Spor');
      await selectType(tester, 'Haftalık');
      expect(find.text(weekdaysRequiredMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.tap(weekday(4));
      await tester.pumpAndSettle();
      expect(find.text(weekdaysRequiredMessage), findsNothing);
      expect(saveEnabled(tester), isTrue);

      await tester.tap(weekday(4));
      await tester.pumpAndSettle();
      expect(find.text(weekdaysRequiredMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('monthly: 1..31; digits only, at most 4', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'Fatura');
      await selectType(tester, 'Aylık');
      expect(find.text(dayOfMonthInvalidMessage), findsOneWidget, reason: 'empty');

      for (final (input, ok) in [('0', false), ('1', true), ('31', true), ('32', false)]) {
        await tester.enterText(dayOfMonthField, input);
        await tester.pumpAndSettle();
        expect(
          find.text(dayOfMonthInvalidMessage),
          ok ? findsNothing : findsOneWidget,
          reason: input,
        );
        expect(saveEnabled(tester), ok, reason: input);
      }

      await tester.enterText(dayOfMonthField, '1a-5');
      await tester.pumpAndSettle();
      expect(fieldText(tester, dayOfMonthField), '15');
      await tester.enterText(dayOfMonthField, '123456');
      await tester.pumpAndSettle();
      expect(fieldText(tester, dayOfMonthField), '1234');
      expect(find.text(dayOfMonthInvalidMessage), findsOneWidget);
    });

    testWidgets('interval: at least 1; digits only, at most 4', (tester) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'Sula');
      await selectType(tester, 'Aralık');
      expect(find.text(intervalInvalidMessage), findsOneWidget);

      await tester.enterText(intervalField, '0');
      await tester.pumpAndSettle();
      expect(find.text(intervalInvalidMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(intervalField, '3');
      await tester.pumpAndSettle();
      expect(find.text(intervalInvalidMessage), findsNothing);
      expect(saveEnabled(tester), isTrue);

      await tester.enterText(intervalField, '-2.5x');
      await tester.pumpAndSettle();
      expect(fieldText(tester, intervalField), '25');
      await tester.enterText(intervalField, '99999');
      await tester.pumpAndSettle();
      expect(fieldText(tester, intervalField), '9999');
    });
  });

  group('create', () {
    testWidgets('sends the form values, pops back, new routine is in the list', (tester) async {
      whenCreate(() async => Right(_created('Koşu')));
      await openCreate(tester);
      when(() => repo.getRoutines()).thenAnswer((_) async => Right([...base, _created('Koşu')]));
      await tester.enterText(titleField, '  Koşu ');
      await tester.enterText(descriptionField, '  ');
      await selectType(tester, 'Haftalık');
      await tester.tap(weekday(2));
      await tester.tap(weekday(0));
      await tester.pumpAndSettle();

      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(createdOnce(), {
        'title': 'Koşu',
        'description': null,
        'recurrenceType': RecurrenceType.weekly,
        'daysOfWeek': [0, 2],
        'dayOfMonth': null,
        'intervalDays': null,
        'startDate': _day,
      });
      expect(find.byType(RoutineEditScreen), findsNothing, reason: 'popped');
      expect(find.byType(RoutinesScreen), findsOneWidget);
      expect(find.text('Koşu'), findsOneWidget);
    });

    testWidgets('Kaydet is disabled while the request runs; double tap sends one request', (
      tester,
    ) async {
      final pending = Completer<_RoutineResult>();
      whenCreate(() => pending.future);
      await openCreate(tester);
      await tester.enterText(titleField, 'Spor');
      await tester.pumpAndSettle();

      await tapSave(tester);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();

      pending.complete(Right(_created('Spor')));
      await tester.pumpAndSettle();
      createdOnce();
    });

    testWidgets('server error: form stays open with the values, snackbar, Kaydet re-enabled', (
      tester,
    ) async {
      whenCreate(() async => const Left(_serverError));
      await openCreate(tester);
      await tester.enterText(titleField, 'Fatura öde');
      await tester.enterText(descriptionField, 'Elektrik');
      await selectType(tester, 'Aylık');
      await tester.enterText(dayOfMonthField, '31');
      await tester.pumpAndSettle();

      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(RoutineEditScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Sunucu hatası. Lütfen daha sonra tekrar deneyin.'),
        ),
        findsOneWidget,
      );
      expect(fieldText(tester, titleField), 'Fatura öde');
      expect(fieldText(tester, descriptionField), 'Elektrik');
      expect(fieldText(tester, dayOfMonthField), '31');
      expect(saveEnabled(tester), isTrue);
    });
  });

  group('start date', () {
    testWidgets('create: default is today; clamped to 2000-01-01..2100-12-31', (tester) async {
      await openCreate(tester);
      expect(startDateText(tester), '01.11.2026');
      expect(formState(tester).startDate, _day);

      formState(tester).setStartDate(DateTime(1999, 12, 31));
      await tester.pump();
      expect(startDateText(tester), '01.01.2000');

      formState(tester).setStartDate(DateTime(2101, 1, 1));
      await tester.pump();
      expect(startDateText(tester), '31.12.2100');

      formState(tester).setStartDate(DateTime(2026, 12, 24, 23, 59));
      await tester.pump();
      expect(formState(tester).startDate, DateTime(2026, 12, 24), reason: 'date part only');
      expect(startDateText(tester), '24.12.2026');
    });

    testWidgets('create: picker gets the bounds and current date; closing it keeps the form', (
      tester,
    ) async {
      await openCreate(tester);
      await tester.enterText(titleField, 'Spor');
      await selectType(tester, 'Haftalık');
      await tester.tap(weekday(3));
      await tester.pumpAndSettle();
      formState(tester).setStartDate(DateTime(2026, 12, 24));
      await tester.pump();

      await tester.ensureVisible(find.byKey(const ValueKey('routine-start-date-button')));
      await tester.tap(find.byKey(const ValueKey('routine-start-date-button')));
      await tester.pumpAndSettle();

      final picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate, DateTime(2000, 1, 1));
      expect(picker.lastDate, DateTime(2100, 12, 31));
      expect(picker.initialDate, DateTime(2026, 12, 24));

      // Close with the real (Turkish) cancel button.
      expect(find.text('Cancel'), findsNothing);
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(RoutineEditScreen), findsOneWidget);
      expect(fieldText(tester, titleField), 'Spor');
      expect(tester.widget<FilterChip>(weekday(3)).selected, isTrue);
      expect(startDateText(tester), '24.12.2026', reason: 'dismissed: date unchanged');
    });

    testWidgets('create: the picked date is what gets sent', (tester) async {
      whenCreate(() async => Right(_created('Spor')));
      await openCreate(tester);
      await tester.enterText(titleField, 'Spor');
      formState(tester).setStartDate(DateTime(2027, 1, 5));
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(createdOnce()['startDate'], DateTime(2027, 1, 5));
    });

    testWidgets('edit: start date is read-only (shown, no picker)', (tester) async {
      await openEdit(tester, base[1]);
      expect(startDateText(tester), '02.11.2026');
      expect(find.text(RoutineEditScreen.startDateReadOnlyHelper), findsOneWidget);
      expect(find.byKey(const ValueKey('routine-start-date-button')), findsNothing);

      await tester.ensureVisible(find.byKey(const ValueKey('routine-start-date')));
      await tester.tap(find.byKey(const ValueKey('routine-start-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);

      formState(tester).setStartDate(DateTime(2030));
      await tester.pump();
      expect(startDateText(tester), '02.11.2026');
    });
  });

  group('edit', () {
    testWidgets('prefilled from the routine', (tester) async {
      await openEdit(tester, base[3]); // interval 3, description set
      expect(fieldText(tester, titleField), 'Bitki sula');
      expect(fieldText(tester, descriptionField), 'Salon ve balkon');
      expect(fieldText(tester, intervalField), '3');
    });

    testWidgets('no change: Kaydet disabled, tapping sends nothing, page stays', (tester) async {
      await openEdit(tester, base[1]);
      expect(saveEnabled(tester), isFalse);
      await tapSave(tester);
      await tester.pumpAndSettle();
      verifyNever(() => repo.updateRoutine(any(), any()));
      expect(find.byType(RoutineEditScreen), findsOneWidget);

      // Change and change back: still nothing to send.
      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await tester.enterText(titleField, ' Spor ');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('title change sends only the title, pops, list shows the new title', (
      tester,
    ) async {
      when(
        () => repo.updateRoutine(any(), any()),
      ).thenAnswer((_) async => Right(base[1].copyWith(title: 'Koşu')));
      await openEdit(tester, base[1]);
      when(() => repo.getRoutines()).thenAnswer(
        (_) async => Right([base[0], base[1].copyWith(title: 'Koşu'), base[2], base[3]]),
      );
      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      final changes =
          verify(() => repo.updateRoutine(2, captureAny())).captured.single as RoutineChanges;
      expect(changes.toBody(), {'title': 'Koşu'});
      expect(find.byType(RoutineEditScreen), findsNothing);
      expect(find.text('Koşu'), findsOneWidget);
    });

    testWidgets('weekly -> daily sends the type with unrelated fields as explicit null', (
      tester,
    ) async {
      when(
        () => repo.updateRoutine(any(), any()),
      ).thenAnswer((_) async => Right(base[1].copyWith(recurrenceType: RecurrenceType.daily)));
      await openEdit(tester, base[1]);
      await selectType(tester, 'Günlük');
      await tapSave(tester);
      await tester.pumpAndSettle();

      final changes =
          verify(() => repo.updateRoutine(2, captureAny())).captured.single as RoutineChanges;
      expect(changes.toBody(), {
        'recurrence_type': 'daily',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': null,
      });
    });

    testWidgets('recurrence note: hidden at first, shown when the rule changes, hidden '
        'when changed back; never for title-only changes', (tester) async {
      await openEdit(tester, base[1]); // weekly 0,2,4
      expect(note, findsNothing);

      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      expect(note, findsNothing, reason: 'title is not the rule');

      await tester.tap(weekday(6));
      await tester.pumpAndSettle();
      expect(note, findsOneWidget);
      await tester.tap(weekday(6));
      await tester.pumpAndSettle();
      expect(note, findsNothing);

      await selectType(tester, 'Aylık');
      expect(note, findsOneWidget);
      await selectType(tester, 'Haftalık');
      expect(note, findsNothing);
    });

    testWidgets('create form never shows the recurrence note', (tester) async {
      await openCreate(tester);
      await selectType(tester, 'Aylık');
      await tester.enterText(dayOfMonthField, '5');
      await tester.pumpAndSettle();
      expect(note, findsNothing);
    });

    testWidgets('404 on save: form stays, snackbar "Kaynak bulunamadı.", list re-fetched', (
      tester,
    ) async {
      when(() => repo.updateRoutine(any(), any())).thenAnswer((_) async => const Left(_notFound));
      await openEdit(tester, base[1]);
      clearInteractions(repo);
      when(() => repo.getRoutines()).thenAnswer((_) async => Right([base[0], base[2], base[3]]));

      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(RoutineEditScreen), findsOneWidget);
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.text('Kaynak bulunamadı.')),
        findsOneWidget,
      );
      expect(fieldText(tester, titleField), 'Koşu');
      verify(() => repo.getRoutines()).called(1);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('routine-row-2')), findsNothing, reason: 'stale row gone');
    });
  });

  group('keyboard open (narrow screen)', () {
    testWidgets('360px with a 300px keyboard: Kaydet reachable and tappable, no overflow', (
      tester,
    ) async {
      whenCreate(() async => Right(_created('Spor')));
      await openCreate(tester, size: const Size(360, 640));
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(titleField, 'Spor');
      await selectType(tester, 'Haftalık');
      for (var d = 0; d < 7; d++) {
        await tester.ensureVisible(weekday(d));
        await tester.tap(weekday(d));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(saveButton);
      await tester.pumpAndSettle();
      final rect = tester.getRect(saveButton);
      expect(rect.bottom, lessThanOrEqualTo(640 - 300), reason: 'above the keyboard');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(createdOnce()['daysOfWeek'], [0, 1, 2, 3, 4, 5, 6]);
    });
  });

  group('page closed while saving (mounted checks)', () {
    testWidgets('list page below: close during the request, no exception, list updated', (
      tester,
    ) async {
      final pending = Completer<_RoutineResult>();
      whenCreate(() => pending.future);
      await openCreate(tester);
      when(() => repo.getRoutines()).thenAnswer((_) async => Right([...base, _created('Koşu')]));
      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(RoutineEditScreen), findsNothing);
      expect(find.byType(RoutinesScreen), findsOneWidget);

      pending.complete(Right(_created('Koşu')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(RoutinesScreen), findsOneWidget, reason: 'no extra pop');
      expect(find.text('Koşu'), findsOneWidget, reason: 'list still updated');
      createdOnce();
    });

    testWidgets('/routines/new opened directly (no list below): close during the request, '
        'no exception, request still completes', (tester) async {
      final pending = Completer<_RoutineResult>();
      whenCreate(() => pending.future);
      await pumpApp(tester, initial: AppRouter.routinesNewPath);
      expect(find.byType(RoutineEditScreen), findsOneWidget);
      expect(find.byType(RoutinesScreen), findsNothing);
      expect(router.canPop(), isFalse);

      await tester.enterText(titleField, 'Koşu');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();

      // Close by leaving to Home: the list page is never built.
      router.go(AppRouter.homePath);
      await tester.pumpAndSettle();
      expect(find.byType(RoutineEditScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget);

      pending.complete(Right(_created('Koşu')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HOME'), findsOneWidget, reason: 'no navigation after close');
      expect(find.byType(RoutinesScreen), findsNothing);
      createdOnce();
    });
  });
}
