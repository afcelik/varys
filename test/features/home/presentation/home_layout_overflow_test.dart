// Home layout overflow: the real app router + real MainScaffold (bottom bar
// <= 800px, extended side rail > 800px) draws HomeScreen at several window
// widths. Data comes from real backend JSON (test/fixtures/), with long,
// realistic titles so the worst case is drawn: both focus slots filled (both
// "Temizle" buttons visible), a long say-no text, long open and done task
// titles, and long routine titles with visible streaks (one routine done).
// Every width runs at text scale 1.0 and 1.5. Home is also drawn with both
// focus slots empty, with everything empty, and with the plan in its error
// and loading states; the routines card in its empty, loading and error states.

import 'dart:async';

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/focus_candidates.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/focus_task_selection_page.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/daily_plan_state_widgets.dart';
import 'package:varys/features/home/presentation/widgets/daily_tasks_card.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/home/presentation/widgets/inbox_card.dart';
import 'package:varys/features/home/presentation/widgets/random_note_card.dart';
import 'package:varys/features/home/presentation/widgets/routines_card.dart';
import 'package:varys/features/home/presentation/widgets/say_no_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';

import '../../../helpers/varys_app_harness.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 1);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _mainFocusTitle =
    'Çeyrek sonu finans raporunu bitir, ekiple gözden geçir ve yönetim kuruluna gönder';
const _sideFocusTitle = 'Yeni müşteri sözleşmesinin hukuki incelemesini tamamla ve imzaya hazırla';
const _sayNoText = 'Öğleden önce sosyal medya, e-posta bildirimleri ve plansız toplantılar';
const _routineTitle = 'Akşam yürüyüşünden sonra yarının planını gözden geçir ve not al';

/// Long routine titles by fixture id. Id 1 is done with streak 3 (fixture);
/// id 2 is open and gets a two-digit streak (12).
const _routineTitles = {
  1: _routineTitle,
  2: 'Sabah koşusu: sahil boyunca beş kilometre, ardından esneme ve kısa meditasyon',
  3: 'Elektrik, su, doğalgaz ve internet faturalarını öde, dekontları arşive kaydet',
  4: 'Balkondaki bütün bitkileri sula, kuruyan yaprakları temizle ve gübre ekle',
};

/// Long daily task titles by fixture id (1, 2, 4 open; 3, 5 done).
const _taskTitles = {
  1: 'Kira sözleşmesi yenilemesi için emlakçıyı ara ve gerekli belgeleri hazırla',
  2: 'Haftalık ekip toplantısının gündemini hazırla ve katılımcılara e-postayla gönder',
  3: 'Geçen ayın kredi kartı ekstresini kontrol et ve itiraz edilecek harcamaları işaretle',
  4: 'Araç muayenesi için randevu al, sigorta poliçesini ve ruhsatı yanına hazırla',
  5: 'Doktor randevusundaki tahlil sonuçlarını e-Nabız üzerinden indir ve yazdır',
};

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Plan from real backend JSON, with both focus slots filled by long titles.
DailyPlan _worstCasePlan() {
  final json = _readJson('test/fixtures/daily_plan_with_tasks.json');
  final tasks = (json['tasks'] as List)
      .map((t) => Task.fromJson(t as Map<String, dynamic>))
      .toList();
  final main = Task.fromJson(
    json['main_focus'] as Map<String, dynamic>,
  ).copyWith(title: _mainFocusTitle);
  final side = tasks[1].copyWith(title: _sideFocusTitle);
  return DailyPlan(
    planDate: _day,
    mainFocus: main,
    sideFocus: side,
    sayNoText: _sayNoText,
    tasks: [for (final t in tasks) t.copyWith(title: _taskTitles[t.id]!)],
  );
}

const _pageSelectableTitle =
    'Kira sözleşmesi yenilemesi için emlakçıyı ara, gerekli belgeleri hazırla ve randevu al';
const _pageSideTitle =
    'Yeni müşteri sözleşmesinin hukuki incelemesini tamamla, notları paylaş ve imzaya hazırla';
const _pageMainTitle = 'Çeyrek sonu finans raporunu bitir, ekiple gözden geçir ve yönetim kuruluna';
const _pageTempTitle =
    'Sunucuya henüz kaydedilmemiş, çok uzun başlıklı geçici görev: haftalık bütçe tablosunu güncelle';

