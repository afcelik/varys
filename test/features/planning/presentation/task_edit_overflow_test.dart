// Overflow matrix for the task EDIT form (/tasks/edit) at every layout
// breakpoint width (360..1800) and text scales 1.0 / 1.5.
//
// States: filled (255-character title, 2000-character description, a project
// with one long unbreakable name, due date and planned day both set, project
// menu open), "Mevcut proje" (projects loading: field disabled; pumped frame
// by frame, never pumpAndSettle), projects failed to load ("Mevcut proje" +
// note + Tekrar dene), error snackbar open, keyboard open (~300 px, with and
// without the snackbar).
//
// Every case: no exception (a RenderFlex overflow is reported as one); every
// visible tap target at least 48x48 and inside the view (the two day fields
// too); a tap at the centre of Kaydet reaches it; texts with maxLines stay
// within their line count (title bar 1, day texts 1, planned-day help 3).

import 'dart:async';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/planning/presentation/task_list_page.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../projects/fake_project_repository.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

final _day = DateTime(2026, 11, 19);
const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _scales = [1.0, 1.5];
const _keyboard = 300.0;

final _longTitle = List.filled(40, 'Uzunbaşlıklıgörev').join(' ').substring(0, 255);
final _longWord = 'P' * 255; // a project name with no break opportunity at all
final _longDescription = List.filled(250, 'açıklama').join(' ').substring(0, 2000);

/// The edited task: everything filled, linked to project 2 (long name).
final _task = Task(
  id: 7,
  title: _longTitle,
  description: _longDescription,
  status: TaskStatus.todo,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  projectId: 2,
  dueDate: DateTime(2026, 11, 25),
  plannedDate: DateTime(2026, 11, 19),
);

