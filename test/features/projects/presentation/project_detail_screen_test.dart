// ProjectDetailScreen widget tests: real notifiers (projects list, task list,
// eisenhowerTasksProvider), in-memory servers behind the repositories
// returning real Either values. Projects from real backend JSON
// (test/fixtures/projects_list.json): 1 "Ev taşıma" active, 1/4 done (25%),
// 2026-11-01 -> 2026-11-20; 2 "Kitap okuma listesi" active, no tasks (null).

import 'dart:async';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/planning/presentation/task_new_args.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/presentation/project_detail_screen.dart';
import 'package:varys/features/projects/presentation/project_edit_screen.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../calendar/fake_task_server.dart';
import '../fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

/// [FakeTaskServer] with forced failures for the list and the status change.
class _TaskServer extends FakeTaskServer {
  _TaskServer(super.server);

  Failure? listFailure;
  Failure? statusFailure;

  @override
  Future<Either<Failure, List<Task>>> getTasksByFilter(TaskFilter filter) async {
    final failure = listFailure;
    if (failure != null) {
      listCalls++;
      return Left(failure);
    }
    return super.getTasksByFilter(filter);
  }

  @override
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status) async {
    final failure = statusFailure;
    if (failure != null) return Left(failure);
    return super.updateTaskStatus(id, status);
  }
}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

Task _task(
  int id,
  String title, {
  int? projectId = 1,
  TaskStatus status = TaskStatus.todo,
  required DateTime createdAt,
  DateTime? dueDate,
  DateTime? deletedAt,
}) => Task(
  id: id,
  title: title,
  status: status,
  createdAt: createdAt,
  updatedAt: createdAt,
  dueDate: dueDate,
  deletedAt: deletedAt,
  projectId: projectId,
);

/// Project 1: 11 (todo, due 21 Kas), 12 (in progress, newest), 13 (done).
/// Not shown: 14 (project 2), 15 (project 1, deleted), 16 (Projesiz).
List<Task> _tasks() => [
  _task(11, 'Kutuları al', createdAt: DateTime(2026, 11, 3), dueDate: DateTime(2026, 11, 21)),
  _task(12, 'Nakliyeci ara', status: TaskStatus.inProgress, createdAt: DateTime(2026, 11, 5)),
  _task(13, 'Adres değişikliği', status: TaskStatus.done, createdAt: DateTime(2026, 11, 2)),
  _task(14, 'Başka projenin işi', projectId: 2, createdAt: DateTime(2026, 11, 6)),
  _task(15, 'Silinmiş iş', createdAt: DateTime(2026, 11, 7), deletedAt: DateTime(2026, 11, 8)),
  _task(16, 'Projesiz iş', projectId: null, createdAt: DateTime(2026, 11, 9)),
];

