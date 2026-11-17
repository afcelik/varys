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
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/daily_plan_state_widgets.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/home/presentation/widgets/say_no_card.dart';
import 'package:varys/features/planning/domain/task.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

final _planDay = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _planDay;
}

/// Plan built from real backend JSON: main focus id 3 "Ana odak görevi", no side focus.
DailyPlan _fixturePlan() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  return DailyPlan(
    planDate: _planDay,
    mainFocus: Task.fromJson(json['main_focus'] as Map<String, dynamic>),
    sideFocus: null,
    sayNoText: json['say_no_text'] as String?,
    tasks: (json['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList(),
  );
}

/// Stands in for FocusTaskSelectionPage: pops [task] when "Seç" is tapped.
class _StubSelectionPage extends StatelessWidget {
  const _StubSelectionPage(this.task);
  final Task task;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: TextButton(onPressed: () => context.pop(task), child: const Text('Seç')),
      );
}

/// Hand-written fake: records each PUT body (built with the same
/// [DailyPlanRepository.buildUpdateBody] the real PUT uses) and applies it
/// like the server does (absent key = keep, null = clear).
class _FakeDailyPlanRepository extends Fake implements DailyPlanRepository {
  _FakeDailyPlanRepository(this.plan);

  DailyPlan plan;
  Failure? failure;
  final bodies = <Map<String, dynamic>>[];

  @override
  Future<Either<Failure, DailyPlan>> getPlan(DateTime day) async => Right(plan);

  @override
  Future<Either<Failure, DailyPlan>> updatePlan(
    DateTime day, {
    PlanField<int> mainFocusTaskId = const PlanField.unset(),
    PlanField<int> sideFocusTaskId = const PlanField.unset(),
    PlanField<String> sayNoText = const PlanField.unset(),
  }) async {
    final body = DailyPlanRepository.buildUpdateBody(
      mainFocusTaskId: mainFocusTaskId,
      sideFocusTaskId: sideFocusTaskId,
      sayNoText: sayNoText,
    );
    bodies.add(body);
    if (failure != null) return Left(failure!);

    Task? byId(Object? id) =>
        id == null ? null : plan.tasks.firstWhere((t) => t.id == id);
    plan = DailyPlan(
      planDate: plan.planDate,
      mainFocus: body.containsKey('main_focus_task_id')
          ? byId(body['main_focus_task_id'])
          : plan.mainFocus,
      sideFocus: body.containsKey('side_focus_task_id')
          ? byId(body['side_focus_task_id'])
          : plan.sideFocus,
      sayNoText: body.containsKey('say_no_text') ? body['say_no_text'] as String? : plan.sayNoText,
      tasks: plan.tasks,
    );
    return Right(plan);
  }
}

