import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/home/presentation/widgets/add_from_planning_sheet.dart';
import 'package:varys/features/home/presentation/widgets/daily_tasks_card.dart';
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

/// Fixture tasks (ids 1-5, all planned for 2026-11-01) as the backend returns them.
List<Task> _fixtureTasks() =>
    (_fixture()['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();

DailyPlan _fixturePlan() => DailyPlan(
  planDate: _planDay,
  mainFocus: Task.fromJson(_fixture()['main_focus'] as Map<String, dynamic>),
  tasks: _fixtureTasks(),
);

/// A task in the real backend JSON shape.
Task _task(int id, String title, {String status = 'todo', String? planned}) {
  final json = Map<String, dynamic>.from((_fixture()['tasks'] as List).first as Map)
    ..['id'] = id
    ..['title'] = title
    ..['status'] = status
    ..['planned_date'] = planned;
  return Task.fromJson(json);
}

final _rapor = _task(10, 'Rapor hazırla');
final _istanbul = _task(11, 'İstanbul toplantısı', status: 'in_progress');
final _irmak = _task(12, 'Irmak projesi', planned: '2026-11-17T09:00:00');
final _bitmis = _task(13, 'Bitmiş iş', status: 'done');

/// Server answer for PATCH planned_date: same task, planned for the plan day.
Task _planned(Task t) => t.copyWith(plannedDate: _planDay);

/// Minimal host: the real DailyTasksCard on the real dailyPlanProvider.
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: ref
          .watch(dailyPlanProvider)
          .when(
            data: (plan) => SingleChildScrollView(child: DailyTasksCard(plan: plan)),
            loading: () => const SizedBox(),
            error: (_, _) => const SizedBox(),
          ),
    );
  }
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(_fixturePlan()));
    when(
      () => taskRepo.getTasks(),
    ).thenAnswer((_) async => Right([..._fixtureTasks(), _rapor, _istanbul, _irmak, _bitmis]));
  });

  Future<void> pumpHost(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
          taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        ],
        child: const MaterialApp(home: _Host()),
      ),
    );
    await tester.pumpAndSettle();
  }

  final openButton = find.byTooltip(AddFromPlanningSheet.title);

  Future<void> openSheet(WidgetTester tester) async {
    await pumpHost(tester);
    await tester.tap(openButton);
    await tester.pumpAndSettle();
  }

  Finder inSheet(Finder f) => find.descendant(of: find.byType(AddFromPlanningSheet), matching: f);
  Finder row(String title) => inSheet(find.widgetWithText(CheckboxListTile, title));
  Finder addButton() => inSheet(find.byType(FilledButton));
  FilledButton addButtonWidget(WidgetTester tester) => tester.widget<FilledButton>(addButton());
  Finder inCard(Finder f) => find.descendant(of: find.byType(DailyTasksCard), matching: f);
  List<int> rowIds(WidgetTester tester) => tester
      .widgetList<CheckboxListTile>(inSheet(find.byType(CheckboxListTile)))
      .map((t) => (t.key! as ValueKey<int>).value)
      .toList();

  group('card button', () {
    testWidgets(
      'tap target is at least 48x48 on mobile and desktop, labelled by its tooltip',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpHost(tester);

        final size = tester.getSize(
          find.ancestor(of: openButton, matching: find.byType(IconButton)),
        );
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(
          tester.getSemantics(openButton),
          isSemantics(tooltip: AddFromPlanningSheet.title),
        );

        // A tap near the corner of the 48x48 area (outside the 40px visual) opens the sheet.
        final rect = tester.getRect(
          find.ancestor(of: openButton, matching: find.byType(IconButton)),
        );
        await tester.tapAt(rect.topLeft + const Offset(2, 2));
        await tester.pumpAndSettle();
        expect(find.byType(AddFromPlanningSheet), findsOneWidget);
        semantics.dispose();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    for (final platform in [TargetPlatform.macOS, TargetPlatform.linux]) {
      testWidgets(
        'tap target is at least 48x48 on ${platform.name}',
        (tester) async {
          await pumpHost(tester);
          final size = tester.getSize(
            find.ancestor(of: openButton, matching: find.byType(IconButton)),
          );
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
          expect(defaultTargetPlatform, platform);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  });

  group('list', () {
    testWidgets('shows only not-done tasks not planned for the plan day; unplanned first', (
      tester,
    ) async {
      await openSheet(tester);

      expect(rowIds(tester), [10, 11, 12]);
      expect(inSheet(find.text('17 Kas')), findsOneWidget);
      expect(row('Bitmiş iş'), findsNothing);
      expect(row('İlk görev - yapılacak'), findsNothing);
    });

    testWidgets('search is case-insensitive and Turkish-aware', (tester) async {
      await openSheet(tester);

      await tester.enterText(inSheet(find.byType(TextField)), 'İSTANBUL');
      await tester.pump();
      expect(rowIds(tester), [11]);

      await tester.enterText(inSheet(find.byType(TextField)), 'ırmak');
      await tester.pump();
      expect(rowIds(tester), [12]);

      await tester.enterText(inSheet(find.byType(TextField)), 'yok böyle');
      await tester.pump();
      expect(rowIds(tester), isEmpty);
      expect(inSheet(find.text(AddFromPlanningSheet.noMatchMessage)), findsOneWidget);
    });

    testWidgets('empty state when nothing can be added; Ekle (0) disabled', (tester) async {
      when(() => taskRepo.getTasks()).thenAnswer((_) async => Right([..._fixtureTasks(), _bitmis]));
      await openSheet(tester);

      expect(inSheet(find.text(AddFromPlanningSheet.emptyMessage)), findsOneWidget);
      expect(inSheet(find.text('Ekle (0)')), findsOneWidget);
      expect(addButtonWidget(tester).onPressed, isNull);
    });

    testWidgets('load error shows userMessage and "Tekrar dene" recovers', (tester) async {
      var calls = 0;
      when(() => taskRepo.getTasks()).thenAnswer((_) async {
        calls++;
        if (calls == 1) return const Left(NetworkFailure('connection refused'));
        return Right([_rapor]);
      });
      await openSheet(tester);

      expect(inSheet(find.text('Bağlantı hatası')), findsOneWidget);
      expect(find.textContaining('connection refused'), findsNothing);

      await tester.tap(inSheet(find.text(AddFromPlanningSheet.retryLabel)));
      await tester.pumpAndSettle();

      expect(rowIds(tester), [10]);
      expect(inSheet(find.text('Bağlantı hatası')), findsNothing);
    });

    testWidgets('300 tasks: lazily built list that scrolls to the last task', (tester) async {
      final many = [for (var i = 0; i < 300; i++) _task(1000 + i, 'Toplu görev $i')];
      when(() => taskRepo.getTasks()).thenAnswer((_) async => Right(many));
      await openSheet(tester);

      expect(inSheet(find.byType(ListView)), findsOneWidget);
      expect(row('Toplu görev 0'), findsOneWidget);
      expect(row('Toplu görev 299'), findsNothing, reason: 'ListView.builder builds lazily');

      await tester.scrollUntilVisible(
        row('Toplu görev 299'),
        500,
        scrollable: find
            .descendant(of: inSheet(find.byType(ListView)), matching: find.byType(Scrollable))
            .first,
      );
      expect(row('Toplu görev 299'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('selection and adding', () {
    testWidgets('multi-select updates "Ekle (n)"; n=0 disables it', (tester) async {
      await openSheet(tester);
      expect(addButtonWidget(tester).onPressed, isNull);

      await tester.tap(row('Rapor hazırla'));
      await tester.tap(row('Irmak projesi'));
      await tester.pump();
      expect(inSheet(find.text('Ekle (2)')), findsOneWidget);
      expect(addButtonWidget(tester).onPressed, isNotNull);

      await tester.tap(row('Rapor hazırla'));
      await tester.pump();
      expect(inSheet(find.text('Ekle (1)')), findsOneWidget);
    });

    testWidgets('all succeed: sheet closes, tasks appear in the card, no snackbar', (tester) async {
      when(() => taskRepo.planForDay(10, any())).thenAnswer((_) async => Right(_planned(_rapor)));
      when(() => taskRepo.planForDay(12, any())).thenAnswer((_) async => Right(_planned(_irmak)));
      await openSheet(tester);

      await tester.tap(row('Irmak projesi'));
      await tester.tap(row('Rapor hazırla'));
      await tester.pump();
      await tester.tap(addButton());
      await tester.pumpAndSettle();

      expect(find.byType(AddFromPlanningSheet), findsNothing);
      verify(() => taskRepo.planForDay(10, _planDay)).called(1);
      verify(() => taskRepo.planForDay(12, _planDay)).called(1);
      expect(inCard(find.text('Rapor hazırla')), findsOneWidget);
      expect(inCard(find.text('Irmak projesi')), findsOneWidget);
      expect(inCard(find.text('2/7')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
      'partial failure: stays open, failed task stays selected, list reloaded, snackbar visible in sheet',
      (tester) async {
        when(() => taskRepo.planForDay(10, any())).thenAnswer((_) async => Right(_planned(_rapor)));
        when(
          () => taskRepo.planForDay(12, any()),
        ).thenAnswer((_) async => const Left(NetworkFailure('connection refused')));
        await openSheet(tester);
        // After the attempt the server reports task 10 planned for today.
        when(
          () => taskRepo.getTasks(),
        ).thenAnswer((_) async => Right([..._fixtureTasks(), _planned(_rapor), _istanbul, _irmak]));

        await tester.tap(row('Rapor hazırla'));
        await tester.tap(row('Irmak projesi'));
        await tester.pump();
        await tester.tap(addButton());
        await tester.pumpAndSettle();

        expect(find.byType(AddFromPlanningSheet), findsOneWidget);
        expect(rowIds(tester), [11, 12]);
        expect(tester.widget<CheckboxListTile>(row('Irmak projesi')).value, isTrue);
        expect(tester.widget<CheckboxListTile>(row('İstanbul toplantısı')).value, isFalse);
        expect(inSheet(find.text('Ekle (1)')), findsOneWidget);
        verify(() => taskRepo.getTasks()).called(2);

        // (a) Snackbar is inside the sheet and on top (not under the modal barrier).
        const message = '1 görev eklenemedi. Bağlantı hatası';
        expect(inSheet(find.widgetWithText(SnackBar, message)), findsOneWidget);
        expect(find.text(message).hitTestable(), findsOneWidget);
        expect(find.textContaining('connection refused'), findsNothing);
        // The snackbar must not cover the button.
        expect(inSheet(find.text('Ekle (1)')).hitTestable(), findsOneWidget);
        expect(
          tester.getRect(inSheet(find.byType(SnackBar))).bottom,
          lessThanOrEqualTo(tester.getRect(addButton()).top),
        );

        // The successful one is already on the card.
        expect(inCard(find.text('Rapor hazırla')), findsOneWidget);
      },
    );

    testWidgets('selections that vanished after a reload are not counted and not sent', (
      tester,
    ) async {
      when(() => taskRepo.planForDay(10, any())).thenAnswer((_) async => Right(_planned(_rapor)));
      when(
        () => taskRepo.planForDay(11, any()),
      ).thenAnswer((_) async => const Left(NetworkFailure('x')));
      when(
        () => taskRepo.planForDay(12, any()),
      ).thenAnswer((_) async => const Left(NetworkFailure('x')));
      await openSheet(tester);
      // Reload: 10 now planned for today, 12 deleted elsewhere.
      when(
        () => taskRepo.getTasks(),
      ).thenAnswer((_) async => Right([..._fixtureTasks(), _planned(_rapor), _istanbul]));

      await tester.tap(row('Rapor hazırla'));
      await tester.tap(row('İstanbul toplantısı'));
      await tester.tap(row('Irmak projesi'));
      await tester.pump();
      await tester.tap(addButton());
      await tester.pumpAndSettle();

      expect(inSheet(find.text('2 görev eklenemedi. Bağlantı hatası')), findsOneWidget);
      expect(rowIds(tester), [11]);
      expect(inSheet(find.text('Ekle (1)')), findsOneWidget, reason: '12 is gone from the list');

      when(
        () => taskRepo.planForDay(11, any()),
      ).thenAnswer((_) async => Right(_planned(_istanbul)));
      await tester.tap(addButton());
      await tester.pumpAndSettle();

      verify(() => taskRepo.planForDay(11, _planDay)).called(2);
      verify(() => taskRepo.planForDay(12, _planDay)).called(1); // first attempt only
      expect(find.byType(AddFromPlanningSheet), findsNothing);
    });

    testWidgets('double tap on Ekle runs one operation', (tester) async {
      final pending = Completer<Either<Failure, Task>>();
      when(() => taskRepo.planForDay(10, any())).thenAnswer((_) => pending.future);
      await openSheet(tester);

      await tester.tap(row('Rapor hazırla'));
      await tester.pump();
      await tester.tap(addButton());
      await tester.pump();
      expect(addButtonWidget(tester).onPressed, isNull, reason: 'disabled while running');
      await tester.tap(addButton(), warnIfMissed: false);
      await tester.pump();

      pending.complete(Right(_planned(_rapor)));
      await tester.pumpAndSettle();

      verify(() => taskRepo.planForDay(10, any())).called(1);
      expect(find.byType(AddFromPlanningSheet), findsNothing);
    });

    testWidgets('sheet closed while a request runs: no exception, plan still updated', (
      tester,
    ) async {
      final pending = Completer<Either<Failure, Task>>();
      when(() => taskRepo.planForDay(12, any())).thenAnswer((_) => pending.future);
      await openSheet(tester);

      await tester.tap(row('Irmak projesi'));
      await tester.pump();
      await tester.tap(addButton());
      await tester.pump();

      // Dismiss via the modal barrier (top 10% of the screen).
      await tester.tapAt(const Offset(400, 20));
      await tester.pumpAndSettle();
      expect(find.byType(AddFromPlanningSheet), findsNothing);

      pending.complete(Right(_planned(_irmak)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(inCard(find.text('Irmak projesi')), findsOneWidget);
      expect(inCard(find.text('2/6')), findsOneWidget);
    });

    testWidgets('(b) keyboard open while searching: "Ekle (n)" stays visible and tappable', (
      tester,
    ) async {
      when(() => taskRepo.planForDay(10, any())).thenAnswer((_) async => Right(_planned(_rapor)));
      await openSheet(tester);
      await tester.tap(row('Rapor hazırla'));
      await tester.pump();

      const keyboard = 500.0;
      await tester.tap(inSheet(find.byType(TextField)));
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(inSheet(find.byType(TextField)), 'rap');
      await tester.pumpAndSettle();

      final screenHeight = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final buttonRect = tester.getRect(addButton());
      expect(buttonRect.bottom, lessThanOrEqualTo(screenHeight - keyboard));
      expect(inSheet(find.text('Ekle (1)')).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(addButton());
      await tester.pumpAndSettle();
      verify(() => taskRepo.planForDay(10, _planDay)).called(1);
    });
  });
}
