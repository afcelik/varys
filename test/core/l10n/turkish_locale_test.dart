// The UI locale is forced to Turkish in the real app root (VarysApp in
// main.dart: locale tr + Material/Widgets/Cupertino delegates). These tests
// pump that real root (via the shared harness) and open the routine start
// date picker, so Material's own texts must come out Turkish, also when the
// system language is English. intl 0.20.2 Turkish date symbols are pinned
// here too.

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/addable_tasks.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routine_edit_screen.dart';

import '../../helpers/varys_app_harness.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

/// Monday, 16 November 2026.
final _today = DateTime(2026, 11, 16);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _today;
}

void main() {
  late _MockRoutineRepository repo;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  setUp(() {
    repo = _MockRoutineRepository();
    when(() => repo.getRoutines()).thenAnswer((_) async => const Right([]));
  });

  /// Real app root on the create form, pushed on top of Home.
  Future<void> openCreateForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.homePath,
      routes: [
        GoRoute(path: AppRouter.homePath, builder: (_, _) => const Scaffold(body: Text('HOME'))),
        GoRoute(path: AppRouter.routinesNewPath, builder: (_, _) => const RoutineEditScreen()),
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
    router.push(AppRouter.routinesNewPath);
    await tester.pumpAndSettle();
    expect(find.text(RoutineEditScreen.createTitle), findsOneWidget);
  }

  final titleField = find.byKey(const ValueKey('routine-title'));
  final pickerButton = find.byKey(const ValueKey('routine-start-date-button'));

  String startDateText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('routine-start-date-text'))).data!;

  Future<void> openPicker(WidgetTester tester) async {
    await tester.ensureVisible(pickerButton);
    await tester.tap(pickerButton);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  }

  void expectTurkishPickerButtons() {
    expect(find.text('İptal'), findsOneWidget);
    expect(find.text('Tamam'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('OK'), findsNothing);
  }

  group('start date picker in the real app root', () {
    testWidgets('Turkish buttons; bounds and default today kept; İptal keeps the form', (
      tester,
    ) async {
      await openCreateForm(tester);
      await tester.enterText(titleField, 'Spor');
      await tester.tap(find.text('Haftalık'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('weekday-2')));
      await tester.pumpAndSettle();
      expect(startDateText(tester), '16.11.2026', reason: 'default is today');

      await openPicker(tester);
      expectTurkishPickerButtons();
      final picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate, DateTime(2000, 1, 1));
      expect(picker.lastDate, DateTime(2100, 12, 31));
      expect(picker.initialDate, _today);

      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(RoutineEditScreen), findsOneWidget);
      expect(tester.widget<TextField>(titleField).controller!.text, 'Spor');
      expect(tester.widget<FilterChip>(find.byKey(const ValueKey('weekday-2'))).selected, isTrue);
      expect(startDateText(tester), '16.11.2026', reason: 'cancelled: date unchanged');
    });

    testWidgets('Tamam applies the picked day', (tester) async {
      await openCreateForm(tester);
      await openPicker(tester);
      await tester.tap(find.text('20'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(startDateText(tester), '20.11.2026');
    });

    testWidgets('month name in the picker is Turkish', (tester) async {
      await openCreateForm(tester);
      await openPicker(tester);
      expect(find.text('Kasım 2026'), findsOneWidget);
      expect(find.text('November 2026'), findsNothing);
    });
  });

  group('locale lock', () {
    testWidgets('system language English: the app still draws Turkish', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      await openCreateForm(tester);
      expect(
        Localizations.localeOf(tester.element(find.byType(RoutineEditScreen))),
        const Locale('tr'),
      );
      await openPicker(tester);
      expectTurkishPickerButtons();
      expect(find.text('Kasım 2026'), findsOneWidget);
    });
  });

  group('intl 0.20.2 Turkish date symbols', () {
    test('formatDateForDisplay: full day and month names', () {
      expect(formatDateForDisplay(_today), 'Pazartesi, 16 Kasım');
    });

    test('buildAddableTasks: short month day label', () {
      final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
          as Map<String, dynamic>;
      final base = Task.fromJson((json['tasks'] as List).first as Map<String, dynamic>);
      final task = base.copyWith(
        id: 1,
        status: TaskStatus.todo,
        plannedDate: DateTime.parse('2026-11-17T00:00:00'),
      );
      final result = buildAddableTasks([task], _today);
      expect(result.single.dayLabel, '17 Kas');
    });
  });
}
