// Home layout overflow: the real app router + real MainScaffold (bottom bar
// <= 800px, extended side rail > 800px) draws HomeScreen at several window
// widths. Data comes from real backend JSON (test/fixtures/), with long,
// realistic titles so the worst case is drawn: both focus slots filled (both
// "Temizle" buttons visible), a long say-no text and a long routine title.

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
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/focus_candidates.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/focus_task_selection_page.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/daily_tasks_card.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/home/presentation/widgets/routines_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
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
    tasks: [
      tasks.first.copyWith(
        title: 'Kira sözleşmesi yenilemesi için emlakçıyı ara ve gerekli belgeleri hazırla',
      ),
      ...tasks.skip(1),
    ],
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

/// Routines from real backend JSON, the first one with a long title.
List<RoutineDayItem> _routines() {
  final items = (jsonDecode(File('test/fixtures/routines_day.json').readAsStringSync()) as List)
      .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
      .toList();
  return [items.first.copyWith(title: _routineTitle), ...items.skip(1)];
}

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
  Future<void> pumpApp(WidgetTester tester, double width, {double textScale = 1.0}) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(routerConfig: ref.watch(routerProvider)),
        ),
      ),
    );
    await tester.pumpAndSettle();
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
    expect(
      find.descendant(of: find.byType(RoutinesCard), matching: find.text(_routineTitle)),
      findsOneWidget,
    );
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

  group('Home has no overflow with the real side rail / bottom bar layout', () {
    for (final width in [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0]) {
      testWidgets('width ${width.toInt()}px', (tester) async {
        await pumpApp(tester, width);
        expect(tester.takeException(), isNull);
        expectWorstCaseDrawn(tester, width);
      });
    }
  });

  group('Home has no overflow with system text scale 1.5', () {
    for (final width in [1000.0, 1200.0, 1400.0, 1800.0]) {
      testWidgets('width ${width.toInt()}px, textScale 1.5', (tester) async {
        await pumpApp(tester, width, textScale: 1.5);
        expect(tester.takeException(), isNull);
        expectWorstCaseDrawn(tester, width);
      });
    }
  });

  /// Pumps the focus selection page alone (it is a full-screen route
  /// outside the shell, so no menu/rail around it), opened by push with
  /// [FocusSlot.main] like the main focus card does.
  Future<void> pumpFocusPage(WidgetTester tester, double width, double textScale) async {
    tester.view.physicalSize = Size(width, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
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
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.tap(find.text('Aç'));
    await tester.pumpAndSettle();
  }

  // Note: HomeScreen itself overflows at 360px + 1.5x (RoutinesCard header
  // row, routines_card.dart); that is outside this page and not hidden here.
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
