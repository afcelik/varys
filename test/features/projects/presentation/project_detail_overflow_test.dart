// Overflow matrix of the project detail page: 8 widths x text scale 1.0/1.5,
// every state (filled worst case, empty, loading, task error, completed
// project, deleted project). Each case: no exception, line limits drawn
// (project title <= 3, description <= 6, task titles <= 2, one-line labels
// 1), every tap target at least 48x48 and inside the screen. Frames are
// pumped one by one; pumpAndSettle is never used.

import 'dart:async';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/presentation/project_detail_screen.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../calendar/fake_task_server.dart';
import '../fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

/// [FakeTaskServer] with a forced list failure.
class _TaskServer extends FakeTaskServer {
  _TaskServer(super.server);

  Failure? listFailure;

  @override
  Future<Either<Failure, List<Task>>> getTasksByFilter(TaskFilter filter) async {
    final failure = listFailure;
    if (failure != null) return Left(failure);
    return super.getTasksByFilter(filter);
  }
}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _scales = [1.0, 1.5];

/// 255 characters with no space (the title limit), for project and tasks.
final _unbrokenProject = 'P' * 255;
final _unbrokenTask = 'G' * 255;

/// More than 6 lines at any width: 9 short lines plus one unbroken word.
final _longDescription = [
  for (var i = 1; i <= 9; i++) 'Satır $i: taşınma öncesi yapılacaklar',
  'Ç' * 300,
].join('\n');

Task _task(
  int id,
  String title, {
  int projectId = 1,
  TaskStatus status = TaskStatus.todo,
  DateTime? dueDate,
}) {
  final at = DateTime(2026, 11, 1).add(Duration(hours: id));
  return Task(
    id: id,
    title: title,
    status: status,
    createdAt: at,
    updatedAt: at,
    dueDate: dueDate,
    projectId: projectId,
  );
}

/// 22 pending (every third one unbroken 255, every other one with a due
/// day) and 3 done tasks for project 1.
List<Task> _manyTasks() => [
  for (var i = 1; i <= 22; i++)
    _task(
      i,
      i % 3 == 0 ? _unbrokenTask : 'Görev $i: kutuları etiketle ve odalara göre ayır',
      dueDate: i.isEven ? DateTime(2026, 12, i) : null,
    ),
  for (var i = 23; i <= 25; i++)
    _task(i, i == 23 ? _unbrokenTask : 'Bitti $i', status: TaskStatus.done),
];

Project _worstProject() => projectsFixture().first.copyWith(
  title: _unbrokenProject,
  description: _longDescription,
  startDate: DateTime(2026, 11, 1),
  targetDate: DateTime(2026, 12, 31),
  totalTasks: 25,
  doneTasks: 3,
  progressPercent: 12,
);

