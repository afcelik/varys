// Home layout overflow: the real app router + real MainScaffold (bottom bar
// <= 800px, extended side rail > 800px) draws HomeScreen at several window
// widths. Data comes from real backend JSON (test/fixtures/), with long,
// realistic titles so the worst case is drawn: both focus slots filled (both
// "Temizle" buttons visible), a long say-no text, long open and done task
// titles, and long routine titles with visible streaks (one routine done).
// Every width runs at text scale 1.0 and 1.5. Home is also drawn with both
// focus slots empty, with everything empty, and with the plan in its error
// and loading states; the routines card in its empty, loading and error states;
// the projects card filled (long titles, progress null/0/100, target date set
// and null), empty, loading and error; the "Günün Notu" card filled (an
// unbroken 255-character title, a 60-line body, 6 tags; the content tap
// target at least 48 high and apart from "Daha fazla"), empty, loading and
// error. The /projects skeleton page is drawn at 360px with text scale 1.0
// and 1.5.

import 'dart:async';

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:varys/features/home/presentation/widgets/projects_card.dart';
import 'package:varys/features/home/presentation/widgets/random_note_card.dart';
import 'package:varys/features/home/presentation/widgets/routines_card.dart';
import 'package:varys/features/home/presentation/widgets/say_no_card.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/projects/presentation/projects_screen.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../notes/fake_note_repository.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/core/theme/app_theme.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

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

/// Long project titles; each wraps to (and is cut at) two lines at 360px.
const _projectTitleNull =
    'Kitap okuma listesi: yılın klasiklerini, birikmiş romanları ve iş kitaplarını bitir';
const _projectTitleZero =
    'Ev taşıma: nakliye, kutular, adres değişikliği, abonelikler ve yeni evin temizliği';
const _projectTitleFull =
    'Vergi beyannamesi: belgeleri topla, giderleri ayıkla, beyannameyi hazırla ve gönder';

/// Worst case for the projects card, from real backend JSON
/// (test/fixtures/projects_list.json): three active projects (the limit),
/// long titles, every progress state at once and target date set and null.
///   2 -> no tasks, progress null, no target date ("Henüz görev yok", no bar)
///   1 -> 0 of 4 done, progress 0, target 2026-11-20 (empty bar, "%0")
///   5 -> 2 of 2 done, progress 100, target 2026-10-31 (full bar, "%100")
List<Project> _worstCaseProjects() {
  final all = (jsonDecode(File('test/fixtures/projects_list.json').readAsStringSync()) as List)
      .map((e) => Project.fromJson(e as Map<String, dynamic>))
      .toList();
  Project byId(int id) => all.firstWhere((p) => p.id == id);
  return [
    byId(2).copyWith(title: _projectTitleNull),
    byId(1).copyWith(title: _projectTitleZero, doneTasks: 0, progressPercent: 0),
    byId(5).copyWith(title: _projectTitleFull, status: ProjectStatus.active),
  ];
}

ProjectLimits _limits() => ProjectLimits.fromJson(
      jsonDecode(File('test/fixtures/projects_limits.json').readAsStringSync())
          as Map<String, dynamic>,
    );

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

/// Title clamp cases: an unbroken 255-char title, a 255-char many-word title
/// and a short reference title.
final _unbrokenTitle = 'G' * 255;
final _manyWordsTitle = List.filled(40, 'Uzunbaşlıklıgörev').join(' ').substring(0, 255);
const _shortTitle = 'Kısa başlık';

/// Worst case plan, open tasks 1 (short), 2 (unbroken) and 4 (many words).
DailyPlan _clampPlan() {
  final plan = _worstCasePlan();
  return plan.copyWith(
    tasks: [
      for (final t in plan.tasks)
        switch (t.id) {
          1 => t.copyWith(title: _shortTitle),
          2 => t.copyWith(title: _unbrokenTitle),
          4 => t.copyWith(title: _manyWordsTitle),
          _ => t,
        },
    ],
  );
}