/// Worst case for the focus selection page (main slot), from real backend
/// JSON: every row state at once, all with long titles: selectable (1),
/// other-slot focus (2, "İkincil odak"), this slot's focus (4, check) and a
/// temporary task (-1, "Ekleniyor…"). Done tasks (3, 5) are not listed.
DailyPlan _focusPagePlan() {
  final json = _readJson('test/fixtures/daily_plan_with_tasks.json');
  final tasks = (json['tasks'] as List)
      .map((t) => Task.fromJson(t as Map<String, dynamic>))
      .toList();
  Task byId(int id) => tasks.firstWhere((t) => t.id == id);
  final selectable = byId(1).copyWith(title: _pageSelectableTitle);
  final side = byId(2).copyWith(title: _pageSideTitle);
  final main = byId(4).copyWith(title: _pageMainTitle);
  final temp = byId(1).copyWith(id: -1, title: _pageTempTitle);
  return DailyPlan(
    planDate: _day,
    mainFocus: main,
    sideFocus: side,
    tasks: [temp, selectable, side, byId(3), main, byId(5)],
  );
}

/// Routines from real backend JSON, all with long titles; id 1 is done with
/// streak 3 (as in the fixture), id 2 is open with streak 12.
List<RoutineDayItem> _routines() {
  final items = (jsonDecode(File('test/fixtures/routines_day.json').readAsStringSync()) as List)
      .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
      .toList();
  return [
    for (final item in items)
      item.copyWith(
        title: _routineTitles[item.id]!,
        currentStreak: item.id == 2 ? 12 : item.currentStreak,
      ),
  ];
}

/// Worst case with both focus slots empty; every other card stays filled.
DailyPlan _focusesEmptyPlan() => _worstCasePlan().copyWith(mainFocus: null, sideFocus: null);

/// Everything empty: no focus, no say-no text, no tasks (routines: Right([])).
DailyPlan _allEmptyPlan() => DailyPlan(planDate: _day, tasks: const []);

