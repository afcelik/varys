// Overflow matrix for /projects, /projects/new and /projects/edit at every
// layout breakpoint width (360..1800) and text scales 1.0 / 1.5.
//
// List states: filled (4 sections, long titles, null/0/25/100 progress,
// with and without target date), one section, empty, loading (pumped frame
// by frame, never pumpAndSettle), error, limit full ("Aktif yap" disabled
// with its reason). Form states: create, edit, limit full (reason below the
// dropdown), error snackbar open, keyboard open (~300 px), long title and
// long description.
//
// Every case: no exception (a RenderFlex overflow is reported as one),
// every visible tap target at least 48x48, and on the form a tap at the
// centre of Kaydet reaches the button.

import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/presentation/project_edit_screen.dart';
import 'package:varys/features/projects/presentation/projects_screen.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_project_repository.dart';

final _day = DateTime(2026, 11, 19);
const _serverError =
    ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _scales = [1.0, 1.5];
const _keyboard = 300.0;

final _longTitle = List.filled(40, 'Uzunbaşlıklıproje').join(' ').substring(0, 255);
final _longWord = 'A' * 255; // no break opportunity at all
final _longDescription = List.filled(250, 'açıklama').join(' ').substring(0, 2000);

/// Real GET /projects data (all four statuses) with long titles and every
/// progress kind: 1 -> 25% + target date, 2 -> null (no tasks, no dates),
/// 5 -> 100%, 9 -> 0% (tasks but none done).
List<Project> _filled() {
  final base = projectsFixture();
  return [
    base[0].copyWith(title: _longTitle, description: _longDescription),
    base[1],
    base[2].copyWith(title: _longWord),
    base[3],
    base[4].copyWith(title: _longTitle, targetDate: DateTime(2026, 12, 31)),
    base[1].copyWith(
        id: 9, title: _longWord, totalTasks: 3, doneTasks: 0, progressPercent: 0,
        status: ProjectStatus.onHold),
  ];
}