/// Routines, open and without streak: 3 (short), 4 (unbroken), 2 (many words).
List<RoutineDayItem> _clampRoutines() => [
  for (final r in _routines())
    switch (r.id) {
      3 => r.copyWith(title: _shortTitle),
      4 => r.copyWith(title: _unbrokenTitle),
      2 => r.copyWith(title: _manyWordsTitle, currentStreak: 0),
      _ => r,
    },
];

/// The note of the day, worst case: the real 255-character unbroken title,
/// the real 60-line body and 6 tags (3 drawn + "+3").
Note _worstCaseNote() {
  final notes = notesFixture();
  return notes
      .firstWhere((n) => n.id == 2)
      .copyWith(
        body: notes.firstWhere((n) => n.id == 3).body,
        tags: [for (var i = 0; i < 6; i++) 'proje fikirleri $i'],
      );
}

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _textScales = [1.0, 1.5];

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockTaskRepository taskRepo;
  late _MockRoutineRepository routineRepo;
  late _MockProjectRepository projectRepo;
  late FakeNoteRepository noteRepo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(ProjectStatus.active);
    registerFallbackValue(TaskStatus.todo);
  });

  setUp(() {
    planRepo = _MockDailyPlanRepository();
    taskRepo = _MockTaskRepository();
    routineRepo = _MockRoutineRepository();
    projectRepo = _MockProjectRepository();
    noteRepo = FakeNoteRepository([_worstCaseNote()]);
    final plan = _worstCasePlan();
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(plan.tasks));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(_routines()));
    when(() => projectRepo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => Right(_worstCaseProjects()));
    when(() => projectRepo.getLimits())
        .thenAnswer((_) async => Right(_limits().copyWith(activeCount: 3)));
  });

  List<Override> overrides() => [
    todayProvider.overrideWith(_FixedToday.new),
    dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
    taskRepositoryProvider.overrideWith((ref) async => taskRepo),
    routineRepositoryProvider.overrideWith((ref) async => routineRepo),
    projectRepositoryProvider.overrideWith((ref) async => projectRepo),
    noteRepositoryProvider.overrideWith((ref) async => noteRepo),
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
      ProjectsCard,
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

  /// Height of one line of the text at [finder]: the same 'Ağ' TextPainter
  /// reference as expectAtMostLines in the planning overflow tests.
  double oneLineHeight(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final oneLine = TextPainter(
      text: TextSpan(text: 'Ağ', style: (paragraph.text as TextSpan).style),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    final height = oneLine.height;
    oneLine.dispose();
    return height;
  }

  /// Lines the text at [finder] really draws.
  int drawnLines(WidgetTester tester, Finder finder) =>
      (tester.getSize(finder).height / oneLineHeight(tester, finder)).round();

  group('Long task and routine titles are cut at 2 lines on Home', () {
    for (final width in _widths) {
      for (final textScale in _textScales) {
        final label = 'width ${width.toInt()}px, textScale $textScale';

        testWidgets('unbroken 255 and many-word titles, $label', (tester) async {
          final plan = _clampPlan();
          when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
          when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(plan.tasks));
          when(
            () => routineRepo.getRoutinesForDay(any()),
          ).thenAnswer((_) async => Right(_clampRoutines()));
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull, reason: label);

          for (final card in [DailyTasksCard, RoutinesCard]) {
            final what = '$label $card';
            final cardRect = tester.getRect(find.byType(card));
            Finder titleIn(String text) =>
                find.descendant(of: find.byType(card), matching: find.text(text));
            Rect rowOf(Finder title) =>
                tester.getRect(find.ancestor(of: title, matching: find.byType(ListTile)));

            final short = titleIn(_shortTitle);
            final shortLines = drawnLines(tester, short);
            expect(shortLines, inInclusiveRange(1, 2), reason: '$what short title lines');
            final shortRow = rowOf(short);
            expect(shortRow.height, greaterThanOrEqualTo(48), reason: '$what short row height');

            for (final text in [_unbrokenTitle, _manyWordsTitle]) {
              final title = titleIn(text);
              final kind = text == _unbrokenTitle ? 'unbroken' : 'many words';
              expect(drawnLines(tester, title), 2, reason: '$what $kind drawn lines');
              final paragraph = tester.renderObject<RenderParagraph>(title);
              expect(paragraph.didExceedMaxLines, isTrue, reason: '$what $kind was cut');
              expect(paragraph.overflow, TextOverflow.ellipsis, reason: '$what $kind ellipsis');

              // The row grows by at most the extra title lines (a dense
              // ListTile's minimum height may absorb part of it).
              final extra = (2 - shortLines) * oneLineHeight(tester, title);
              final row = rowOf(title);
              expect(
                row.height,
                inInclusiveRange(shortRow.height - 0.5, shortRow.height + extra + 0.5),
                reason: '$what $kind: height vs the short-title row (+$extra)',
              );
              expect(row.height, greaterThanOrEqualTo(48), reason: '$what $kind row height');
              final r = tester.getRect(title);
              expect(r.left, greaterThanOrEqualTo(cardRect.left), reason: '$what $kind left');
              expect(r.right, lessThanOrEqualTo(cardRect.right), reason: '$what $kind right');
              expect(row.right, lessThanOrEqualTo(cardRect.right), reason: '$what $kind row');
            }
          }

          // "Planlamadan ekle" keeps its full 48x48 tap target.
          final addButton = find.ancestor(
            of: find.descendant(
              of: find.byType(DailyTasksCard),
              matching: find.byTooltip('Planlamadan ekle'),
            ),
            matching: find.byType(IconButton),
          );
          expect(addButton, findsOneWidget);
          final size = tester.getSize(addButton);
          expect(size.width, greaterThanOrEqualTo(48), reason: label);
          expect(size.height, greaterThanOrEqualTo(48), reason: label);
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

  /// The whole button (incl. Material tap padding) is at least 48x48.
  void expectTapTarget(WidgetTester tester, Finder button, String label) {
    expect(button, findsOneWidget, reason: label);
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48), reason: label);
    expect(size.height, greaterThanOrEqualTo(48), reason: label);
  }

  group('Projects card states have no overflow on Home', () {
    Finder inProjects(Finder f) => find.descendant(of: find.byType(ProjectsCard), matching: f);
    Finder projectRow(int id) => inProjects(find.byKey(ValueKey('project-$id')));
    Finder inRow(int id, Finder f) => find.descendant(of: projectRow(id), matching: f);

    void expectCardFrame(WidgetTester tester, double width) {
      expectShell(width);
      expect(inProjects(find.text(ProjectsCard.title)), findsOneWidget);
      final more = find.ancestor(
        of: inProjects(find.text(ProjectsCard.moreText)),
        matching: find.byType(TextButton),
      );
      expectTapTarget(tester, more, ProjectsCard.moreText);
      final card = tester.getRect(find.byType(ProjectsCard));
      expect(card.left, greaterThanOrEqualTo(0));
      expect(card.right, lessThanOrEqualTo(width));
    }

    /// Title on its own line; the bar (or "Henüz görev yok") sits fully below it.
    void expectBelowTitle(WidgetTester tester, int id, String title, Finder below) {
      final titleRect = tester.getRect(inRow(id, find.text(title)));
      final belowRect = tester.getRect(below);
      expect(belowRect.top, greaterThanOrEqualTo(titleRect.bottom), reason: '$id');
      final rowRect = tester.getRect(projectRow(id));
      expect(belowRect.right, lessThanOrEqualTo(rowRect.right), reason: '$id');
      expect(titleRect.right, lessThanOrEqualTo(rowRect.right), reason: '$id');
    }

    LinearProgressIndicator bar(WidgetTester tester, int id) =>
        tester.widget<LinearProgressIndicator>(inRow(id, find.byType(LinearProgressIndicator)));

    for (final width in _widths) {
      for (final textScale in _textScales) {
        final label = 'width ${width.toInt()}px, textScale $textScale';

        testWidgets('filled (long titles, progress null/0/100), $label', (tester) async {
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull);
          expectCardFrame(tester, width);
          expect(inProjects(find.text(ProjectsCard.counterText(3, 3))), findsOneWidget);
          for (final (id, title) in [
            (2, _projectTitleNull),
            (1, _projectTitleZero),
            (5, _projectTitleFull),
          ]) {
            expect(inRow(id, find.text(title)), findsOneWidget, reason: title);
          }

          // progress null: "Henüz görev yok", no bar, no percent.
          final noTasks = inRow(2, find.text(ProjectsCard.noTasksText));
          expect(noTasks, findsOneWidget);
          expect(inRow(2, find.byType(LinearProgressIndicator)), findsNothing);
          expect(inRow(2, find.textContaining('%')), findsNothing);
          expectBelowTitle(tester, 2, _projectTitleNull, noTasks);

          // progress 0: empty bar and "%0".
          expect(bar(tester, 1).value, 0);
          expect(inRow(1, find.text('%0')), findsOneWidget);
          expect(inRow(1, find.text(ProjectsCard.noTasksText)), findsNothing);
          expectBelowTitle(
              tester, 1, _projectTitleZero, inRow(1, find.byKey(const ValueKey('project-progress-1'))));

          // progress 100: full bar and "%100".
          expect(bar(tester, 5).value, 1.0);
          expect(inRow(5, find.text('%100')), findsOneWidget);
          expectBelowTitle(
              tester, 5, _projectTitleFull, inRow(5, find.byKey(const ValueKey('project-progress-5'))));

          // Target date set (short Turkish day) and null.
          expect(inRow(1, find.text('20 Kas')), findsOneWidget);
          expect(inRow(5, find.text('31 Eki')), findsOneWidget);
          expect(inRow(2, find.byKey(const ValueKey('project-target-2'))), findsNothing);
        });

        testWidgets('empty, $label', (tester) async {
          when(() => projectRepo.getProjects(status: any(named: 'status')))
              .thenAnswer((_) async => const Right([]));
          when(() => projectRepo.getLimits())
              .thenAnswer((_) async => Right(_limits().copyWith(activeCount: 0)));
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull);
          expectCardFrame(tester, width);
          expect(inProjects(find.text(ProjectsCard.emptyText)), findsOneWidget);
          expect(inProjects(find.text(ProjectsCard.counterText(0, 3))), findsOneWidget);
        });

        testWidgets('loading, $label', (tester) async {
          final pending = Completer<Either<Failure, List<Project>>>();
          addTearDown(() {
            if (!pending.isCompleted) pending.complete(const Right([]));
          });
          when(() => projectRepo.getProjects(status: any(named: 'status')))
              .thenAnswer((_) => pending.future);
          await pumpApp(tester, width, textScale: textScale, settle: false);
          // Let the shell (side rail) finish animating; the request stays pending.
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          expectCardFrame(tester, width);
          expect(inProjects(find.byKey(const ValueKey('projects-skeleton'))), findsOneWidget);
          expect(inProjects(find.textContaining(RegExp(r'^Aktif \d+/\d+$'))), findsNothing); // no counter yet
        });

        testWidgets('error, $label', (tester) async {
          const failure = NetworkFailure('timeout');
          when(() => projectRepo.getProjects(status: any(named: 'status')))
              .thenAnswer((_) async => const Left(failure));
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull);
          expectCardFrame(tester, width);
          expect(inProjects(find.text(userMessage(failure))), findsOneWidget);
          final retry = find.ancestor(
            of: inProjects(find.text(ProjectsCard.retryText)),
            matching: find.byType(OutlinedButton),
          );
          expectTapTarget(tester, retry, ProjectsCard.retryText);
          // The rest of Home still works.
          expect(find.byType(RoutinesCard), findsOneWidget);
          expect(find.text(_routineTitle), findsOneWidget);
        });
      }
    }
  });

  group('Günün Notu card states have no overflow on Home', () {
    Finder inCard(Finder f) => find.descendant(of: find.byType(RandomNoteCard), matching: f);
    final title = find.byKey(const ValueKey('random-note-title'));
    final body = find.byKey(const ValueKey('random-note-body'));
    final open = find.byKey(const ValueKey('random-note-open'));
    final more = find.byKey(const ValueKey('random-note-more'));

    void expectCardFrame(WidgetTester tester, String label) {
      expect(inCard(find.text(RandomNoteCard.title)), findsOneWidget, reason: label);
      expectTapTarget(tester, find.byKey(const ValueKey('random-note-more')), '$label more');
      final card = tester.getRect(find.byType(RandomNoteCard));
      expect(card.left, greaterThanOrEqualTo(0), reason: label);
      expect(card.right, lessThanOrEqualTo(tester.view.physicalSize.width), reason: label);
    }

    for (final width in _widths) {
      for (final textScale in _textScales) {
        final label = 'width ${width.toInt()}px, textScale $textScale';

        testWidgets('filled (255 unbroken title, long body, 6 tags), $label', (tester) async {
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull, reason: label);
          expectCardFrame(tester, label);
          expect(drawnLines(tester, title), RandomNoteCard.titleMaxLines, reason: '$label title');
          expect(tester.renderObject<RenderParagraph>(title).didExceedMaxLines, isTrue);
          expect(drawnLines(tester, body), RandomNoteCard.bodyMaxLines, reason: '$label body');
          expect(tester.renderObject<RenderParagraph>(body).didExceedMaxLines, isTrue);
          expect(inCard(find.text('+3')), findsOneWidget, reason: label);
          // Content tap target: at least 48 high, inside the card, separate
          // from "Daha fazla" (not nested, rects do not intersect).
          final openRect = tester.getRect(open);
          expect(openRect.height, greaterThanOrEqualTo(48), reason: '$label content height');
          expect(find.descendant(of: open, matching: more), findsNothing, reason: label);
          expect(openRect.overlaps(tester.getRect(more)), isFalse, reason: '$label rects');
          final cardRect = tester.getRect(find.byType(RandomNoteCard));
          for (final f in [title, body]) {
            final r = tester.getRect(f);
            expect(r.left, greaterThanOrEqualTo(cardRect.left), reason: label);
            expect(r.right, lessThanOrEqualTo(cardRect.right), reason: label);
          }
        });

        testWidgets('empty, $label', (tester) async {
          noteRepo.server = [];
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull, reason: label);
          expectCardFrame(tester, label);
          expect(inCard(find.text(RandomNoteCard.emptyText)), findsOneWidget);
          expect(open, findsNothing, reason: '$label no content tap target');
          expectTapTarget(tester, find.byKey(const ValueKey('random-note-add')), '$label add');
        });

        testWidgets('loading, $label', (tester) async {
          noteRepo.ofDayGate = Completer<void>();
          addTearDown(() {
            if (!noteRepo.ofDayGate!.isCompleted) noteRepo.ofDayGate!.complete();
          });
          await pumpApp(tester, width, textScale: textScale, settle: false);
          expect(tester.takeException(), isNull, reason: label);
          // No pumpAndSettle (the request stays pending): step past the side
          // rail's open animation before measuring edges.
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(tester.takeException(), isNull, reason: label);
          expectCardFrame(tester, label);
          expect(inCard(find.byKey(const ValueKey('random-note-skeleton'))), findsOneWidget);
          expect(title, findsNothing);
          expect(open, findsNothing, reason: '$label no content tap target');
        });

        testWidgets('error, $label', (tester) async {
          const failure = NetworkFailure('timeout');
          noteRepo.ofDayFailure = failure;
          await pumpApp(tester, width, textScale: textScale);
          expect(tester.takeException(), isNull, reason: label);
          expectCardFrame(tester, label);
          expect(inCard(find.text(userMessage(failure))), findsOneWidget);
          expectTapTarget(tester, find.byKey(const ValueKey('random-note-retry')), '$label retry');
          expect(open, findsNothing, reason: '$label no content tap target');
          // The error stays in the card: the rest of Home is drawn.
          expect(find.byType(ProjectsCard), findsOneWidget);
          expect(find.byType(InboxCard), findsOneWidget);
        });
      }
    }
  });

  group('/projects page opened from Home has no overflow', () {
    for (final textScale in _textScales) {
      testWidgets('width 360px, textScale $textScale (opened from the Home card)', (tester) async {
        await pumpApp(tester, 360, textScale: textScale);
        final more = find.descendant(
          of: find.byType(ProjectsCard),
          matching: find.text(ProjectsCard.moreText),
        );
        await tester.ensureVisible(more);
        await tester.pumpAndSettle();
        await tester.tap(more);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ProjectsScreen), findsOneWidget);
        expect(find.byType(NavigationBar), findsNothing, reason: 'outside the shell');
        expect(find.text(ProjectsScreen.title), findsOneWidget);
        final text = find.byKey(const ValueKey('projects-section-active'));
        expect(text, findsOneWidget);
        final rect = tester.getRect(text);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(360));
        expectTapTarget(
          tester,
          find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(IconButton)),
          'BackArrow',
        );
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

  /// Same app as [pumpApp] (real routerProvider, real MainScaffold, dark theme,
  /// forced tr locale + delegates as in VarysApp) but the theme uses
  /// VisualDensity.compact, the desktop (macOS/Linux) default. No platform
  /// override: only the density changes.
  Future<void> pumpCompactApp(WidgetTester tester, double width, double textScale) async {
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
          builder: (context, ref, _) => MaterialApp.router(
            theme: AppTheme.darkTheme.copyWith(visualDensity: VisualDensity.compact),
            locale: const Locale('tr'),
            supportedLocales: const [Locale('tr')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            routerConfig: ref.watch(routerProvider),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Step 29 clamp fixtures: short / unbroken 255 / many-word titles in both
  /// cards; routine 1 done with streak 3.
  void useClampFixtures() {
    final plan = _clampPlan();
    when(() => planRepo.getPlan(any())).thenAnswer((_) async => Right(plan));
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(plan.tasks));
    when(
      () => routineRepo.getRoutinesForDay(any()),
    ).thenAnswer((_) async => Right(_clampRoutines()));
  }

  /// Checkbox of the row whose title is [title] inside [card].
  Finder checkboxOf(Type card, String title) => find.descendant(
    of: find.ancestor(
      of: find.descendant(of: find.byType(card), matching: find.text(title)),
      matching: find.byType(ListTile),
    ),
    matching: find.byType(Checkbox),
  );

  for (final compact in [false, true]) {
    final density = compact ? 'compact' : 'standard';

    Future<void> pumpWith(WidgetTester tester, double width, double textScale) => compact
        ? pumpCompactApp(tester, width, textScale)
        : pumpApp(tester, width, textScale: textScale);

    group('Home checkbox tap targets are 48x48 ($density density)', () {
      for (final width in _widths) {
        for (final textScale in _textScales) {
          final label = '$density, width ${width.toInt()}px, textScale $textScale';

          testWidgets('task and routine checkboxes, $label', (tester) async {
            useClampFixtures();
            await pumpWith(tester, width, textScale);
            expect(tester.takeException(), isNull, reason: label);
            expect(find.byType(HomeScreen), findsOneWidget);

            for (final card in [DailyTasksCard, RoutinesCard]) {
              final what = '$label $card';
              final cardRect = tester.getRect(find.byType(card));
              final boxes = find.descendant(of: find.byType(card), matching: find.byType(Checkbox));
              // Tasks 1-5 / routines 1-4 are all drawn with a checkbox.
              expect(boxes, findsNWidgets(card == DailyTasksCard ? 5 : 4), reason: what);
              for (final element in boxes.evaluate()) {
                final box = find.byElementPredicate((e) => e == element);
                final rect = tester.getRect(box);
                expect(rect.width, greaterThanOrEqualTo(48), reason: '$what checkbox width');
                expect(rect.height, greaterThanOrEqualTo(48), reason: '$what checkbox height');
                final row = tester.getRect(find.ancestor(of: box, matching: find.byType(ListTile)));
                expect(row.height, greaterThanOrEqualTo(48), reason: '$what row height');
                expect(rect.top, greaterThanOrEqualTo(row.top - 0.5), reason: '$what in row');
                expect(rect.bottom, lessThanOrEqualTo(row.bottom + 0.5), reason: '$what in row');
                expect(rect.left, greaterThanOrEqualTo(cardRect.left), reason: '$what in card');
                expect(rect.right, lessThanOrEqualTo(cardRect.right), reason: '$what in card');
              }

              Finder titleIn(String text) =>
                  find.descendant(of: find.byType(card), matching: find.text(text));
              expect(
                drawnLines(tester, titleIn(_shortTitle)),
                inInclusiveRange(1, 2),
                reason: '$what short title lines',
              );
              for (final text in [_unbrokenTitle, _manyWordsTitle]) {
                final title = titleIn(text);
                final kind = text == _unbrokenTitle ? 'unbroken' : 'many words';
                expect(drawnLines(tester, title), 2, reason: '$what $kind drawn lines');
                final paragraph = tester.renderObject<RenderParagraph>(title);
                expect(paragraph.didExceedMaxLines, isTrue, reason: '$what $kind was cut');
                final r = tester.getRect(title);
                expect(r.right, lessThanOrEqualTo(cardRect.right), reason: '$what $kind right');
              }
            }

            // Routine 1 (done) keeps its streak icon and count, inside the
            // card and right of its title.
            final cardRect = tester.getRect(find.byType(RoutinesCard));
            final streak = find.byKey(const ValueKey('streak-1'));
            expect(streak, findsOneWidget, reason: label);
            expect(
              find.descendant(of: streak, matching: find.byIcon(Icons.local_fire_department)),
              findsOneWidget,
              reason: label,
            );
            expect(find.descendant(of: streak, matching: find.text('3')), findsOneWidget);
            final streakRect = tester.getRect(streak);
            expect(streakRect.right, lessThanOrEqualTo(cardRect.right), reason: '$label streak');
            final titleRect = tester.getRect(
              find.descendant(of: find.byType(RoutinesCard), matching: find.text(_routineTitle)),
            );
            expect(
              titleRect.right,
              lessThanOrEqualTo(streakRect.left + 0.5),
              reason: '$label streak vs title',
            );
          });
        }
      }
    });

    group('Checkbox corner tap completes ($density density)', () {
      for (final (width, textScale) in [(360.0, 1.0), (1400.0, 1.5)]) {
        final label = '$density, width ${width.toInt()}px, textScale $textScale';

        testWidgets('task: 20px from center completes, 30px does not, $label', (tester) async {
          useClampFixtures();
          final task = _clampPlan().tasks.firstWhere((t) => t.id == 1);
          when(
            () => taskRepo.updateTaskStatus(1, TaskStatus.done),
          ).thenAnswer((_) async => Right(task.copyWith(status: TaskStatus.done)));
          await pumpWith(tester, width, textScale);
          final center = tester.getCenter(checkboxOf(DailyTasksCard, _shortTitle));

          // 30px right of center: outside the 48x48 target, no toggle.
          await tester.tapAt(center + const Offset(30, 0));
          await tester.pumpAndSettle();
          verifyNever(() => taskRepo.updateTaskStatus(any(), any()));

          // Near the corner (20px right and down): inside the target only.
          await tester.tapAt(center + const Offset(20, 20));
          await tester.pumpAndSettle();
          verify(() => taskRepo.updateTaskStatus(1, TaskStatus.done)).called(1);
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('routine: 20px from center completes, 30px does not, $label', (tester) async {
          useClampFixtures();
          when(() => routineRepo.markDone(any(), any())).thenAnswer((_) async => const Right(null));
          await pumpWith(tester, width, textScale);
          final center = tester.getCenter(checkboxOf(RoutinesCard, _shortTitle));

          await tester.tapAt(center + const Offset(30, 0));
          await tester.pumpAndSettle();
          verifyNever(() => routineRepo.markDone(any(), any()));

          await tester.tapAt(center + const Offset(20, 20));
          await tester.pumpAndSettle();
          verify(() => routineRepo.markDone(3, _day)).called(1);
          expect(tester.takeException(), isNull, reason: label);
        });
      }
    });
  }
}
