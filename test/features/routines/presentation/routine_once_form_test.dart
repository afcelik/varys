// Routine form and the one-time ('once') type: 'Tek sefer' is not offered
// for routines, except when the routine being edited is already one-time
// (e.g. created elsewhere); then it shows selected, editing works and the
// other types can be chosen. Data is real backend JSON.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
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

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => DateTime(2026, 11, 21);
}

List<Routine> _read(String name) =>
    (jsonDecode(File('test/fixtures/$name').readAsStringSync()) as List<dynamic>)
        .map((e) => Routine.fromJson(e as Map<String, dynamic>))
        .toList();

void main() {
  late _MockRoutineRepository repo;
  late List<Routine> withOnce; // daily (1), once (2, 2026-11-25)
  late List<Routine> classic; // routines_list.json: daily, weekly, monthly, interval
  late GoRouter router;

  setUpAll(() {
    registerFallbackValue(const RoutineChanges());
  });

  setUp(() {
    repo = _MockRoutineRepository();
    withOnce = _read('routines_list_with_once.json');
    classic = _read('routines_list.json');
    when(() => repo.getRoutines()).thenAnswer((_) async => Right(withOnce));
    when(() => repo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.routinesPath,
      routes: [
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

  Future<void> open(WidgetTester tester, {Routine? routine}) async {
    await pumpApp(tester);
    if (routine == null) {
      router.push(AppRouter.routinesNewPath);
    } else {
      router.push(AppRouter.routinesEditPath, extra: routine);
    }
    await tester.pumpAndSettle();
  }

  final typeSelector = find.byKey(const ValueKey('routine-type'));
  final saveButton = find.byKey(const ValueKey('routine-save'));
  final titleField = find.byKey(const ValueKey('routine-title'));

  SegmentedButton<RecurrenceType> selector(WidgetTester tester) =>
      tester.widget<SegmentedButton<RecurrenceType>>(typeSelector);
  List<RecurrenceType> offered(WidgetTester tester) =>
      selector(tester).segments.map((s) => s.value).toList();
  Finder segmentText(String label) => find.descendant(of: typeSelector, matching: find.text(label));

  Future<void> selectType(WidgetTester tester, String label) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(segmentText(label));
    await tester.pumpAndSettle();
    await tester.tap(segmentText(label));
    await tester.pumpAndSettle();
  }

  Future<RoutineChanges> saveAndCapture(WidgetTester tester, Routine answer) async {
    when(() => repo.updateRoutine(any(), any())).thenAnswer((_) async => Right(answer));
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    return verify(() => repo.updateRoutine(answer.id, captureAny())).captured.single
        as RoutineChanges;
  }

  const fourTypes = [
    RecurrenceType.daily,
    RecurrenceType.weekly,
    RecurrenceType.monthly,
    RecurrenceType.interval,
  ];

  group('Tek sefer is not offered', () {
    testWidgets('create form: four types, no Tek sefer', (tester) async {
      await open(tester);
      expect(find.text(RoutineEditScreen.createTitle), findsOneWidget);
      expect(offered(tester), fourTypes);
      expect(segmentText('Tek sefer'), findsNothing);
    });

    testWidgets('editing any non-once routine: four types, no Tek sefer', (tester) async {
      for (final routine in [...classic, withOnce.first]) {
        await open(tester, routine: routine);
        expect(offered(tester), fourTypes, reason: routine.recurrenceType.name);
        expect(segmentText('Tek sefer'), findsNothing, reason: routine.recurrenceType.name);
      }
    });

    test('typeOptions: once only for an original once routine', () {
      expect(RoutineEditScreen.typeOptions(null), fourTypes);
      expect(RoutineEditScreen.typeOptions(classic[1]), fourTypes);
      expect(RoutineEditScreen.typeOptions(withOnce.last), [...fourTypes, RecurrenceType.once]);
    });
  });

  group('an existing once routine', () {
    testWidgets('opens with Tek sefer offered and selected; no recurrence fields', (tester) async {
      await open(tester, routine: withOnce.last);
      expect(find.text(RoutineEditScreen.editTitle), findsOneWidget);
      expect(offered(tester), [...fourTypes, RecurrenceType.once]);
      expect(selector(tester).selected, {RecurrenceType.once});
      expect(segmentText('Tek sefer'), findsOneWidget);
      expect(find.byKey(const ValueKey('weekday-0')), findsNothing);
      expect(find.byKey(const ValueKey('routine-day-of-month')), findsNothing);
      expect(find.byKey(const ValueKey('routine-interval')), findsNothing);
      expect(find.text(recurrenceChangeNote), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('staying once: a title edit sends only the title', (tester) async {
      final once = withOnce.last;
      await open(tester, routine: once);
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      await tester.enterText(titleField, 'Vergi beyannamesi 2026');
      await tester.pumpAndSettle();
      final changes = await saveAndCapture(tester, once.copyWith(title: 'Vergi beyannamesi 2026'));
      expect(changes.toBody(), {'title': 'Vergi beyannamesi 2026'});
    });

    testWidgets('once -> weekly: type + days, the others explicit null; Tek sefer stays '
        'offered so it can be chosen back', (tester) async {
      final once = withOnce.last;
      await open(tester, routine: once);
      await selectType(tester, 'Haftalık');
      expect(segmentText('Tek sefer'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('weekday-3')));
      await tester.tap(find.byKey(const ValueKey('weekday-3')));
      await tester.pumpAndSettle();
      expect(find.text(recurrenceChangeNote), findsOneWidget);

      final changes = await saveAndCapture(
        tester,
        once.copyWith(recurrenceType: RecurrenceType.weekly, daysOfWeek: [3]),
      );
      expect(changes.toBody(), {
        'recurrence_type': 'weekly',
        'days_of_week': [3],
        'day_of_month': null,
        'interval_days': null,
      });
    });

    testWidgets('switching away and back to Tek sefer is no change (Kaydet disabled)', (
      tester,
    ) async {
      await open(tester, routine: withOnce.last);
      await selectType(tester, 'Aylık');
      await selectType(tester, 'Tek sefer');
      expect(selector(tester).selected, {RecurrenceType.once});
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      verifyNever(() => repo.updateRoutine(any(), any()));
    });
  });

  group('routine list summary', () {
    testWidgets("the once routine reads 'Tek sefer, 25 Kasım'", (tester) async {
      await pumpApp(tester);
      expect(find.text('Tek sefer, 25 Kasım'), findsOneWidget);
      expect(find.text('Her gün'), findsOneWidget);
    });
  });
}