void main() {
  late _MockDailyPlanRepository repo;
  late DailyPlan plan;
  late Task taskToPick;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(const PlanField<int>.unset());
    registerFallbackValue(const PlanField<String>.unset());
  });

  setUp(() {
    repo = _MockDailyPlanRepository();
    plan = _fixturePlan();
    when(() => repo.getPlan(any())).thenAnswer((_) async => Right(plan));
  });

  void stubUpdate(Either<Failure, DailyPlan> Function() result) {
    when(() => repo.updatePlan(
          any(),
          mainFocusTaskId: any(named: 'mainFocusTaskId'),
          sideFocusTaskId: any(named: 'sideFocusTaskId'),
          sayNoText: any(named: 'sayNoText'),
        )).thenAnswer((_) async => result());
  }

  void verifyNoUpdate() {
    verifyNever(() => repo.updatePlan(
          any(),
          mainFocusTaskId: any(named: 'mainFocusTaskId'),
          sideFocusTaskId: any(named: 'sideFocusTaskId'),
          sayNoText: any(named: 'sayNoText'),
        ));
  }

  Future<void> pumpHome(WidgetTester tester, {DailyPlanRepository? repository}) async {
    tester.view.physicalSize = const Size(790, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: AppRouter.focusTaskSelectionPath,
        builder: (_, _) => _StubSelectionPage(taskToPick),
      ),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => repository ?? repo),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> pickFocus(WidgetTester tester, String emptyLabel, Task task) async {
    taskToPick = task;
    await tester.tap(find.text(emptyLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seç'));
    await tester.pumpAndSettle();
  }

  void expectNoErrorScreenOrEnglish() {
    expect(find.byType(DailyPlanError), findsNothing);
    expect(find.text('Plan yüklenemedi'), findsNothing);
    expect(find.textContaining('focus'), findsNothing);
    expect(find.textContaining('cannot'), findsNothing);
    expect(find.textContaining('Instance of'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);
  }

  Finder inMainCard(String text) =>
      find.descendant(of: find.byType(MainFocusCard), matching: find.text(text));
  Finder inSideCard(String text) =>
      find.descendant(of: find.byType(SideFocusCard), matching: find.text(text));

  group('Focus selection on HomeScreen', () {
    testWidgets('(a) main focus task chosen as side focus: no request, snackbar, screen intact',
        (tester) async {
      await pumpHome(tester);
      expect(inMainCard('Ana odak görevi'), findsOneWidget);

      await pickFocus(tester, 'İkincil odak seç', plan.mainFocus!);

      verifyNoUpdate();
      expect(find.widgetWithText(SnackBar, 'Bu görev zaten ana odak.'), findsOneWidget);
      expect(inMainCard('Ana odak görevi'), findsOneWidget);
      expect(inSideCard('İkincil odak seç'), findsOneWidget);
      expectNoErrorScreenOrEnglish();
    });

    testWidgets('(a\') side focus task chosen as main focus: no request, snackbar', (tester) async {
      final side = plan.tasks.first; // "İlk görev - yapılacak"
      plan = plan.copyWith(mainFocus: null, sideFocus: side);
      await pumpHome(tester);

      await pickFocus(tester, 'Ana odak seç', side);

      verifyNoUpdate();
      expect(find.widgetWithText(SnackBar, 'Bu görev zaten ikincil odak.'), findsOneWidget);
      expect(inSideCard('İlk görev - yapılacak'), findsOneWidget);
      expect(inMainCard('Ana odak seç'), findsOneWidget);
      expectNoErrorScreenOrEnglish();
    });

    testWidgets('(b) server 422 safety net: old focuses stay, Turkish snackbar, no error screen',
        (tester) async {
      stubUpdate(() => const Left(
          ServerFailure(DailyPlanRepository.planUpdateInvalidMessage, statusCode: 422)));
      await pumpHome(tester);

      await pickFocus(tester, 'İkincil odak seç', plan.tasks[3]);

      verify(() => repo.updatePlan(_planDay, sideFocusTaskId: const PlanField.set(4))).called(1);
      expect(
        find.widgetWithText(SnackBar, 'Plan güncellenemedi. Lütfen seçimi kontrol edin.'),
        findsOneWidget,
      );
      expect(inMainCard('Ana odak görevi'), findsOneWidget);
      expect(inSideCard('İkincil odak seç'), findsOneWidget);
      expect(find.byType(DailyPlanLoading), findsNothing);
      expectNoErrorScreenOrEnglish();
    });

    testWidgets('valid side focus selection updates the side card, no snackbar', (tester) async {
      stubUpdate(() => Right(plan.copyWith(sideFocus: plan.tasks[3])));
      await pumpHome(tester);

      await pickFocus(tester, 'İkincil odak seç', plan.tasks[3]);

      expect(inSideCard('Dördüncü görev - yapılacak'), findsOneWidget);
      expect(inMainCard('Ana odak görevi'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('SayNoCard save', () {
    Finder sayNoField() =>
        find.descendant(of: find.byType(SayNoCard), matching: find.byType(TextField));

    Future<void> typeAndBlur(WidgetTester tester, String text) async {
      await tester.enterText(sayNoField(), text);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    Future<void> refocusAndBlur(WidgetTester tester) async {
      await tester.tap(sayNoField());
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
    }

    testWidgets('failed save keeps typed text + snackbar; next blur retries; success stops resends',
        (tester) async {
      var fail = true;
      stubUpdate(() => fail
          ? const Left(NetworkFailure('timeout'))
          : Right(plan.copyWith(sayNoText: 'Toplantılar')));
      await pumpHome(tester);

      // 1) Save fails: text stays, Turkish snackbar
      await typeAndBlur(tester, 'Toplantılar');
      verify(() => repo.updatePlan(_planDay, sayNoText: const PlanField.set('Toplantılar'))).called(1);
      expect(tester.widget<TextField>(sayNoField()).controller!.text, 'Toplantılar');
      expect(find.widgetWithText(SnackBar, 'Bağlantı hatası'), findsOneWidget);
      expectNoErrorScreenOrEnglish();

      // 2) Next focus loss retries (comparison uses last SUCCESSFUL value)
      ScaffoldMessenger.of(tester.element(find.byType(SayNoCard))).clearSnackBars();
      await tester.pumpAndSettle();
      fail = false;
      await refocusAndBlur(tester);
      verify(() => repo.updatePlan(_planDay, sayNoText: const PlanField.set('Toplantılar'))).called(1);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.widget<TextField>(sayNoField()).controller!.text, 'Toplantılar');

      // 3) Unchanged after success: no new request
      await refocusAndBlur(tester);
      verifyNoUpdate();
    });

    testWidgets('stored null + empty field: blur sends no request', (tester) async {
      final fake = _FakeDailyPlanRepository(plan); // fixture say_no_text is null
      await pumpHome(tester, repository: fake);

      await refocusAndBlur(tester);
      await typeAndBlur(tester, '   '); // whitespace-only == null

      expect(fake.bodies, isEmpty);
    });

    for (final emptied in ['', '   ']) {
      testWidgets('saved text emptied to "$emptied" + blur sends explicit null, then nothing',
          (tester) async {
        final fake = _FakeDailyPlanRepository(plan.copyWith(sayNoText: 'Toplantılar'));
        await pumpHome(tester, repository: fake);
        expect(tester.widget<TextField>(sayNoField()).controller!.text, 'Toplantılar');

        await typeAndBlur(tester, emptied);

        expect(fake.bodies, [
          {'say_no_text': null},
        ]);
        expect(fake.bodies.single['say_no_text'], isNot(''));
        expect(fake.plan.sayNoText, isNull);
        expect(tester.widget<TextField>(sayNoField()).controller!.text, '');
        expect(find.byType(SnackBar), findsNothing);

        // Now stored null == empty field: no further request
        await refocusAndBlur(tester);
        expect(fake.bodies, hasLength(1));
      });
    }
  });

  group('Clearing focus on HomeScreen', () {
    Finder clearIn(Type card) =>
        find.descendant(of: find.byType(card), matching: find.text('Temizle'));

    testWidgets('main focus "Temizle": card shows empty state, PUT body is explicit null',
        (tester) async {
      final fake = _FakeDailyPlanRepository(plan);
      await pumpHome(tester, repository: fake);
      expect(inMainCard('Ana odak görevi'), findsOneWidget);

      await tester.tap(clearIn(MainFocusCard));
      await tester.pumpAndSettle();

      expect(fake.bodies, [
        {'main_focus_task_id': null},
      ]);
      expect(inMainCard('Ana odak seç'), findsOneWidget);
      expect(inMainCard('Ana odak görevi'), findsNothing);
      expect(clearIn(MainFocusCard), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expectNoErrorScreenOrEnglish();
    });

    testWidgets('side focus "Temizle": side card empty, main untouched', (tester) async {
      final fake = _FakeDailyPlanRepository(plan.copyWith(sideFocus: plan.tasks[3]));
      await pumpHome(tester, repository: fake);
      expect(inSideCard('Dördüncü görev - yapılacak'), findsOneWidget);

      await tester.tap(clearIn(SideFocusCard));
      await tester.pumpAndSettle();

      expect(fake.bodies, [
        {'side_focus_task_id': null},
      ]);
      expect(inSideCard('İkincil odak seç'), findsOneWidget);
      expect(inMainCard('Ana odak görevi'), findsOneWidget);
    });

    testWidgets('clear failure: old focus stays, Turkish snackbar, no error screen',
        (tester) async {
      final fake = _FakeDailyPlanRepository(plan)..failure = const NetworkFailure('timeout');
      await pumpHome(tester, repository: fake);

      await tester.tap(clearIn(MainFocusCard));
      await tester.pumpAndSettle();

      expect(fake.bodies, [
        {'main_focus_task_id': null},
      ]);
      expect(inMainCard('Ana odak görevi'), findsOneWidget);
      expect(find.widgetWithText(SnackBar, 'Bağlantı hatası'), findsOneWidget);
      expect(find.byType(DailyPlanLoading), findsNothing);
      expectNoErrorScreenOrEnglish();
    });
  });
}