// UI texts with no static const in lib/ (typed here; keep in sync).
const _mainEmptyLabel = 'Ana odak seç'; // focus_cards.dart MainFocusCard
const _sideEmptyLabel = 'İkincil odak seç'; // focus_cards.dart SideFocusCard
const _sayNoHint = 'Örn: Sosyal medya, gereksiz toplantılar...'; // say_no_card.dart
const _noTasksText = 'Bugün için görev yok'; // daily_tasks_card.dart _EmptyTasks
const _planErrorTitle = 'Plan yüklenemedi'; // daily_plan_state_widgets.dart
const _planRetryText = 'Tekrar Dene'; // daily_plan_state_widgets.dart

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _textScales = [1.0, 1.5];

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    final plan = _worstCasePlan();
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(plan.tasks));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(_routines()));
  });

  List<Override> overrides() => [
    todayProvider.overrideWith(_FixedToday.new),
    dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
    taskRepositoryProvider.overrideWith((ref) async => taskRepo),
    routineRepositoryProvider.overrideWith((ref) async => routineRepo),
  ];

  /// Pumps the real app (real router, real MainScaffold) logged in on Home.
  /// With [settle] false (a request left pending) pumpAndSettle is not used
  /// (it could hang); it pumps 100ms steps until Home is drawn (max 3s).
  Future<void> pumpApp(
    WidgetTester tester,
    double width, {
    double textScale = 1.0,
    bool settle = true,
  }) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Real app root with the real routerProvider (no router override).
    await pumpVarysApp(
      tester,
      overrides: overrides(),
      textScale: textScale != 1.0 ? textScale : null,
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 30 && find.byType(HomeScreen).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Asserts the worst case was really drawn inside the real shell layout.
  void expectWorstCaseDrawn(WidgetTester tester, double width) {
    expect(find.byType(HomeScreen), findsOneWidget);
    if (width > 800) {
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    } else {
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    }
    // The card titles under test are really drawn (longest variants).
    expect(find.text('Günün Ana Odağı'), findsOneWidget);
    expect(find.text('Bugün Yapılacaklar'), findsOneWidget);
    // Both focus slots filled -> both "Temizle" buttons visible.
    expect(find.text('Temizle'), findsNWidgets(2));
    expect(
      find.descendant(of: find.byType(MainFocusCard), matching: find.text(_mainFocusTitle)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(SideFocusCard), matching: find.text(_sideFocusTitle)),
      findsOneWidget,
    );
    expect(find.text(_sayNoText), findsOneWidget);
    // Long open and done task titles in the daily tasks card.
    for (final title in _taskTitles.values) {
      expect(
        find.descendant(of: find.byType(DailyTasksCard), matching: find.text(title)),
        findsOneWidget,
        reason: title,
      );
    }
    // Routines card: every long title, streak icon + number (done id 1 with
    // 3, open id 2 with 12), the done checkbox ticked, counter and "Daha fazla".
    Finder inRoutines(Finder f) => find.descendant(of: find.byType(RoutinesCard), matching: f);
    for (final title in _routineTitles.values) {
      expect(inRoutines(find.text(title)), findsOneWidget, reason: title);
    }
    expect(inRoutines(find.byIcon(Icons.local_fire_department)), findsNWidgets(2));
    for (final (id, streak) in [(1, '3'), (2, '12')]) {
      final row = inRoutines(find.byKey(ValueKey('streak-$id')));
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.byIcon(Icons.local_fire_department)),
        findsOneWidget,
      );
      expect(find.descendant(of: row, matching: find.text(streak)), findsOneWidget);
    }
    final doneCheckbox = tester.widget<Checkbox>(
      find.descendant(
        of: find.ancestor(of: inRoutines(find.text(_routineTitle)), matching: find.byType(ListTile)),
        matching: find.byType(Checkbox),
      ),
    );
    expect(doneCheckbox.value, isTrue);
    // Two separate counters: routines 1 done of 4, daily tasks 2 done of 5.
    expect(inRoutines(find.text('1/4')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(DailyTasksCard), matching: find.text('2/5')),
      findsOneWidget,
    );
    expect(inRoutines(find.text(RoutinesCard.moreText)), findsOneWidget);
    // "Planlamadan ekle" button in the daily tasks header, full 48x48 tap target.
    final addButton = find.descendant(
      of: find.byType(DailyTasksCard),
      matching: find.byTooltip('Planlamadan ekle'),
    );
    expect(addButton, findsOneWidget);
    // Measure the whole button (incl. tap padding), found via its tooltip.
    final size = tester.getSize(find.ancestor(of: addButton, matching: find.byType(IconButton)));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  }

  /// The real shell around Home: side rail > 800px, bottom bar <= 800px,
  /// and the Home app bar.
  void expectShell(double width) {
    if (width > 800) {
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    } else {
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    }
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Ana Sayfa')),
      findsOneWidget,
    );
  }

  /// Both empty focus tiles: label drawn, tap target >= 48x48, tile fully on
  /// screen and the label fully inside its tile (an overflowing label is not).
  void expectEmptyFocusTargets(WidgetTester tester, double width) {
    for (final (card, label) in [
      (MainFocusCard, _mainEmptyLabel),
      (SideFocusCard, _sideEmptyLabel),
    ]) {
      final text = find.descendant(of: find.byType(card), matching: find.text(label));
      expect(text, findsOneWidget, reason: label);
      final tile = find.ancestor(of: text, matching: find.byType(InkWell)).first;
      final size = tester.getSize(tile);
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, greaterThanOrEqualTo(48), reason: label);
      final tileRect = tester.getRect(tile);
      expect(tileRect.left, greaterThanOrEqualTo(0), reason: label);
      expect(tileRect.right, lessThanOrEqualTo(width), reason: label);
      final textRect = tester.getRect(text);
      expect(textRect.left, greaterThanOrEqualTo(tileRect.left), reason: label);
      expect(textRect.right, lessThanOrEqualTo(tileRect.right), reason: label);
    }
    expect(find.text('Temizle'), findsNothing);
    expect(find.text('Günün Ana Odağı'), findsOneWidget);
    expect(find.text('İkincil Odak'), findsOneWidget);
  }

  /// Plan loading/error replaces the whole Home body: no plan cards, no
  /// routines card, no placeholder cards.
  void expectNoPlanCards() {
    for (final type in [
      MainFocusCard,
      SideFocusCard,
      SayNoCard,
      DailyTasksCard,
      RoutinesCard,
      RandomNoteCard,
      InboxCard,
    ]) {
      expect(find.byType(type), findsNothing, reason: '$type');
    }
  }

  group('Home states have no overflow with the real side rail / bottom bar layout', () {
    Finder inRoutines(Finder f) => find.descendant(of: find.byType(RoutinesCard), matching: f);
    Finder inTasks(Finder f) => find.descendant(of: find.byType(DailyTasksCard), matching: f);

    for (final width in _widths) {
      for (final textScale in _textScales) {
        final label = 'width ${width.toInt()}px, textScale $textScale';

        testWidgets('(a) all filled, $label', (tester) async {
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull);
          expectWorstCaseDrawn(tester, width);
        });

        testWidgets('(b) focuses empty, others filled, $label', (tester) async {
          final plan = _focusesEmptyPlan();
          when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull);
          expect(find.byType(HomeScreen), findsOneWidget);
          expectShell(width);
          expectEmptyFocusTargets(tester, width);
          expect(find.text(_sayNoText), findsOneWidget);
          for (final title in _taskTitles.values) {
            expect(inTasks(find.text(title)), findsOneWidget, reason: title);
          }
          for (final title in _routineTitles.values) {
            expect(inRoutines(find.text(title)), findsOneWidget, reason: title);
          }
        });

        testWidgets('(c) all empty, $label', (tester) async {
          final plan = _allEmptyPlan();
          when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
          when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
          when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull);
          expect(find.byType(HomeScreen), findsOneWidget);
          expectShell(width);
          expectEmptyFocusTargets(tester, width);
          expect(
            find.descendant(of: find.byType(SayNoCard), matching: find.text(_sayNoHint)),
            findsOneWidget,
          );
          expect(inTasks(find.text(_noTasksText)), findsOneWidget);
          expect(inTasks(find.text('0/0')), findsOneWidget);
          expect(inRoutines(find.text(RoutinesCard.emptyText)), findsOneWidget);
          expect(inRoutines(find.text('0/0')), findsOneWidget);
        });

        testWidgets('(d) plan error, $label', (tester) async {
          const failure = NetworkFailure('timeout');
          when(() => planRepo.getPlan(any())).thenAnswer((_) async => const Left(failure));
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull);
          expect(find.byType(HomeScreen), findsOneWidget);
          expectShell(width);
          final error = find.byType(DailyPlanError);
          expect(error, findsOneWidget);
          Finder inError(Finder f) => find.descendant(of: error, matching: f);
          expect(inError(find.text(_planErrorTitle)), findsOneWidget);
          expect(inError(find.text(userMessage(failure))), findsOneWidget);
          expect(inError(find.text(_planRetryText)), findsOneWidget);
          expectNoPlanCards();
        });

        testWidgets('(e) plan loading, $label', (tester) async {
          final pending = Completer<Either<Failure, DailyPlan>>();
          addTearDown(() {
            if (!pending.isCompleted) pending.complete(Right(_worstCasePlan()));
          });
          when(() => planRepo.getPlan(any())).thenAnswer((_) => pending.future);
          await pumpApp(tester, width, textScale: textScale, settle: false);
          expect(tester.takeException(), isNull);
          expect(find.byType(HomeScreen), findsOneWidget);
          expectShell(width);
          expect(find.byType(DailyPlanLoading), findsOneWidget);
          expect(find.byType(DailyPlanError), findsNothing);
          expectNoPlanCards();
        });
      }
    }
  });

  group('Plan error "Tekrar Dene" reloads Home', () {
    for (final (width, textScale) in [(360.0, 1.0), (1400.0, 1.5)]) {
      testWidgets('width ${width.toInt()}px, textScale $textScale', (tester) async {
        const failure = NetworkFailure('timeout');
        final plan = _worstCasePlan();
        var calls = 0;
        when(() => planRepo.getPlan(any())).thenAnswer((_) async {
          calls++;
          if (calls == 1) return const Left(failure);
          return Right(plan);
        });
        await pumpApp(tester, width, textScale: textScale);
        expect(tester.takeException(), isNull);
        expect(find.byType(DailyPlanError), findsOneWidget);
        expect(find.text(userMessage(failure)), findsOneWidget);

        await tester.tap(find.text(_planRetryText));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(DailyPlanError), findsNothing);
        expect(
          find.descendant(of: find.byType(MainFocusCard), matching: find.text(_mainFocusTitle)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: find.byType(SideFocusCard), matching: find.text(_sideFocusTitle)),
          findsOneWidget,
        );
        for (final title in _taskTitles.values) {
          expect(
            find.descendant(of: find.byType(DailyTasksCard), matching: find.text(title)),
            findsOneWidget,
            reason: title,
          );
        }
        verify(() => planRepo.getPlan(any())).called(2);
      });
    }
  });

  group('Routines card states have no overflow on Home', () {
    Finder inRoutines(Finder f) => find.descendant(of: find.byType(RoutinesCard), matching: f);

    void expectCardFrame() {
      expect(inRoutines(find.text(RoutinesCard.title)), findsOneWidget);
      expect(inRoutines(find.text(RoutinesCard.moreText)), findsOneWidget);
    }

    for (final width in _widths) {
      for (final textScale in _textScales) {
        final label = 'width ${width.toInt()}px, textScale $textScale';

        testWidgets('empty, $label', (tester) async {
          when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull);
          expectCardFrame();
          expect(inRoutines(find.text(RoutinesCard.emptyText)), findsOneWidget);
          expect(inRoutines(find.text('0/0')), findsOneWidget);
        });

        testWidgets('loading, $label', (tester) async {
          final pending = Completer<Either<Failure, List<RoutineDayItem>>>();
          addTearDown(() {
            if (!pending.isCompleted) pending.complete(const Right([]));
          });
          when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) => pending.future);
          await pumpApp(tester, width, textScale: textScale, settle: false);
          expect(tester.takeException(), isNull);
          expectCardFrame();
          expect(inRoutines(find.byKey(const ValueKey('routines-skeleton'))), findsOneWidget);
          expect(inRoutines(find.textContaining('/')), findsNothing); // no counter yet
        });

        testWidgets('error, $label', (tester) async {
          const failure = NetworkFailure('timeout');
          when(() => routineRepo.getRoutinesForDay(any()))
              .thenAnswer((_) async => const Left(failure));
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull);
          expectCardFrame();
          expect(inRoutines(find.text(userMessage(failure))), findsOneWidget);
          expect(inRoutines(find.text(RoutinesCard.retryText)), findsOneWidget);
        });
      }
    }
  });

  /// Pumps the focus selection page alone (it is a full-screen route
  /// outside the shell, so no menu/rail around it), opened by push with
  /// [FocusSlot.main] like the main focus card does.
  Future<void> pumpFocusPage(WidgetTester tester, double width, double textScale) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  context.push<Task>(AppRouter.focusTaskSelectionPath, extra: FocusSlot.main),
              child: const Text('Aç'),
            ),
          ),
        ),
        GoRoute(
          path: AppRouter.focusTaskSelectionPath,
          builder: (_, state) => FocusTaskSelectionPage(slot: state.extra as FocusSlot),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: overrides(),
      textScale: textScale != 1.0 ? textScale : null,
    );
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
  }

  group('Focus selection page has no overflow (long titles, every row state)', () {
    for (final width in [360.0, 1400.0]) {
      for (final textScale in [1.0, 1.5]) {
        testWidgets('width ${width.toInt()}px, textScale $textScale', (tester) async {
          final plan = _focusPagePlan();
          when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
          await pumpFocusPage(tester, width, textScale);

          expect(tester.takeException(), isNull);
          final page = find.byType(FocusTaskSelectionPage);
          expect(page, findsOneWidget);
          Finder inPage(Finder f) => find.descendant(of: page, matching: f);

          // Every row state is really drawn, with its long title.
          for (final title in [
            _pageTempTitle,
            _pageSelectableTitle,
            _pageSideTitle,
            _pageMainTitle,
          ]) {
            expect(inPage(find.text(title)), findsOneWidget, reason: title);
          }
          expect(inPage(find.text('İkincil odak')), findsOneWidget);
          expect(inPage(find.text('Ekleniyor…')), findsOneWidget);
          expect(inPage(find.byIcon(Icons.check_circle)), findsOneWidget);
          expect(inPage(find.text('Ana odak seç')), findsOneWidget);

          // "Planlamadan ekle" in the app bar keeps a 48x48 tap target.
          final addButton = find.ancestor(
            of: inPage(find.byTooltip('Planlamadan ekle')),
            matching: find.byType(IconButton),
          );
          expect(addButton, findsOneWidget);
          final size = tester.getSize(addButton);
          expect(size.width, greaterThanOrEqualTo(48));
          expect(size.height, greaterThanOrEqualTo(48));
        });
      }
    }
  });
}
