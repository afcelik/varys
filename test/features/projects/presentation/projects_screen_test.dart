import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/presentation/project_edit_screen.dart';
import 'package:varys/features/projects/presentation/projects_screen.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_project_repository.dart';

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

void main() {
  late FakeProjectRepository repo;
  late GoRouter router;

  setUpAll(() async => initializeDateFormatting('tr_TR', null));

  setUp(() => repo = FakeProjectRepository());

  Future<void> pumpList(WidgetTester tester, {bool settle = true}) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.homePath,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.projectsPath, builder: (_, _) => const ProjectsScreen()),
        GoRoute(path: AppRouter.projectsNewPath, builder: (_, _) => const ProjectEditScreen()),
        GoRoute(
          path: AppRouter.projectsEditPath,
          builder: (_, state) => ProjectEditScreen(project: state.extra! as Project),
        ),
        GoRoute(
          path: AppRouter.projectDetailPath,
          builder: (_, state) => Scaffold(body: Text('DETAIL ${(state.extra! as Project).id}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: [projectRepositoryProvider.overrideWith((ref) async => repo)],
    );
    await tester.pumpAndSettle();
    router.push(AppRouter.projectsPath);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  Finder section(ProjectStatus s) => find.byKey(ValueKey('projects-section-${s.apiValue}'));
  Finder row(int id) => find.byKey(ValueKey('project-row-$id'));
  Finder menu(int id) => find.byKey(ValueKey('project-menu-$id'));
  Finder inRow(int id, Finder f) => find.descendant(of: row(id), matching: f);
  String counter(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('projects-active-counter'))).data!;

  Future<void> openMenu(WidgetTester tester, int id) async {
    await tester.ensureVisible(menu(id));
    await tester.pumpAndSettle();
    await tester.tap(menu(id));
    await tester.pumpAndSettle();
  }

  PopupMenuItem<ProjectRowAction> menuItem(WidgetTester tester, String key) =>
      tester.widget<PopupMenuItem<ProjectRowAction>>(find.byKey(ValueKey('project-action-$key')));

  void expectTapTarget(WidgetTester tester, Finder f, String what) {
    final size = tester.getSize(f);
    expect(size.width, greaterThanOrEqualTo(48), reason: '$what width');
    expect(size.height, greaterThanOrEqualTo(48), reason: '$what height');
  }

  group('sections', () {
    testWidgets('projects in all 4 statuses: 4 section headers in fixed order', (tester) async {
      await pumpList(tester);

      final labels = ['Aktif', 'Beklemede', 'İleride', 'Tamamlanan'];
      final statuses = ProjectStatus.values;
      for (var i = 0; i < 4; i++) {
        expect(section(statuses[i]), findsOneWidget);
        expect(
          find.descendant(of: section(statuses[i]), matching: find.text(labels[i])),
          findsOneWidget,
        );
      }
      final ys = [for (final s in statuses) tester.getTopLeft(section(s)).dy];
      expect(ys, [...ys]..sort(), reason: 'Aktif, Beklemede, İleride, Tamamlanan');
      // Rows sit under their own section.
      expect(tester.getTopLeft(row(3)).dy, greaterThan(ys[1]));
      expect(tester.getTopLeft(row(3)).dy, lessThan(ys[2]));
      expect(tester.getTopLeft(row(5)).dy, greaterThan(ys[3]));
    });

    testWidgets('only active projects: exactly one section header; empty ones hidden', (
      tester,
    ) async {
      repo.server = repo.server.where((p) => p.status == ProjectStatus.active).toList();
      await pumpList(tester);

      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('projects-section-'),
        ),
        findsOneWidget,
      );
      expect(section(ProjectStatus.active), findsOneWidget);
      for (final s in [ProjectStatus.onHold, ProjectStatus.someday, ProjectStatus.completed]) {
        expect(section(s), findsNothing);
      }
      expect(find.text('Beklemede'), findsNothing);
      expect(find.text('Tamamlanan'), findsNothing);
      expect(row(1), findsOneWidget);
      expect(row(2), findsOneWidget);
    });

    testWidgets('app bar counter "Aktif N/M" comes from the limits', (tester) async {
      await pumpList(tester);
      expect(counter(tester), 'Aktif 2/3');
    });
  });

  group('row content', () {
    testWidgets('progress: percent with a bar; null -> "Henüz görev yok"; 0 is a percent, '
        'not "no tasks"', (tester) async {
      repo.server = [
        ...repo.server,
        repo.server[1].copyWith(
          id: 9,
          title: 'Sıfır',
          totalTasks: 3,
          doneTasks: 0,
          progressPercent: 0,
        ),
      ];
      await pumpList(tester);

      // 25%
      final bar1 = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('project-progress-1')),
      );
      expect(bar1.value, 0.25);
      expect(inRow(1, find.text('%25')), findsOneWidget);
      expect(inRow(1, find.text(ProjectsScreen.noTasksText)), findsNothing);
      // null: no tasks text, no bar
      expect(inRow(2, find.text(ProjectsScreen.noTasksText)), findsOneWidget);
      expect(find.byKey(const ValueKey('project-progress-2')), findsNothing);
      // 0: a bar at 0 and "%0"
      final bar9 = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('project-progress-9')),
      );
      expect(bar9.value, 0);
      expect(inRow(9, find.text('%0')), findsOneWidget);
      expect(inRow(9, find.text(ProjectsScreen.noTasksText)), findsNothing);
      // 100%
      expect(inRow(5, find.text('%100')), findsOneWidget);
    });

    testWidgets('target date as a Turkish short day; absent -> no line', (tester) async {
      await pumpList(tester);
      expect(inRow(1, find.text('Hedef: 20 Kas')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-target-2')), findsNothing);
    });

    testWidgets('long title: at most 2 lines with ellipsis', (tester) async {
      repo.server = [repo.server.first.copyWith(title: 'Çok uzun proje adı ' * 30)];
      await pumpList(tester);
      final title = tester.widget<Text>(find.byKey(const ValueKey('project-title-1')));
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap targets: add button and every row menu at least 48x48', (tester) async {
      await pumpList(tester);
      expectTapTarget(tester, find.byKey(const ValueKey('projects-add')), 'add');
      for (final id in [1, 2, 3, 4, 5]) {
        await tester.ensureVisible(menu(id));
        expectTapTarget(tester, menu(id), 'menu $id');
        expect(tester.getSize(row(id)).height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('tapping a row opens the detail page for that project (not the edit form)', (
      tester,
    ) async {
      await pumpList(tester);
      await tester.tap(find.byKey(const ValueKey('project-title-3')));
      await tester.pumpAndSettle();
      expect(find.text('DETAIL 3'), findsOneWidget);
      expect(find.byType(ProjectEditScreen), findsNothing);
    });

    testWidgets('menu "Düzenle" opens the edit form for that project', (tester) async {
      await pumpList(tester);
      await openMenu(tester, 3);
      await tester.tap(find.byKey(const ValueKey('project-action-edit')));
      await tester.pumpAndSettle();
      final form = tester.widget<ProjectEditScreen>(find.byType(ProjectEditScreen));
      expect(form.project!.id, 3);
      expect(find.text(ProjectEditScreen.editTitle), findsOneWidget);
      expect(repo.updateCalls, isEmpty, reason: 'opening the form changes nothing');
    });
  });

  group('status menu', () {
    testWidgets('active project: no "Aktif yap"; Düzenle, hold, someday, complete, delete shown', (
      tester,
    ) async {
      await pumpList(tester);
      await openMenu(tester, 1);
      expect(find.byKey(const ValueKey('project-action-activate')), findsNothing);
      expect(find.text(ProjectsScreen.activateText), findsNothing);
      for (final k in ['edit', 'hold', 'someday', 'complete', 'delete']) {
        expect(find.byKey(ValueKey('project-action-$k')), findsOneWidget, reason: k);
        expectTapTarget(tester, find.byKey(ValueKey('project-action-$k')), k);
      }
    });

    testWidgets('completed project, limit full: "Aktif yap" disabled with the reason; '
        'no "Tamamla"', (tester) async {
      repo.limitsOverride = const ProjectLimits(maxActive: 3, activeCount: 3);
      await pumpList(tester);
      await openMenu(tester, 5);

      expect(menuItem(tester, 'activate').enabled, isFalse);
      expect(find.byKey(const ValueKey('project-action-activate-reason')), findsOneWidget);
      expect(find.text(ProjectsScreen.activateDisabledReason), findsOneWidget);
      expect(find.byKey(const ValueKey('project-action-complete')), findsNothing);
      expect(find.byKey(const ValueKey('project-action-hold')), findsOneWidget);
      expect(find.byKey(const ValueKey('project-action-someday')), findsOneWidget);

      // Tapping the disabled item sends nothing.
      await tester.tap(find.text(ProjectsScreen.activateText), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.updateCalls, isEmpty);
    });

    testWidgets('completed project, free slot: "Aktif yap" enabled, no reason; activating '
        'sends status active and moves the row', (tester) async {
      await pumpList(tester);
      await openMenu(tester, 5);
      expect(menuItem(tester, 'activate').enabled, isTrue);
      expect(find.text(ProjectsScreen.activateDisabledReason), findsNothing);
      expectTapTarget(tester, find.byKey(const ValueKey('project-action-activate')), 'activate');

      await tester.tap(find.text(ProjectsScreen.activateText));
      await tester.pumpAndSettle();

      expect(repo.updateCalls.single.$1, 5);
      expect(repo.updateCalls.single.$2, {'status': 'active'});
      expect(section(ProjectStatus.completed), findsNothing, reason: 'its only project left');
      expect(
        tester.getTopLeft(row(5)).dy,
        lessThan(tester.getTopLeft(section(ProjectStatus.onHold)).dy),
      );
      expect(counter(tester), 'Aktif 3/3');
    });

    testWidgets('"Tamamla" shown for on hold and someday projects', (tester) async {
      await pumpList(tester);
      for (final id in [3, 4]) {
        await openMenu(tester, id);
        expect(
          find.byKey(const ValueKey('project-action-complete')),
          findsOneWidget,
          reason: '$id',
        );
        await tester.tapAt(const Offset(5, 5)); // close the menu
        await tester.pumpAndSettle();
      }
    });

    testWidgets('"Beklemeye al" sends only the status; row moves, counter drops', (tester) async {
      await pumpList(tester);
      await openMenu(tester, 1);
      await tester.tap(find.text(ProjectsScreen.holdText));
      await tester.pumpAndSettle();

      expect(repo.updateCalls.single.$1, 1);
      expect(repo.updateCalls.single.$2, {'status': 'on_hold'});
      final holdTop = tester.getTopLeft(section(ProjectStatus.onHold)).dy;
      final somedayTop = tester.getTopLeft(section(ProjectStatus.someday)).dy;
      expect(tester.getTopLeft(row(1)).dy, inExclusiveRange(holdTop, somedayTop));
      expect(counter(tester), 'Aktif 1/3');
    });

    testWidgets('server 409 on "Aktif yap": limit message in a snackbar, list stays', (
      tester,
    ) async {
      await pumpList(tester);
      // The server is full although the page still shows 2/3.
      repo.maxActive = 2;
      await openMenu(tester, 3);
      await tester.tap(find.text(ProjectsScreen.activateText));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text(ActiveProjectLimitFailure.message),
        ),
        findsOneWidget,
      );
      expect(find.text('active_project_limit_reached'), findsNothing);
      expect(row(3), findsOneWidget);
      expect(counter(tester), 'Aktif 2/2', reason: 'refreshed from the server');
    });

    testWidgets('404 (deleted elsewhere): "Kaynak bulunamadı." and the row disappears', (
      tester,
    ) async {
      await pumpList(tester);
      repo.server = repo.server.where((p) => p.id != 4).toList();
      await openMenu(tester, 4);
      await tester.tap(find.text(ProjectsScreen.completeText));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.text('Kaynak bulunamadı.')),
        findsOneWidget,
      );
      expect(row(4), findsNothing);
      expect(section(ProjectStatus.someday), findsNothing);
    });
  });

  group('delete', () {
    Future<void> openDelete(WidgetTester tester, int id) async {
      await openMenu(tester, id);
      await tester.tap(find.byKey(const ValueKey('project-action-delete')));
      await tester.pumpAndSettle();
    }

    testWidgets('dialog shows the fixed question; Vazgeç deletes nothing', (tester) async {
      await pumpList(tester);
      await openDelete(tester, 2);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(ProjectsScreen.deleteQuestion),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(ProjectsScreen.deleteCancelText));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.deleteIds, isEmpty);
      expect(row(2), findsOneWidget);
    });

    testWidgets('double tap on Sil: dialog closes on the first tap, one DELETE, row gone', (
      tester,
    ) async {
      final pending = Completer<Either<Failure, void>>();
      repo.onDelete = (_) => pending.future;
      await pumpList(tester);
      await openDelete(tester, 2);

      final confirm = find.byKey(const ValueKey('project-delete-confirm'));
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(ProjectsScreen), findsOneWidget, reason: 'no extra pop');

      // Menu is disabled while the request runs.
      expect(tester.widget<PopupMenuButton<ProjectRowAction>>(menu(2)).enabled, isFalse);

      repo.server = repo.server.where((p) => p.id != 2).toList();
      pending.complete(const Right(null));
      await tester.pumpAndSettle();

      expect(repo.deleteIds, [2]);
      expect(row(2), findsNothing);
      expect(counter(tester), 'Aktif 1/3');
    });

    testWidgets('server error: snackbar with the fixed text, row stays', (tester) async {
      repo.onDelete = (_) async => const Left(_serverError);
      await pumpList(tester);
      await openDelete(tester, 1);
      await tester.tap(find.byKey(const ValueKey('project-delete-confirm')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.text(userMessage(_serverError))),
        findsOneWidget,
      );
      expect(row(1), findsOneWidget);
    });
  });

  group('load states', () {
    testWidgets('loading: spinner, no counter', (tester) async {
      repo.listGate = Completer<void>();
      await pumpList(tester, settle: false);
      expect(find.byKey(const ValueKey('projects-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('projects-active-counter')), findsNothing);
      repo.listGate!.complete();
      await tester.pumpAndSettle();
      expect(row(1), findsOneWidget);
    });

    testWidgets('empty: "Henüz proje yok" and "Proje ekle" opens the create form', (tester) async {
      repo.server = [];
      await pumpList(tester);
      expect(find.text(ProjectsScreen.emptyText), findsOneWidget);
      expect(counter(tester), 'Aktif 0/3');
      final add = find.byKey(const ValueKey('projects-empty-add'));
      expectTapTarget(tester, add, 'empty add');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text(ProjectEditScreen.createTitle), findsOneWidget);
    });

    testWidgets('error: fixed message and "Tekrar dene" reloads', (tester) async {
      repo.listFailure = _serverError;
      await pumpList(tester);
      expect(find.text(userMessage(_serverError)), findsOneWidget);
      final retry = find.byKey(const ValueKey('projects-retry'));
      expectTapTarget(tester, retry, 'retry');

      repo.listFailure = null;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.text(userMessage(_serverError)), findsNothing);
      expect(row(1), findsOneWidget);
    });

    testWidgets('silent refresh after a change: the list stays on screen (no spinner)', (
      tester,
    ) async {
      await pumpList(tester);
      repo.listGate = Completer<void>();
      await openMenu(tester, 1);
      await tester.tap(find.text(ProjectsScreen.somedayText));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('projects-loading')), findsNothing);
      expect(row(1), findsOneWidget);
      expect(row(5), findsOneWidget);
      repo.listGate!.complete();
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(row(1)).dy,
        greaterThan(tester.getTopLeft(section(ProjectStatus.someday)).dy),
      );
    });
  });
}
