// FocusTaskSelectionPage: lists only the plan's unfinished "Bugün
// Yapılacaklar" tasks for one focus slot. Real DailyPlanNotifier; only the
// repositories are mocked. Plans come from real backend JSON.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/focus_candidates.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/focus_task_selection_page.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/home/presentation/widgets/add_from_planning_sheet.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

final _planDay = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _planDay;
}

Map<String, dynamic> _fixture() =>
    jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
        as Map<String, dynamic>;

/// Real backend JSON tasks: 1 todo, 2 in_progress, 3 done, 4 todo, 5 done.
List<Task> _tasks() =>
    (_fixture()['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();

Task _task(int id) => _tasks().firstWhere((t) => t.id == id);

DailyPlan _plan({Task? main, Task? side, List<Task>? tasks}) =>
    DailyPlan(planDate: _planDay, mainFocus: main, sideFocus: side, tasks: tasks ?? _tasks());

/// Unplanned Planning task, real JSON shape.
Task _unplanned() => Task.fromJson(
      Map<String, dynamic>.from((_fixture()['tasks'] as List).first as Map)
        ..['id'] = 20
        ..['title'] = 'Fatura öde'
        ..['planned_date'] = null,
    );

const _t1 = 'İlk görev - yapılacak';
const _t2 = 'İkinci görev - devam ediyor';
const _t3 = 'Üçüncü görev - tamamlandı';
const _t4 = 'Dördüncü görev - yapılacak';
const _t5 = 'Beşinci görev - tamamlandı';

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;

  // What the launcher got back from push(): [returned] is false until the
  // page pops; [result] is the popped value.
  late bool returned;
  Task? result;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(const PlanField<int>.unset());
    registerFallbackValue(const PlanField<String>.unset());
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    returned = false;
    result = null;
  });

  void stubPlan(DailyPlan plan) =>
      when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));

  /// Pumps a launcher at '/' and opens the real page for [slot] via push.
  Future<void> openPage(WidgetTester tester, FocusSlot slot, {bool settle = true}) async {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await context.push<Task>(AppRouter.focusTaskSelectionPath, extra: slot);
              returned = true;
            },
            child: const Text('Aç'),
          ),
        ),
      ),
      GoRoute(
        path: AppRouter.focusTaskSelectionPath,
        builder: (_, state) => FocusTaskSelectionPage(slot: state.extra as FocusSlot),
      ),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.tap(find.text('Aç'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(FocusTaskSelectionPage)));

  Finder tile(String title) => find.ancestor(of: find.text(title), matching: find.byType(ListTile));

  /// Row is drawn faded (Opacity 0.5), disabled, with [label] next to it.
  void expectFadedWithLabel(WidgetTester tester, String title, String label) {
    final row = tile(title);
    expect(tester.widget<ListTile>(row).enabled, isFalse);
    expect(tester.widget<ListTile>(row).onTap, isNull);
    final opacity = tester.widget<Opacity>(find.ancestor(of: row, matching: find.byType(Opacity)));
    expect(opacity.opacity, 0.5);
    expect(find.descendant(of: row, matching: find.text(label)), findsOneWidget);
  }

  Future<void> tapAndExpectNoPop(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    expect(find.byType(FocusTaskSelectionPage), findsOneWidget);
    expect(returned, isFalse);
  }

  group('load states', () {
    testWidgets('plan loading: spinner', (tester) async {
      final completer = Completer<Either<Failure, DailyPlan>>();
      when(() => planRepo.getPlan(any())).thenAnswer((_) => completer.future);
      await openPage(tester, FocusSlot.main, settle: false);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_t1), findsNothing);

      completer.complete(Right(_plan()));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(_t1), findsOneWidget);
    });

    testWidgets('plan error: userMessage + "Tekrar dene" reloads the plan', (tester) async {
      var calls = 0;
      when(() => planRepo.getPlan(any())).thenAnswer((_) async {
        calls++;
        return calls == 1 ? const Left(NetworkFailure('connection refused')) : Right(_plan());
      });
      await openPage(tester, FocusSlot.main);

      expect(find.text('Bağlantı hatası'), findsOneWidget);
      expect(find.textContaining('connection refused'), findsNothing);
      expect(find.textContaining('Instance of'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.text(_t1), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Tekrar dene'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Bağlantı hatası'), findsNothing);
      expect(find.text(_t1), findsOneWidget);
    });

    testWidgets('reload while open keeps the old list (no full-page spinner)', (tester) async {
      stubPlan(_plan());
      await openPage(tester, FocusSlot.main);
      expect(find.text(_t1), findsOneWidget);

      final completer = Completer<Either<Failure, DailyPlan>>();
      when(() => planRepo.getPlan(any())).thenAnswer((_) => completer.future);
      container(tester).invalidate(dailyPlanProvider);
      await tester.pump();
      await tester.pump();

      expect(find.text(_t1), findsOneWidget);
      expect(find.text(_t2), findsOneWidget);
      expect(find.text(_t4), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      verify(() => planRepo.getPlan(any())).called(2);

      final renamed = _tasks().map((t) => t.id == 1 ? t.copyWith(title: 'Yenilenen görev') : t);
      completer.complete(Right(_plan(tasks: renamed.toList())));
      await tester.pumpAndSettle();
      expect(find.text('Yenilenen görev'), findsOneWidget);
      expect(find.text(_t1), findsNothing);
    });
  });

  group('list content', () {
    testWidgets('only the plan day\'s unfinished tasks are shown, in plan order', (tester) async {
      stubPlan(_plan());
      await openPage(tester, FocusSlot.main);

      for (final t in [_t1, _t2, _t4]) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.text(_t3), findsNothing);
      expect(find.text(_t5), findsNothing);
      expect(tester.getTopLeft(find.text(_t1)).dy, lessThan(tester.getTopLeft(find.text(_t2)).dy));
      expect(tester.getTopLeft(find.text(_t2)).dy, lessThan(tester.getTopLeft(find.text(_t4)).dy));
      // Only the plan is read; the page no longer loads all tasks.
      verifyNever(() => taskRepo.getTasks());
      verifyNever(() => taskRepo.getTasksByFilter(any()));
    });

    testWidgets('title follows the slot', (tester) async {
      stubPlan(_plan());
      await openPage(tester, FocusSlot.main);
      expect(find.text('Ana odak seç'), findsOneWidget);
    });

    testWidgets('side slot title', (tester) async {
      stubPlan(_plan());
      await openPage(tester, FocusSlot.side);
      expect(find.text('İkincil odak seç'), findsOneWidget);
    });

    testWidgets('BackArrow is the leading widget; back returns null', (tester) async {
      stubPlan(_plan());
      await openPage(tester, FocusSlot.main);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
    });
  });

  group('row states', () {
    testWidgets('selectable row pops with that task', (tester) async {
      stubPlan(_plan());
      await openPage(tester, FocusSlot.main);
      await tester.tap(find.text(_t2));
      await tester.pumpAndSettle();

      expect(find.byType(FocusTaskSelectionPage), findsNothing);
      expect(returned, isTrue);
      expect(result?.id, 2);
    });

    testWidgets('main slot: side focus is faded, labeled "İkincil odak", tap does not pop',
        (tester) async {
      stubPlan(_plan(side: _task(2)));
      await openPage(tester, FocusSlot.main);

      expectFadedWithLabel(tester, _t2, 'İkincil odak');
      await tapAndExpectNoPop(tester, _t2);
    });

    testWidgets('side slot: main focus is faded, labeled "Ana odak", tap does not pop',
        (tester) async {
      stubPlan(_plan(main: _task(1)));
      await openPage(tester, FocusSlot.side);

      expectFadedWithLabel(tester, _t1, 'Ana odak');
      await tapAndExpectNoPop(tester, _t1);
    });

    testWidgets('temporary (negative id) task is faded, "Ekleniyor…", cannot be chosen',
        (tester) async {
      final temp = _task(1).copyWith(id: -1, title: 'Henüz kaydedilmedi');
      stubPlan(_plan(tasks: [temp, ..._tasks()]));
      await openPage(tester, FocusSlot.main);

      expectFadedWithLabel(tester, 'Henüz kaydedilmedi', 'Ekleniyor…');
      await tapAndExpectNoPop(tester, 'Henüz kaydedilmedi');
    });

    testWidgets("this slot's focus has a check; tapping it pops null (no change)",
        (tester) async {
      stubPlan(_plan(main: _task(4)));
      await openPage(tester, FocusSlot.main);

      expect(find.descendant(of: tile(_t4), matching: find.byIcon(Icons.check_circle)),
          findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      await tester.tap(find.text(_t4));
      await tester.pumpAndSettle();
      expect(find.byType(FocusTaskSelectionPage), findsNothing);
      expect(returned, isTrue);
      expect(result, isNull);
    });

    testWidgets('focus moved to another day (not in plan.tasks): absent, no crash, '
        'another task can be chosen; the notifier pre-check still runs', (tester) async {
      final moved = _task(1).copyWith(id: 99, title: 'Başka güne taşınan görev');
      stubPlan(_plan(main: moved, side: _task(2)));
      when(() => planRepo.updatePlan(
            any(),
            mainFocusTaskId: any(named: 'mainFocusTaskId'),
            sideFocusTaskId: any(named: 'sideFocusTaskId'),
            sayNoText: any(named: 'sayNoText'),
          )).thenAnswer((_) async => Right(_plan(main: _task(4), side: _task(2))));
      await openPage(tester, FocusSlot.main);

      expect(tester.takeException(), isNull);
      expect(find.text('Başka güne taşınan görev'), findsNothing);
      expect(find.byIcon(Icons.check_circle), findsNothing);
      expectFadedWithLabel(tester, _t2, 'İkincil odak');

      final notifier = container(tester).read(dailyPlanProvider.notifier);
      await tester.tap(find.text(_t4));
      await tester.pumpAndSettle();
      expect(result?.id, 4);

      // Pre-check is still the safety net: side focus as main → no request.
      final rejected = await notifier.setMainFocus(_task(2));
      expect(rejected.fold((f) => f, (_) => null),
          const ValidationFailure(DailyPlanNotifier.alreadySideFocusMessage));
      verifyNever(() => planRepo.updatePlan(
            any(),
            mainFocusTaskId: any(named: 'mainFocusTaskId'),
            sideFocusTaskId: any(named: 'sideFocusTaskId'),
            sayNoText: any(named: 'sayNoText'),
          ));

      // The chosen task goes through the same path the card uses.
      final accepted = await notifier.setMainFocus(result!);
      expect(accepted.isRight(), isTrue);
      verify(() => planRepo.updatePlan(
            any(),
            mainFocusTaskId: const PlanField.set(4),
            sideFocusTaskId: const PlanField<int>.unset(),
            sayNoText: const PlanField<String>.unset(),
          )).called(1);
    });
  });

  group('add from planning', () {
    Finder inSheet(Finder f) => find.descendant(of: find.byType(AddFromPlanningSheet), matching: f);

    void stubSheet() {
      when(() => taskRepo.getTasks()).thenAnswer((_) async => Right([_unplanned()]));
      when(() => taskRepo.planForDay(20, any())).thenAnswer(
          (_) async => Right(_unplanned().copyWith(plannedDate: _planDay)));
    }

    testWidgets('empty state: message + button opens the sheet; added task becomes selectable',
        (tester) async {
      final doneOnly = _tasks().where((t) => t.status == TaskStatus.done).toList();
      stubPlan(_plan(tasks: doneOnly));
      stubSheet();
      await openPage(tester, FocusSlot.side);

      expect(find.text('Bugün için seçilebilecek görev yok'), findsOneWidget);
      expect(find.text(_t3), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Planlamadan ekle'));
      await tester.pumpAndSettle();
      expect(find.byType(AddFromPlanningSheet), findsOneWidget);

      await tester.tap(inSheet(find.text('Fatura öde')));
      await tester.pump();
      await tester.tap(inSheet(find.text('Ekle (1)')));
      await tester.pumpAndSettle();

      expect(find.byType(AddFromPlanningSheet), findsNothing);
      verify(() => taskRepo.planForDay(20, _planDay)).called(1);
      // List updates from plan state (no new getPlan).
      verify(() => planRepo.getPlan(any())).called(1);
      expect(find.text('Bugün için seçilebilecek görev yok'), findsNothing);
      expect(tester.widget<ListTile>(tile('Fatura öde')).enabled, isTrue);

      await tester.tap(find.text('Fatura öde'));
      await tester.pumpAndSettle();
      expect(result?.id, 20);
    });

    testWidgets('app bar button: tooltip, 48x48 tap target, opens the sheet', (tester) async {
      stubPlan(_plan());
      stubSheet();
      await openPage(tester, FocusSlot.main);

      final button = find.ancestor(
          of: find.byTooltip('Planlamadan ekle'), matching: find.byType(IconButton));
      expect(find.descendant(of: find.byType(AppBar), matching: button), findsOneWidget);
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byType(AddFromPlanningSheet), findsOneWidget);
      expect(inSheet(find.text('Fatura öde')), findsOneWidget);
    });
  });
}