void main() {
  late _TaskServer tasks;
  late FakeProjectRepository projects;
  late _MockDailyPlanRepository planRepo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    tasks = _TaskServer(_manyTasks());
    projects = FakeProjectRepository([_worstProject(), ...projectsFixture().skip(1)]);
    planRepo = _MockDailyPlanRepository();
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
  });

  Future<void> frames(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Home placeholder, then the detail page pushed with [project]; frames
  /// are pumped one by one (no pumpAndSettle).
  Future<void> openDetail(WidgetTester tester, double width, double scale, Project project) async {
    tester.view.physicalSize = Size(width, width <= 400 ? 740 : 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: AppRouter.homePath,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          pageBuilder: (_, _) => const NoTransitionPage(child: Scaffold(body: Text('HOME'))),
        ),
        GoRoute(
          path: AppRouter.projectDetailPath,
          // As in the app router: no page transition, so rects are final.
          pageBuilder: (_, state) =>
              NoTransitionPage(child: ProjectDetailScreen(initial: state.extra! as Project)),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      textScale: scale,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        taskRepositoryProvider.overrideWith((ref) async => tasks),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        projectRepositoryProvider.overrideWith((ref) async => projects),
      ],
    );
    await frames(tester, 2);
    unawaited(router.push(AppRouter.projectDetailPath, extra: project));
    await frames(tester);
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  ScrollPosition listPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byType(ProjectDetailScreen), matching: find.byType(Scrollable)),
      )
      .position;

  /// Brings [f] on screen: the list builds lazily, so an item may not exist
  /// yet (below) or any more (scrolled past). From the top, scroll down in
  /// steps until it is built, then ensureVisible. One frame per step.
  Future<void> reveal(WidgetTester tester, Finder f) async {
    if (f.evaluate().isEmpty) {
      listPosition(tester).jumpTo(0);
      await tester.pump();
    }
    for (var i = 0; i < 200 && f.evaluate().isEmpty; i++) {
      final position = listPosition(tester);
      position.jumpTo((position.pixels + 300).clamp(0, position.maxScrollExtent));
      await tester.pump();
    }
    await tester.ensureVisible(f);
    await tester.pump();
  }

  int drawnLines(WidgetTester tester, Finder finder) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final oneLine = TextPainter(
      text: TextSpan(text: 'Ağ', style: (paragraph.text as TextSpan).style),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    final lines = (paragraph.size.height / oneLine.height).round();
    oneLine.dispose();
    return lines;
  }

  void expectTarget(WidgetTester tester, Finder f, double width, String label) {
    expect(f, findsOneWidget, reason: label);
    final r = tester.getRect(f);
    expect(r.width, greaterThanOrEqualTo(48), reason: '$label width');
    expect(r.height, greaterThanOrEqualTo(48), reason: '$label height');
    expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$label left');
    expect(r.right, lessThanOrEqualTo(width + 0.5), reason: '$label right');
  }

  void expectInside(WidgetTester tester, Finder f, double width, String label) {
    final r = tester.getRect(f);
    expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$label left');
    expect(r.right, lessThanOrEqualTo(width + 0.5), reason: '$label right');
  }

  /// BackArrow, and (unless [gone]) Düzenle and Görev ekle: 48x48 on screen.
  void expectAppBar(WidgetTester tester, double width, String label, {bool gone = false}) {
    expect(tester.takeException(), isNull, reason: label);
    expectTarget(tester, find.widgetWithIcon(IconButton, Icons.arrow_back), width, '$label back');
    if (gone) {
      expect(key('project-detail-edit'), findsNothing, reason: label);
      expect(key('project-detail-add-task'), findsNothing, reason: label);
    } else {
      expectTarget(tester, key('project-detail-edit'), width, '$label Düzenle');
      expectTarget(tester, key('project-detail-add-task'), width, '$label Görev ekle');
    }
  }

  /// Header lines: title <= 3 ([titleLines] exactly when given), status 1.
  void expectHeader(WidgetTester tester, String label, {int? titleLines}) {
    final title = key('project-detail-title');
    expect(tester.widget<Text>(title).maxLines, 3, reason: label);
    final lines = drawnLines(tester, title);
    expect(lines, lessThanOrEqualTo(3), reason: '$label title');
    if (titleLines != null) expect(lines, titleLines, reason: '$label title');
    expect(drawnLines(tester, key('project-detail-status')), 1, reason: '$label status');
  }

  /// Every drawn task row: title <= 2 lines (2 for an unbroken title), due
  /// day 1 line, checkbox and row at least 48, all inside the screen.
  Future<void> expectTaskRows(
    WidgetTester tester,
    List<Task> expected,
    double width,
    String label,
  ) async {
    for (final task in expected) {
      final row = key('project-task-${task.id}');
      await reveal(tester, row);
      expect(tester.takeException(), isNull, reason: '$label row ${task.id}');
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48), reason: '$label row');
      expectInside(tester, row, width, '$label row ${task.id}');
      expectTarget(tester, key('project-task-check-${task.id}'), width, '$label check');
      final title = key('project-task-title-${task.id}');
      expect(tester.widget<Text>(title).maxLines, 2, reason: label);
      final lines = drawnLines(tester, title);
      expect(lines, lessThanOrEqualTo(2), reason: '$label task ${task.id}');
      if (task.title == _unbrokenTask) expect(lines, 2, reason: '$label task ${task.id} cut');
      if (task.dueDate != null) {
        final due = key('project-task-due-${task.id}');
        expect(drawnLines(tester, due), 1, reason: '$label due ${task.id}');
        expectInside(tester, due, width, '$label due ${task.id}');
      }
    }
  }

  for (final width in _widths) {
    for (final scale in _scales) {
      final label = '${width.toInt()}px x$scale';

      group('project detail $label', () {
        testWidgets('filled: unbroken 255 titles, 10-line description, 22 pending + 3 done', (
          tester,
        ) async {
          await openDetail(tester, width, scale, _worstProject());
          expectAppBar(tester, width, label);
          expectHeader(tester, label, titleLines: 3);
          expectInside(tester, key('project-detail-title'), width, '$label title');

          // Description: 6 lines collapsed, all lines open, back to 6.
          final description = key('project-detail-description');
          final toggle = key('project-detail-description-toggle');
          expect(drawnLines(tester, description), 6, reason: '$label description');
          expectTarget(tester, toggle, width, '$label Tümünü göster');
          await tester.tap(toggle);
          await frames(tester, 2);
          expect(tester.takeException(), isNull, reason: '$label description open');
          expect(drawnLines(tester, description), greaterThan(6), reason: label);
          await reveal(tester, toggle);
          await tester.tap(toggle);
          await frames(tester, 2);
          await reveal(tester, description);
          expect(drawnLines(tester, description), 6, reason: '$label description closed');

          for (final k in ['start', 'target', 'count']) {
            await reveal(tester, key('project-detail-$k'));
            expect(drawnLines(tester, key('project-detail-$k')), 1, reason: '$label $k');
            expectInside(tester, key('project-detail-$k'), width, '$label $k');
          }
          expect(tester.widget<Text>(key('project-detail-percent')).data, '%12');

          final pending = _manyTasks().where((t) => t.status != TaskStatus.done).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          await expectTaskRows(tester, pending, width, label);

          final doneToggle = key('project-detail-done-toggle');
          await reveal(tester, doneToggle);
          expectTarget(tester, doneToggle, width, '$label Tamamlananlar');
          expect(drawnLines(tester, key('project-detail-done-title')), 1, reason: label);
          await tester.tap(doneToggle);
          await frames(tester, 2);
          final done = _manyTasks().where((t) => t.status == TaskStatus.done).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          await expectTaskRows(tester, done, width, '$label done');
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('empty: no tasks, no description, no dates', (tester) async {
          final project = projectsFixture()[2]; // 3 "Bahçe düzenlemesi", on hold
          await openDetail(tester, width, scale, project);
          expectAppBar(tester, width, label);
          expectHeader(tester, label);
          final empty = key('project-detail-tasks-empty');
          expect(empty, findsOneWidget);
          expectInside(tester, empty, width, '$label empty');
          expect(drawnLines(tester, key('project-detail-no-tasks')), 1, reason: label);
          expect(key('project-detail-done-toggle'), findsNothing);
          expect(key('project-detail-description-toggle'), findsNothing);
        });

        testWidgets('loading: spinner in the task section only (frame by frame)', (tester) async {
          tasks.listGate = Completer<void>();
          await openDetail(tester, width, scale, _worstProject());
          expectAppBar(tester, width, label);
          expectHeader(tester, label, titleLines: 3);
          final spinner = key('project-detail-tasks-loading');
          await reveal(tester, spinner);
          expect(spinner, findsOneWidget);
          expectInside(tester, spinner, width, '$label spinner');
          expect(tester.takeException(), isNull, reason: label);

          tasks.listGate!.complete();
          await frames(tester);
          expect(spinner, findsNothing);
          expect(tester.takeException(), isNull, reason: label);
        });

        testWidgets('task error: message and Tekrar dene (48x48); header unaffected', (
          tester,
        ) async {
          const failure = NetworkFailure('timeout');
          tasks.listFailure = failure;
          await openDetail(tester, width, scale, _worstProject());
          expectAppBar(tester, width, label);
          expectHeader(tester, label, titleLines: 3);
          final retry = key('project-detail-tasks-retry');
          await reveal(tester, retry);
          expectTarget(tester, retry, width, '$label retry');
          final message = find.descendant(
            of: key('project-detail-tasks-error'),
            matching: find.text(userMessage(failure)),
          );
          expect(message, findsOneWidget);
          expectInside(tester, message, width, '$label message');
        });

        testWidgets('completed project: "Tamamlanan", %100, every task done', (tester) async {
          final project = _worstProject().copyWith(
            status: ProjectStatus.completed,
            totalTasks: 25,
            doneTasks: 25,
            progressPercent: 100,
          );
          projects.server = [project, ...projectsFixture().skip(1)];
          tasks.server = [for (final t in _manyTasks()) t.copyWith(status: TaskStatus.done)];
          await openDetail(tester, width, scale, project);
          expectAppBar(tester, width, label);
          expectHeader(tester, label, titleLines: 3);
          expect(tester.widget<Text>(key('project-detail-status')).data, 'Tamamlanan');
          expect(tester.widget<Text>(key('project-detail-percent')).data, '%100');
          expect(key('project-detail-tasks-empty'), findsOneWidget);

          final doneToggle = key('project-detail-done-toggle');
          await reveal(tester, doneToggle);
          expectTarget(tester, doneToggle, width, '$label Tamamlananlar');
          expect(tester.widget<Text>(key('project-detail-done-title')).data, 'Tamamlananlar (25)');
          await tester.tap(doneToggle);
          await frames(tester, 2);
          final all = [for (final t in _manyTasks()) t.copyWith(status: TaskStatus.done)]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          await expectTaskRows(tester, all, width, '$label done');
        });

        testWidgets('deleted project: message and Geri dön (48x48); no Düzenle / Görev ekle', (
          tester,
        ) async {
          await openDetail(tester, width, scale, _worstProject().copyWith(id: 999));
          expectAppBar(tester, width, label, gone: true);
          final gone = key('project-detail-gone');
          expect(gone, findsOneWidget);
          expectInside(tester, gone, width, '$label gone');
          expectTarget(tester, key('project-detail-back'), width, '$label Geri dön');
          expect(key('project-detail-title'), findsNothing);
        });
      });
    }
  }
}