void main() {
  late FakeProjectRepository repo;
  late GoRouter router;

  setUpAll(() async => initializeDateFormatting('tr_TR', null));

  setUp(() => repo = FakeProjectRepository(_filled()));

  Future<void> pumpApp(
    WidgetTester tester,
    Size size,
    double scale, {
    String initial = AppRouter.projectsPath,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: AppRouter.homePath, builder: (_, _) => const Scaffold()),
        GoRoute(path: AppRouter.projectsPath, builder: (_, _) => const ProjectsScreen()),
        GoRoute(path: AppRouter.projectsNewPath, builder: (_, _) => const ProjectEditScreen()),
        GoRoute(
          path: AppRouter.projectsEditPath,
          builder: (_, state) => state.extra is Project
              ? ProjectEditScreen(project: state.extra! as Project)
              : const ProjectEditUnavailablePage(),
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
        projectRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    if (settle) await tester.pumpAndSettle();
  }

  final saveButton = find.byKey(const ValueKey('project-save'));
  final statusMenu = find.byType(DropdownMenu<ProjectStatus>);
  final reason = find.byKey(const ValueKey('project-active-unavailable'));

  void expectNoException(WidgetTester tester, String label) {
    expect(tester.takeException(), isNull, reason: label);
  }

  /// Every on-screen, hit-testable button-like widget is at least 48x48.
  void expectTapTargets(WidgetTester tester, String label) {
    final targets = find
        .byWidgetPredicate((w) => w is IconButton || w is PopupMenuButton || w is ButtonStyleButton)
        .hitTestable();
    final viewWidth = tester.view.physicalSize.width;
    for (final element in targets.evaluate()) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$label: ${element.widget} left');
      expect(rect.right, lessThanOrEqualTo(viewWidth + 0.5),
          reason: '$label: ${element.widget} right');
      expect(box.size.width, greaterThanOrEqualTo(48), reason: '$label: ${element.widget} width');
      expect(box.size.height, greaterThanOrEqualTo(48), reason: '$label: ${element.widget} height');
    }
    for (final key in ['project-start-date-button', 'project-target-date-button']) {
      final f = find.byKey(ValueKey(key)).hitTestable();
      if (f.evaluate().isNotEmpty) {
        expect(tester.getSize(f).height, greaterThanOrEqualTo(48), reason: '$label: $key');
      }
    }
  }

  /// [finder] is on screen, above [bottomInset], and a tap at its centre
  /// reaches it (not covered by a snackbar or the keyboard area).
  Future<void> expectReachableAndHittable(
    WidgetTester tester,
    Finder finder,
    String label, {
    double bottomInset = 0,
  }) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    final viewHeight = tester.view.physicalSize.height;
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(0), reason: '$label: top');
    expect(rect.bottom, lessThanOrEqualTo(viewHeight - bottomInset), reason: '$label: bottom');

    final target = tester.renderObject(finder);
    final hit = tester.hitTestOnBinding(rect.center);
    final hits = hit.path.any((entry) {
      RenderObject? node = entry.target is RenderObject ? entry.target as RenderObject : null;
      while (node != null) {
        if (identical(node, target)) return true;
        node = node.parent;
      }
      return false;
    });
    expect(hits, isTrue, reason: '$label: Kaydet is covered at its centre');
  }

  Future<void> openMenu(WidgetTester tester, int id) async {
    final menu = find.byKey(ValueKey('project-menu-$id'));
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }

  Future<void> closeMenu(WidgetTester tester) async {
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
  }

  Set<String> keysOnScreen() => {
        for (final e in find.byWidgetPredicate((w) => w.key is ValueKey<String>).evaluate())
          (e.widget.key! as ValueKey<String>).value,
      };

  /// Scrolls to the end, checking every frame; returns the keys seen
  /// (rows below the fold are only built once scrolled into view).
  Future<Set<String>> scrollThrough(WidgetTester tester, String label) async {
    final seen = <String>{};
    void collect() => seen.addAll(keysOnScreen());

    collect();
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pumpAndSettle();
      expectNoException(tester, '$label scrolled');
      expectTapTargets(tester, '$label scrolled');
      collect();
    }
    return seen;
  }

  for (final width in _widths) {
    for (final scale in _scales) {
      final label = '${width.toInt()}px x$scale';
      final size = Size(width, width <= 400 ? 740 : 900);

      group('/projects $label', () {
        testWidgets('filled: 4 sections, long titles, mixed progress and dates', (tester) async {
          await pumpApp(tester, size, scale);
          expect(find.byKey(const ValueKey('projects-section-active')), findsOneWidget);
          expect(find.byKey(const ValueKey('project-progress-1')), findsOneWidget);
          expect(find.byKey(const ValueKey('project-no-tasks-2')), findsOneWidget);
          expect(find.byKey(const ValueKey('project-target-1')), findsOneWidget);
          expectNoException(tester, '$label filled');
          expectTapTargets(tester, '$label filled');
          final seenAtStart = keysOnScreen();
          final title = tester.getRect(find.byKey(const ValueKey('project-title-1')));
          expect(title.right, lessThanOrEqualTo(width), reason: 'title inside the row');

          // Status menu of an active row and the delete dialog (long title).
          await openMenu(tester, 1);
          expect(find.byKey(const ValueKey('project-action-hold')), findsOneWidget);
          expectNoException(tester, '$label menu');
          expectTapTargets(tester, '$label menu');
          await tester.tap(find.byKey(const ValueKey('project-action-delete')));
          await tester.pumpAndSettle();
          expect(find.text(ProjectsScreen.deleteQuestion), findsOneWidget);
          expectNoException(tester, '$label delete dialog');
          expectTapTargets(tester, '$label delete dialog');
          await tester.tap(find.text(ProjectsScreen.deleteCancelText));
          await tester.pumpAndSettle();

          final seen = {...seenAtStart, ...await scrollThrough(tester, '$label filled')};
          for (final s in ProjectStatus.values) {
            expect(seen, contains('projects-section-${s.apiValue}'), reason: '$label ${s.name}');
          }
          expect(seen, containsAll(['project-progress-9', 'project-progress-5', 'project-row-4']));
        });

        testWidgets('limit full: "Aktif yap" disabled with its reason visible', (tester) async {
          repo.limitsOverride = const ProjectLimits(maxActive: 3, activeCount: 3);
          await pumpApp(tester, size, scale);
          expect(find.text('Aktif 3/3'), findsOneWidget);
          await openMenu(tester, 4);
          final item = tester.widget<PopupMenuItem<ProjectRowAction>>(
              find.byKey(const ValueKey('project-action-activate')));
          expect(item.enabled, isFalse);
          final reasonText = find.byKey(const ValueKey('project-action-activate-reason'));
          expect(reasonText, findsOneWidget);
          final r = tester.getRect(reasonText);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(width));
          expect(r.bottom, lessThanOrEqualTo(size.height));
          expectNoException(tester, '$label limit full menu');
          expectTapTargets(tester, '$label limit full menu');
          await closeMenu(tester);
        });

        testWidgets('one section only', (tester) async {
          repo.server = [_filled()[0], projectsFixture()[1]];
          await pumpApp(tester, size, scale);
          expect(find.byKey(const ValueKey('projects-section-active')), findsOneWidget);
          expect(find.byKey(const ValueKey('projects-section-on_hold')), findsNothing);
          expectNoException(tester, '$label one section');
          expectTapTargets(tester, '$label one section');
        });

        testWidgets('empty', (tester) async {
          repo.server = [];
          await pumpApp(tester, size, scale);
          expect(find.text(ProjectsScreen.emptyText), findsOneWidget);
          expectNoException(tester, '$label empty');
          expectTapTargets(tester, '$label empty');
        });

        testWidgets('loading (frame by frame, no pumpAndSettle)', (tester) async {
          repo.listGate = Completer<void>();
          await pumpApp(tester, size, scale, settle: false);
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byKey(const ValueKey('projects-loading')), findsOneWidget);
          expectNoException(tester, '$label loading');
          expectTapTargets(tester, '$label loading');
          repo.listGate!.complete();
          await tester.pumpAndSettle();
        });

        testWidgets('error', (tester) async {
          repo.listFailure = _serverError;
          await pumpApp(tester, size, scale);
          expect(find.byKey(const ValueKey('projects-retry')), findsOneWidget);
          expectNoException(tester, '$label error');
          expectTapTargets(tester, '$label error');
        });
      });

      group('project form $label', () {
        testWidgets('create: long title and description; then the limit-full reason below the '
            'dropdown', (tester) async {
          await pumpApp(tester, size, scale, initial: AppRouter.projectsNewPath);
          await tester.enterText(find.byKey(const ValueKey('project-title')), _longTitle);
          await tester.enterText(find.byKey(const ValueKey('project-description')), _longDescription);
          await tester.pumpAndSettle();
          expectNoException(tester, '$label create');
          expectTapTargets(tester, '$label create');
          await expectReachableAndHittable(tester, saveButton, '$label create');

          // Limit full: default Beklemede, reason text under the dropdown.
          repo.limitsOverride = const ProjectLimits(maxActive: 3, activeCount: 3);
          router.go(AppRouter.homePath);
          await tester.pumpAndSettle();
          router.go(AppRouter.projectsNewPath);
          await tester.pumpAndSettle();
          expect(reason, findsOneWidget);
          final r = tester.getRect(reason);
          expect(r.top, greaterThanOrEqualTo(tester.getRect(statusMenu).bottom));
          expect(r.right, lessThanOrEqualTo(width));
          expectNoException(tester, '$label limit full');
          expectTapTargets(tester, '$label limit full');
        });

        testWidgets('edit: long title and description, both dates set', (tester) async {
          final project = _filled()[0].copyWith(targetDate: DateTime(2100, 12, 31));
          await pumpApp(tester, size, scale);
          router.push(AppRouter.projectsEditPath, extra: project);
          await tester.pumpAndSettle();
          expect(find.text(ProjectEditScreen.editTitle), findsOneWidget);
          expectNoException(tester, '$label edit');
          expectTapTargets(tester, '$label edit');
          await tester.ensureVisible(find.byKey(const ValueKey('project-target-date-clear')));
          await tester.pumpAndSettle();
          expectTapTargets(tester, '$label edit dates');

          // Open the status dropdown.
          await tester.ensureVisible(statusMenu);
          await tester.pumpAndSettle();
          await tester.tap(statusMenu);
          await tester.pumpAndSettle();
          expectNoException(tester, '$label dropdown open');
          await tester.tap(find.widgetWithText(MenuItemButton, 'İleride').last);
          await tester.pumpAndSettle();
          await expectReachableAndHittable(tester, saveButton, '$label edit');
        });

        testWidgets('error snackbar open: Kaydet still reachable and hit at its centre',
            (tester) async {
          repo.onUpdate = (_, _) async => const Left(_serverError);
          final project = _filled()[0];
          await pumpApp(tester, size, scale);
          router.push(AppRouter.projectsEditPath, extra: project);
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const ValueKey('project-title')), '$_longWord!');
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const ValueKey('project-title')), 'Yeni ad');
          await tester.pumpAndSettle();
          await tester.tap(saveButton);
          await tester.pumpAndSettle();

          expect(find.byType(SnackBar), findsOneWidget);
          expectNoException(tester, '$label snackbar');
          expectTapTargets(tester, '$label snackbar');
          await expectReachableAndHittable(tester, saveButton, '$label snackbar');
          await tester.tap(saveButton);
          await tester.pump();
          expect(repo.updateCalls, hasLength(2), reason: 'second tap reached Kaydet');
          await tester.pumpAndSettle();
        });

        testWidgets('keyboard open (~300 px): Kaydet above it; with an error snackbar too',
            (tester) async {
          repo.onCreate = (_) async => const Left(_serverError);
          await pumpApp(tester, size, scale, initial: AppRouter.projectsNewPath);
          tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await tester.enterText(find.byKey(const ValueKey('project-title')), _longTitle);
          await tester.enterText(find.byKey(const ValueKey('project-description')), _longDescription);
          await tester.pumpAndSettle();
          expectNoException(tester, '$label keyboard');
          expectTapTargets(tester, '$label keyboard');
          await expectReachableAndHittable(tester, saveButton, '$label keyboard',
              bottomInset: _keyboard);

          await tester.tap(saveButton);
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsOneWidget);
          expectNoException(tester, '$label keyboard + snackbar');
          await expectReachableAndHittable(tester, saveButton, '$label keyboard + snackbar',
              bottomInset: _keyboard);
        });

        testWidgets('edit error page (no extra)', (tester) async {
          await pumpApp(tester, size, scale);
          router.push(AppRouter.projectsEditPath);
          await tester.pumpAndSettle();
          expect(find.text(ProjectEditUnavailablePage.message), findsOneWidget);
          expectNoException(tester, '$label unavailable');
          expectTapTargets(tester, '$label unavailable');
        });
      });
    }
  }
}