void main() {
  late _TaskServer tasks;
  late FakeProjectRepository projects;
  late _MockDailyPlanRepository planRepo;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    tasks = _TaskServer(_tasks());
    projects = FakeProjectRepository();
    planRepo = _MockDailyPlanRepository();
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
  });

  Project byId(int id) => projectsFixture().firstWhere((p) => p.id == id);

  /// Home placeholder, then the detail page pushed with [project] as extra.
  Future<void> openDetail(
    WidgetTester tester,
    Project project, {
    bool settle = true,
    Size size = const Size(600, 1600),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.homePath,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: AppRouter.projectDetailPath,
          builder: (_, state) => ProjectDetailScreen(initial: state.extra! as Project),
        ),
        GoRoute(
          path: AppRouter.projectsEditPath,
          builder: (_, state) => ProjectEditScreen(project: state.extra! as Project),
        ),
        GoRoute(
          path: AppRouter.tasksNewPath,
          builder: (_, state) =>
              TaskEditScreen(initialProjectId: (state.extra as TaskNewArgs?)?.projectId),
        ),
        GoRoute(
          path: AppRouter.tasksEditPath,
          builder: (_, state) => TaskEditScreen(task: state.extra! as Task),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        taskRepositoryProvider.overrideWith((ref) async => tasks),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        projectRepositoryProvider.overrideWith((ref) async => projects),
      ],
    );
    await tester.pumpAndSettle();
    router.push(AppRouter.projectDetailPath, extra: project);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
  }

  Finder key(String k) => find.byKey(ValueKey(k));
  Finder taskRow(int id) => key('project-task-$id');
  String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

  /// Task ids of the drawn rows, top to bottom.
  List<int> shownTaskIds(WidgetTester tester) {
    final rows = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          RegExp(r'^project-task-\d+$').hasMatch((w.key! as ValueKey<String>).value),
    );
    final found = rows.evaluate().toList()
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a.widget))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
      );
    return [
      for (final e in found) int.parse((e.widget.key! as ValueKey<String>).value.split('-').last),
    ];
  }

  void expectTapTarget(WidgetTester tester, Finder f, String what) {
    expect(f, findsOneWidget, reason: what);
    final size = tester.getSize(f);
    expect(size.width, greaterThanOrEqualTo(48), reason: '$what width');
    expect(size.height, greaterThanOrEqualTo(48), reason: '$what height');
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

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(ProjectDetailScreen)));

  group('header', () {
    testWidgets('filled: title, status, description, dates, bar at 25% with "%25" and '
        '"1/4 görev"', (tester) async {
      await openDetail(tester, byId(1));

      expect(text(tester, 'project-detail-title'), 'Ev taşıma');
      expect(text(tester, 'project-detail-status'), 'Aktif');
      expect(text(tester, 'project-detail-description'), 'Yeni eve geçiş işleri');
      expect(text(tester, 'project-detail-start'), 'Başlangıç: 1 Kas');
      expect(text(tester, 'project-detail-target'), 'Hedef: 20 Kas');
      expect(tester.widget<LinearProgressIndicator>(key('project-detail-progress')).value, 0.25);
      expect(text(tester, 'project-detail-percent'), '%25');
      expect(text(tester, 'project-detail-count'), '1/4 görev');
      expect(key('project-detail-no-tasks'), findsNothing);
      expect(key('project-detail-description-toggle'), findsNothing, reason: 'short text');
      expect(find.text(ProjectDetailScreen.title), findsOneWidget);
    });

    testWidgets('progress null: "Henüz görev yok", no bar, no percent, no count; no dates', (
      tester,
    ) async {
      await openDetail(tester, byId(2));
      expect(text(tester, 'project-detail-no-tasks'), 'Henüz görev yok');
      expect(key('project-detail-progress'), findsNothing);
      expect(key('project-detail-percent'), findsNothing);
      expect(key('project-detail-count'), findsNothing);
      expect(key('project-detail-start'), findsNothing);
      expect(key('project-detail-target'), findsNothing);
      expect(key('project-detail-description'), findsNothing);
    });

    testWidgets('progress 0 is a percent (not "Henüz görev yok"): empty bar, "%0", "0/3 görev"', (
      tester,
    ) async {
      projects.server = [
        for (final p in projects.server)
          p.id == 2 ? p.copyWith(totalTasks: 3, doneTasks: 0, progressPercent: 0) : p,
      ];
      await openDetail(tester, byId(2));
      expect(key('project-detail-no-tasks'), findsNothing);
      expect(tester.widget<LinearProgressIndicator>(key('project-detail-progress')).value, 0);
      expect(text(tester, 'project-detail-percent'), '%0');
      expect(text(tester, 'project-detail-count'), '0/3 görev');
    });

    testWidgets('extra is only the start: stale extra shown while the list loads, then the '
        'current project from the list', (tester) async {
      projects.listGate = Completer<void>();
      await openDetail(tester, byId(1).copyWith(title: 'Eski başlık'), settle: false);
      expect(text(tester, 'project-detail-title'), 'Eski başlık');
      expect(key('project-detail-gone'), findsNothing, reason: 'not gone while loading');

      projects.listGate!.complete();
      await tester.pumpAndSettle();
      expect(text(tester, 'project-detail-title'), 'Ev taşıma');
    });

    testWidgets('long titles (255 chars, no spaces): project title at most 3 lines, task title '
        'at most 2 lines, both with an ellipsis', (tester) async {
      final longProject = 'P' * 255;
      final longTask = 'G' * 255;
      projects.server = [
        for (final p in projects.server) p.id == 1 ? p.copyWith(title: longProject) : p,
      ];
      tasks.server = [for (final t in tasks.server) t.id == 11 ? t.copyWith(title: longTask) : t];
      await openDetail(tester, byId(1), size: const Size(360, 1600));

      final title = key('project-detail-title');
      expect(tester.widget<Text>(title).data, longProject);
      expect(drawnLines(tester, title), 3);
      expect(tester.widget<Text>(title).overflow, TextOverflow.ellipsis);
      final taskTitle = key('project-task-title-11');
      expect(drawnLines(tester, taskTitle), 2);
      expect(tester.widget<Text>(taskTitle).overflow, TextOverflow.ellipsis);
    });

    testWidgets('long description: 6 lines + "Tümünü göster"; opens fully, "Daralt" closes', (
      tester,
    ) async {
      final long = List.generate(12, (i) => 'Satır ${i + 1}: taşınma notu').join('\n');
      projects.server = [
        for (final p in projects.server) p.id == 1 ? p.copyWith(description: long) : p,
      ];
      await openDetail(tester, byId(1));
      final description = key('project-detail-description');
      final toggle = key('project-detail-description-toggle');

      expect(drawnLines(tester, description), 6);
      expect(find.descendant(of: toggle, matching: find.text('Tümünü göster')), findsOneWidget);
      expectTapTarget(tester, toggle, 'description toggle');

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(drawnLines(tester, description), 12);
      expect(find.descendant(of: toggle, matching: find.text('Daralt')), findsOneWidget);

      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(drawnLines(tester, description), 6);
      expect(find.descendant(of: toggle, matching: find.text('Tümünü göster')), findsOneWidget);
    });
  });

  group('tasks', () {
    testWidgets('only this project\'s non-deleted tasks; pending newest first; due day shown; '
        'done hidden by default with its count', (tester) async {
      await openDetail(tester, byId(1));

      expect(shownTaskIds(tester), [12, 11]);
      for (final id in [13, 14, 15, 16]) {
        expect(taskRow(id), findsNothing, reason: 'task $id');
      }
      expect(text(tester, 'project-task-due-11'), '21 Kas');
      expect(key('project-task-due-12'), findsNothing);
      expect(text(tester, 'project-detail-done-title'), 'Tamamlananlar (1)');
      expect(find.text('Adres değişikliği'), findsNothing, reason: 'closed by default');
    });

    testWidgets('"Tamamlananlar" opens and closes; done task is checked and struck through', (
      tester,
    ) async {
      await openDetail(tester, byId(1));
      final toggle = key('project-detail-done-toggle');
      expectTapTarget(tester, toggle, 'done toggle');

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(shownTaskIds(tester), [12, 11, 13]);
      expect(tester.widget<Checkbox>(key('project-task-check-13')).value, isTrue);
      expect(
        tester.widget<Text>(key('project-task-title-13')).style?.decoration,
        TextDecoration.lineThrough,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(shownTaskIds(tester), [12, 11]);
    });

    testWidgets('empty: "Bu projede bekleyen görev yok", no "Tamamlananlar"', (tester) async {
      await openDetail(tester, byId(3));
      expect(
        find.descendant(
          of: key('project-detail-tasks-empty'),
          matching: find.text('Bu projede bekleyen görev yok'),
        ),
        findsOneWidget,
      );
      expect(key('project-detail-done-toggle'), findsNothing);
      expect(shownTaskIds(tester), isEmpty);
    });

    testWidgets('only done tasks: empty pending text and "Tamamlananlar (1)"', (tester) async {
      tasks.server = [
        _task(21, 'Bitti', projectId: 2, status: TaskStatus.done, createdAt: DateTime(2026, 11)),
      ];
      await openDetail(tester, byId(2));
      expect(key('project-detail-tasks-empty'), findsOneWidget);
      expect(text(tester, 'project-detail-done-title'), 'Tamamlananlar (1)');
    });

    testWidgets('loading: spinner only in the task section; the header is shown', (tester) async {
      tasks.listGate = Completer<void>();
      await openDetail(tester, byId(1), settle: false);
      expect(key('project-detail-tasks-loading'), findsOneWidget);
      expect(text(tester, 'project-detail-title'), 'Ev taşıma');
      expect(text(tester, 'project-detail-percent'), '%25');
      expect(shownTaskIds(tester), isEmpty);

      tasks.listGate!.complete();
      await tester.pumpAndSettle();
      expect(key('project-detail-tasks-loading'), findsNothing);
      expect(shownTaskIds(tester), [12, 11]);
    });

    testWidgets('task error stays in the section: userMessage + "Tekrar dene" (48x48); header, '
        'Düzenle and Görev ekle unaffected; retry loads the tasks', (tester) async {
      tasks.listFailure = _serverError;
      await openDetail(tester, byId(1));

      final error = key('project-detail-tasks-error');
      expect(find.descendant(of: error, matching: find.text(_serverError.message)), findsOneWidget);
      expect(text(tester, 'project-detail-title'), 'Ev taşıma');
      expect(text(tester, 'project-detail-percent'), '%25');
      expect(key('project-detail-edit'), findsOneWidget);
      expect(key('project-detail-add-task'), findsOneWidget);
      expect(key('project-detail-gone'), findsNothing);
      final retry = key('project-detail-tasks-retry');
      expectTapTarget(tester, retry, 'retry');

      tasks.listFailure = null;
      final before = tasks.listCalls;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(tasks.listCalls, greaterThan(before));
      expect(error, findsNothing);
      expect(shownTaskIds(tester), [12, 11]);
    });

    testWidgets('checkbox (48x48) completes the task: status sent, row moves to '
        '"Tamamlananlar", projects reloaded', (tester) async {
      await openDetail(tester, byId(1));
      final check = key('project-task-check-11');
      expectTapTarget(tester, check, 'checkbox');
      final projectLoads = projects.listCalls;

      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(tasks.updateCalls, [11]);
      expect(tasks.server.firstWhere((t) => t.id == 11).status, TaskStatus.done);
      expect(shownTaskIds(tester), [12]);
      expect(text(tester, 'project-detail-done-title'), 'Tamamlananlar (2)');
      expect(projects.listCalls, greaterThan(projectLoads), reason: 'progress re-read');
      expect(find.byType(TaskEditScreen), findsNothing, reason: 'checkbox does not open edit');
    });

    testWidgets('a done task can be reopened from "Tamamlananlar"', (tester) async {
      await openDetail(tester, byId(1));
      await tester.tap(key('project-detail-done-toggle'));
      await tester.pumpAndSettle();
      await tester.tap(key('project-task-check-13'));
      await tester.pumpAndSettle();
      expect(tasks.server.firstWhere((t) => t.id == 13).status, TaskStatus.todo);
      expect(shownTaskIds(tester), [12, 11, 13], reason: '13 is pending now (oldest)');
      expect(key('project-detail-done-toggle'), findsNothing);
    });

    testWidgets('failed toggle: userMessage snackbar, the task stays pending', (tester) async {
      tasks.statusFailure = _serverError;
      await openDetail(tester, byId(1));
      await tester.tap(key('project-task-check-11'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.text(_serverError.message)),
        findsOneWidget,
      );
      expect(shownTaskIds(tester), [12, 11]);
      expect(tester.widget<Checkbox>(key('project-task-check-11')).value, isFalse);
    });

    testWidgets('tapping a row (at least 48 high) opens the edit form for that task', (
      tester,
    ) async {
      await openDetail(tester, byId(1));
      expect(tester.getSize(taskRow(11)).height, greaterThanOrEqualTo(48));
      await tester.tap(key('project-task-title-11'));
      await tester.pumpAndSettle();
      final form = tester.widget<TaskEditScreen>(find.byType(TaskEditScreen));
      expect(form.task!.id, 11);
      expect(find.text(TaskEditScreen.editTitle), findsOneWidget);
    });
  });

  group('app bar', () {
    testWidgets('BackArrow, Düzenle and Görev ekle are 48x48 targets', (tester) async {
      await openDetail(tester, byId(1));
      expectTapTarget(tester, find.widgetWithIcon(IconButton, Icons.arrow_back), 'back');
      expectTapTarget(tester, key('project-detail-edit'), 'Düzenle');
      expectTapTarget(tester, key('project-detail-add-task'), 'Görev ekle');
      expect(tester.widget<IconButton>(key('project-detail-edit')).tooltip, 'Düzenle');
      expect(tester.widget<IconButton>(key('project-detail-add-task')).tooltip, 'Görev ekle');
    });

    testWidgets('Düzenle opens the edit form with the current project (not the stale extra)', (
      tester,
    ) async {
      await openDetail(tester, byId(1).copyWith(title: 'Eski başlık'));
      await tester.tap(key('project-detail-edit'));
      await tester.pumpAndSettle();
      final form = tester.widget<ProjectEditScreen>(find.byType(ProjectEditScreen));
      expect(form.project!.id, 1);
      expect(form.project!.title, 'Ev taşıma');
    });

    testWidgets('a saved title change in Düzenle shows on the detail page', (tester) async {
      await openDetail(tester, byId(1));
      await tester.tap(key('project-detail-edit'));
      await tester.pumpAndSettle();
      await tester.enterText(key('project-title'), 'Yeni ev');
      await tester.pump();
      await tester.ensureVisible(key('project-save'));
      await tester.tap(key('project-save'));
      await tester.pumpAndSettle();
      expect(find.byType(ProjectEditScreen), findsNothing);
      expect(text(tester, 'project-detail-title'), 'Yeni ev');
    });

    testWidgets('Görev ekle opens the form with this project chosen; after Kaydet the task is '
        'on the detail page', (tester) async {
      await openDetail(tester, byId(1));
      await tester.tap(key('project-detail-add-task'));
      await tester.pumpAndSettle();

      final form = tester.widget<TaskEditScreen>(find.byType(TaskEditScreen));
      expect(form.task, isNull);
      expect(form.initialProjectId, 1);
      final menu = tester.widget<DropdownMenu<ProjectChoice>>(
        find.byType(DropdownMenu<ProjectChoice>),
      );
      expect(menu.initialSelection?.id, 1);

      await tester.enterText(find.byKey(const ValueKey('task-title')), 'Perde as');
      await tester.pump();
      await tester.ensureVisible(find.byKey(const ValueKey('task-save')));
      await tester.tap(find.byKey(const ValueKey('task-save')));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsNothing);
      final created = tasks.server.firstWhere((t) => t.title == 'Perde as');
      expect(created.projectId, 1);
      expect(shownTaskIds(tester).first, created.id, reason: 'newest on top');
      expect(find.text('Perde as'), findsOneWidget);
    });
  });

  group('deleted project', () {
    testWidgets('not in the loaded list: "Bu proje artık yok", no Düzenle / Görev ekle, no '
        'tasks; "Geri dön" (48x48) goes back', (tester) async {
      await openDetail(tester, byId(1).copyWith(id: 999));
      expect(text(tester, 'project-detail-gone'), 'Bu proje artık yok');
      expect(key('project-detail-edit'), findsNothing);
      expect(key('project-detail-add-task'), findsNothing);
      expect(key('project-detail-title'), findsNothing);
      expect(shownTaskIds(tester), isEmpty);
      final back = key('project-detail-back');
      expectTapTarget(tester, back, 'Geri dön');

      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byType(ProjectDetailScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('deleted while open: the page switches to "Bu proje artık yok"', (tester) async {
      await openDetail(tester, byId(1));
      expect(key('project-detail-edit'), findsOneWidget);

      projects.server = projects.server.where((p) => p.id != 1).toList();
      container(tester).invalidate(projectsListProvider);
      await tester.pumpAndSettle();
      expect(key('project-detail-gone'), findsOneWidget);
      expect(key('project-detail-edit'), findsNothing);
      expect(key('project-detail-add-task'), findsNothing);
      expectTapTarget(tester, key('project-detail-back'), 'Geri dön');
    });

    testWidgets('project list failed: the extra is shown (not "gone"), tasks still listed', (
      tester,
    ) async {
      projects.listFailure = _serverError;
      await openDetail(tester, byId(1));
      expect(text(tester, 'project-detail-title'), 'Ev taşıma');
      expect(key('project-detail-gone'), findsNothing);
      expect(key('project-detail-edit'), findsOneWidget);
      expect(shownTaskIds(tester), [12, 11]);
    });
  });
}