void main() {
  late FakeProjectRepository projectRepo;
  late _MockTaskRepository taskRepo;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(const PlanField<String>.unset());
    registerFallbackValue(const PlanField<int>.unset());
    registerFallbackValue(const PlanField<DateTime>.unset());
  });

  setUp(() {
    // Real GET /projects with long names: 1 → long title, 2 → one long word.
    final base = projectsFixture();
    projectRepo = FakeProjectRepository([
      base[0].copyWith(title: _longTitle),
      base[1].copyWith(title: _longWord),
      ...base.skip(2),
    ]);
    taskRepo = _MockTaskRepository();
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([_task]));
  });

  void answerUpdate(Either<Failure, Task> result) {
    when(
      () => taskRepo.updateTask(
        any(),
        title: any(named: 'title'),
        description: any(named: 'description'),
        status: any(named: 'status'),
        plannedDate: any(named: 'plannedDate'),
        dueDate: any(named: 'dueDate'),
        projectId: any(named: 'projectId'),
      ),
    ).thenAnswer((_) async => result);
  }

  int updateCalls() => verify(
    () => taskRepo.updateTask(
      any(),
      title: any(named: 'title'),
      description: any(named: 'description'),
      status: any(named: 'status'),
      plannedDate: any(named: 'plannedDate'),
      dueDate: any(named: 'dueDate'),
      projectId: any(named: 'projectId'),
    ),
  ).callCount;

  /// The edit form opened with [_task] (as from a Planning row).
  Future<void> pumpForm(WidgetTester tester, Size size, double scale, {bool settle = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.tasksEditPath,
      initialExtra: _task,
      routes: [
        GoRoute(path: AppRouter.homePath, builder: (_, _) => const Scaffold()),
        GoRoute(path: AppRouter.planningPath, builder: (_, _) => const TaskListPage()),
        GoRoute(
          path: AppRouter.tasksEditPath,
          builder: (_, state) => state.extra is Task
              ? TaskEditScreen(task: state.extra as Task)
              : const TaskEditUnavailablePage(),
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
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ],
    );
    if (settle) await tester.pumpAndSettle();
  }

  final titleField = find.byKey(const ValueKey('task-title'));
  final saveButton = find.byKey(const ValueKey('task-save'));
  final projectMenu = find.byType(DropdownMenu<ProjectChoice>);
  final dueText = find.byKey(const ValueKey('task-due-date-text'));
  final plannedText = find.byKey(const ValueKey('task-planned-date-text'));
  final plannedHelp = find.text(TaskEditScreen.plannedDateHelp);
  final appBarTitle = find.descendant(
    of: find.byType(AppBar),
    matching: find.text(TaskEditScreen.editTitle),
  );

  void expectNoException(WidgetTester tester, String label) {
    expect(tester.takeException(), isNull, reason: label);
  }

  /// Every on-screen, hit-testable tap target is at least 48x48 and inside
  /// the view horizontally; the two day fields are at least 48 high.
  void expectTapTargets(WidgetTester tester, String label) {
    final targets = find
        .byWidgetPredicate(
          (w) => w is IconButton || w is ButtonStyleButton || w is FloatingActionButton,
        )
        .hitTestable();
    final viewWidth = tester.view.physicalSize.width;
    for (final element in targets.evaluate()) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      expect(box.size.width, greaterThanOrEqualTo(48), reason: '$label: ${element.widget} width');
      expect(box.size.height, greaterThanOrEqualTo(48), reason: '$label: ${element.widget} height');
      expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$label: ${element.widget} left');
      expect(
        rect.right,
        lessThanOrEqualTo(viewWidth + 0.5),
        reason: '$label: ${element.widget} right',
      );
    }
    for (final key in ['task-due-date-button', 'task-planned-date-button']) {
      final field = find.byKey(ValueKey(key)).hitTestable();
      if (field.evaluate().isNotEmpty) {
        expect(tester.getSize(field).height, greaterThanOrEqualTo(48), reason: '$label: $key');
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

  /// The text at [finder] renders at most [lines] lines.
  void expectAtMostLines(WidgetTester tester, Finder finder, int lines, String label) {
    final paragraph = tester.renderObject<RenderParagraph>(finder);
    final oneLine = TextPainter(
      text: TextSpan(text: 'Ağ', style: (paragraph.text as TextSpan).style),
      textDirection: TextDirection.ltr,
      textScaler: paragraph.textScaler,
    )..layout();
    expect(
      paragraph.size.height,
      lessThanOrEqualTo(oneLine.height * lines + 0.5),
      reason: '$label: more than $lines lines',
    );
    oneLine.dispose();
  }

  /// Line limits of the form's texts that declare maxLines.
  Future<void> expectLineLimits(WidgetTester tester, String label) async {
    expectAtMostLines(tester, appBarTitle, 1, '$label app bar title');
    await tester.ensureVisible(plannedHelp);
    await tester.pump();
    expectAtMostLines(tester, dueText, 1, '$label due text');
    expectAtMostLines(tester, plannedText, 1, '$label planned text');
    expectAtMostLines(tester, plannedHelp, 3, '$label planned help');
  }

  for (final width in _widths) {
    for (final scale in _scales) {
      final label = '${width.toInt()}px x$scale';
      final size = Size(width, width <= 400 ? 740 : 900);

      group('task edit form $label', () {
        testWidgets('filled: long values, long project name, both days; menu open', (tester) async {
          await pumpForm(tester, size, scale);
          expect(find.text(TaskEditScreen.editTitle), findsOneWidget);
          expect(tester.widget<DropdownMenu<ProjectChoice>>(projectMenu).initialSelection?.id, 2);
          expect(tester.widget<Text>(dueText).data, '25.11.2026');
          expect(tester.widget<Text>(plannedText).data, '19.11.2026');

          await tester.ensureVisible(projectMenu);
          await tester.pumpAndSettle();
          await tester.tap(projectMenu);
          await tester.pumpAndSettle();
          expectNoException(tester, '$label menu open');
          await tester.tap(find.widgetWithText(MenuItemButton, _longTitle).last);
          await tester.pumpAndSettle();

          expectNoException(tester, '$label filled');
          expectTapTargets(tester, '$label filled');
          await expectLineLimits(tester, '$label filled');
          await tester.ensureVisible(find.byKey(const ValueKey('task-planned-date-clear')));
          await tester.pumpAndSettle();
          expectTapTargets(tester, '$label filled, day rows');
          await expectReachableAndHittable(tester, saveButton, '$label filled');
        });

        testWidgets('"Mevcut proje" while projects load (frame by frame, no pumpAndSettle)', (
          tester,
        ) async {
          projectRepo.listGate = Completer<void>();
          await pumpForm(tester, size, scale, settle: false);
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final menu = tester.widget<DropdownMenu<ProjectChoice>>(projectMenu);
          expect(menu.enabled, isFalse);
          expect(menu.initialSelection?.label, TaskEditScreen.currentProjectLabel);
          expect(find.byKey(const ValueKey('task-projects-loading')), findsOneWidget);
          expectNoException(tester, '$label pending');
          expectTapTargets(tester, '$label pending');
          await expectLineLimits(tester, '$label pending');
          await expectReachableAndHittable(tester, saveButton, '$label pending');
          projectRepo.listGate!.complete();
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byKey(const ValueKey('task-projects-loading')), findsNothing);
          expectNoException(tester, '$label loaded');
        });

        testWidgets('projects failed to load: "Mevcut proje", note and Tekrar dene', (
          tester,
        ) async {
          projectRepo.listFailure = const NetworkFailure('Sunucuya bağlanılamıyor');
          await pumpForm(tester, size, scale);
          expect(
            tester.widget<DropdownMenu<ProjectChoice>>(projectMenu).initialSelection?.label,
            TaskEditScreen.currentProjectLabel,
          );
          final note = find.text(TaskEditScreen.projectsErrorText);
          await tester.ensureVisible(find.byKey(const ValueKey('task-projects-retry')));
          await tester.pumpAndSettle();
          expect(tester.getRect(note).right, lessThanOrEqualTo(width));
          expectNoException(tester, '$label projects error');
          expectTapTargets(tester, '$label projects error');
          await expectLineLimits(tester, '$label projects error');
          await expectReachableAndHittable(tester, saveButton, '$label projects error');
        });

        testWidgets('error snackbar open: Kaydet still reachable and hit at its centre', (
          tester,
        ) async {
          answerUpdate(const Left(_serverError));
          await pumpForm(tester, size, scale);
          // Still 255 characters, but changed (Kaydet enabled).
          await tester.enterText(titleField, _longTitle.replaceFirst('U', 'K'));
          await tester.pumpAndSettle();
          await tester.tap(saveButton);
          await tester.pumpAndSettle();

          expect(find.byType(SnackBar), findsOneWidget);
          expectNoException(tester, '$label snackbar');
          expectTapTargets(tester, '$label snackbar');
          await expectReachableAndHittable(tester, saveButton, '$label snackbar');
          await tester.tap(saveButton);
          await tester.pump();
          expect(updateCalls(), 2);
          await tester.pumpAndSettle();
        });

        testWidgets('keyboard open (~300 px): Kaydet above it; with an error snackbar too', (
          tester,
        ) async {
          answerUpdate(const Left(_serverError));
          await pumpForm(tester, size, scale);
          tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await tester.enterText(titleField, 'Klavye açıkken ${'x' * 200}');
          await tester.pumpAndSettle();
          expectNoException(tester, '$label keyboard');
          expectTapTargets(tester, '$label keyboard');
          await expectReachableAndHittable(
            tester,
            saveButton,
            '$label keyboard',
            bottomInset: _keyboard,
          );

          await tester.tap(saveButton);
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsOneWidget);
          expectNoException(tester, '$label keyboard + snackbar');
          await expectReachableAndHittable(
            tester,
            saveButton,
            '$label keyboard + snackbar',
            bottomInset: _keyboard,
          );
        });
      });
    }
  }
}
