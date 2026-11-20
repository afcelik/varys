// Overflow matrix for the task create form (/tasks/new) and the Planning row
// at every layout breakpoint width (360..1800) and text scales 1.0 / 1.5.
//
// Form states: empty, filled (255-character title, 2000-character
// description, long unbreakable project name chosen, due date set, project
// menu open), projects failed to load (note + Tekrar dene), projects loading
// (pumped frame by frame, never pumpAndSettle), error snackbar open, keyboard
// open (~300 px, with and without the snackbar).
// Planning row states: project name + due day + long title + description,
// description only, meta line only, neither.
//
// Every case: no exception (a RenderFlex overflow is reported as one), every
// visible tap target at least 48x48 and inside the view; on the form a tap at
// the centre of Kaydet reaches the button; on the row the description and the
// meta line stay clamped to 2 lines and inside the row.

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

Task _task({String? title, String? description, int? projectId, DateTime? due}) => Task(
  id: 7,
  title: title ?? 'Görev',
  description: description,
  status: TaskStatus.todo,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  projectId: projectId,
  dueDate: due,
);

void main() {
  late FakeProjectRepository projectRepo;
  late _MockTaskRepository taskRepo;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(_task());
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
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
  });

  Future<void> pumpApp(
    WidgetTester tester,
    Size size,
    double scale, {
    String initial = AppRouter.tasksNewPath,
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: AppRouter.homePath, builder: (_, _) => const Scaffold()),
        GoRoute(path: AppRouter.planningPath, builder: (_, _) => const TaskListPage()),
        GoRoute(path: AppRouter.tasksNewPath, builder: (_, _) => const TaskEditScreen()),
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
  final descriptionField = find.byKey(const ValueKey('task-description'));
  final saveButton = find.byKey(const ValueKey('task-save'));
  final projectMenu = find.byType(DropdownMenu<ProjectChoice>);

  void expectNoException(WidgetTester tester, String label) {
    expect(tester.takeException(), isNull, reason: label);
  }

  /// Every on-screen, hit-testable tap target is at least 48x48 and inside
  /// the view horizontally.
  void expectTapTargets(WidgetTester tester, String label) {
    final targets = find
        .byWidgetPredicate(
          (w) =>
              w is IconButton ||
              w is ButtonStyleButton ||
              w is FloatingActionButton ||
              w is Checkbox ||
              w is FilterChip,
        )
        .hitTestable();
    final viewWidth = tester.view.physicalSize.width;
    for (final element in targets.evaluate()) {
      final box = element.renderObject! as RenderBox;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      expect(box.size.width, greaterThanOrEqualTo(48), reason: '$label: ${element.widget} width');
      expect(box.size.height, greaterThanOrEqualTo(48), reason: '$label: ${element.widget} height');
      // In a horizontal scroller (Planning's filter chips) a target may sit
      // partly outside the view; it is reached by scrolling, which
      // [expectScrollableChipsReachable] checks.
      final axis = Scrollable.maybeOf(element)?.axisDirection;
      if (axis == AxisDirection.left || axis == AxisDirection.right) continue;
      expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$label: ${element.widget} left');
      expect(
        rect.right,
        lessThanOrEqualTo(viewWidth + 0.5),
        reason: '$label: ${element.widget} right',
      );
    }
    final due = find.byKey(const ValueKey('task-due-date-button')).hitTestable();
    if (due.evaluate().isNotEmpty) {
      expect(tester.getSize(due).height, greaterThanOrEqualTo(48), reason: '$label: due date');
    }
  }

  /// Every filter chip of the Planning page can be scrolled fully into view.
  Future<void> expectScrollableChipsReachable(WidgetTester tester, String label) async {
    final viewWidth = tester.view.physicalSize.width;
    for (final filter in TaskFilter.values) {
      final chip = find.widgetWithText(FilterChip, filter.label);
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      final r = tester.getRect(chip);
      expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$label: ${filter.label} left');
      expect(r.right, lessThanOrEqualTo(viewWidth + 0.5), reason: '$label: ${filter.label} right');
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

  Future<void> fillAll(WidgetTester tester) async {
    await tester.enterText(titleField, _longTitle);
    await tester.enterText(descriptionField, _longDescription);
    await tester.pumpAndSettle();
  }

  for (final width in _widths) {
    for (final scale in _scales) {
      final label = '${width.toInt()}px x$scale';
      final size = Size(width, width <= 400 ? 740 : 900);

      group('task form $label', () {
        testWidgets('empty', (tester) async {
          await pumpApp(tester, size, scale);
          expect(find.text(TaskEditScreen.createTitle), findsOneWidget);
          expectNoException(tester, '$label empty');
          expectTapTargets(tester, '$label empty');
          await expectReachableAndHittable(tester, saveButton, '$label empty');
        });

        testWidgets('filled: long title/description, long project name, due date; menu open', (
          tester,
        ) async {
          when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(_task()));
          await pumpApp(tester, size, scale);
          await fillAll(tester);

          await tester.ensureVisible(projectMenu);
          await tester.pumpAndSettle();
          await tester.tap(projectMenu);
          await tester.pumpAndSettle();
          expectNoException(tester, '$label menu open');
          await tester.tap(find.widgetWithText(MenuItemButton, _longWord).last);
          await tester.pumpAndSettle();
          expect(tester.widget<DropdownMenu<ProjectChoice>>(projectMenu).initialSelection?.id, 2);

          final due = find.byKey(const ValueKey('task-due-date-button'));
          await tester.ensureVisible(due);
          await tester.pumpAndSettle();
          await tester.tap(due);
          await tester.pumpAndSettle();
          expectNoException(tester, '$label picker');
          await tester.tap(find.text('Tamam'));
          await tester.pumpAndSettle();
          expect(find.text('19.11.2026'), findsOneWidget);

          expectNoException(tester, '$label filled');
          expectTapTargets(tester, '$label filled');
          await tester.ensureVisible(find.byKey(const ValueKey('task-due-date-clear')));
          await tester.pumpAndSettle();
          expectTapTargets(tester, '$label filled, date row');
          await expectReachableAndHittable(tester, saveButton, '$label filled');
        });

        testWidgets('projects failed to load: note and Tekrar dene', (tester) async {
          projectRepo.listFailure = const NetworkFailure('Sunucuya bağlanılamıyor');
          await pumpApp(tester, size, scale);
          await fillAll(tester);
          final note = find.text(TaskEditScreen.projectsErrorText);
          expect(note, findsOneWidget);
          await tester.ensureVisible(find.byKey(const ValueKey('task-projects-retry')));
          await tester.pumpAndSettle();
          expect(tester.getRect(note).right, lessThanOrEqualTo(width));
          expectNoException(tester, '$label projects error');
          expectTapTargets(tester, '$label projects error');
          await expectReachableAndHittable(tester, saveButton, '$label projects error');
        });

        testWidgets('projects loading (frame by frame, no pumpAndSettle)', (tester) async {
          projectRepo.listGate = Completer<void>();
          await pumpApp(tester, size, scale, settle: false);
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byKey(const ValueKey('task-projects-loading')), findsOneWidget);
          await tester.enterText(titleField, _longTitle);
          await tester.pump(const Duration(milliseconds: 100));
          expectNoException(tester, '$label loading');
          expectTapTargets(tester, '$label loading');
          await expectReachableAndHittable(tester, saveButton, '$label loading');
          projectRepo.listGate!.complete();
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byKey(const ValueKey('task-projects-loading')), findsNothing);
        });

        testWidgets('error snackbar open: Kaydet still reachable and hit at its centre', (
          tester,
        ) async {
          when(() => taskRepo.createTask(any())).thenAnswer((_) async => const Left(_serverError));
          await pumpApp(tester, size, scale);
          await fillAll(tester);
          await tester.tap(saveButton);
          await tester.pumpAndSettle();

          expect(find.byType(SnackBar), findsOneWidget);
          expectNoException(tester, '$label snackbar');
          expectTapTargets(tester, '$label snackbar');
          await expectReachableAndHittable(tester, saveButton, '$label snackbar');
          await tester.tap(saveButton);
          await tester.pump();
          verify(() => taskRepo.createTask(any())).called(2);
          await tester.pumpAndSettle();
        });

        testWidgets('keyboard open (~300 px): Kaydet above it; with an error snackbar too', (
          tester,
        ) async {
          when(() => taskRepo.createTask(any())).thenAnswer((_) async => const Left(_serverError));
          await pumpApp(tester, size, scale);
          tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          await fillAll(tester);
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

        testWidgets('Eisenhower switches on, then error snackbar: rows >= 48, help <= 2 lines', (
          tester,
        ) async {
          when(() => taskRepo.createTask(any())).thenAnswer((_) async => const Left(_serverError));
          Future<void> pumpCase(WidgetTester t, Size s, double sc) async {
            await pumpApp(t, s, sc);
            await t.enterText(titleField, _longTitle);
            await t.pumpAndSettle();
          }

          await pumpCase(tester, size, scale);
          final important = find.byKey(const ValueKey('task-important'));
          final urgent = find.byKey(const ValueKey('task-urgent'));
          for (final (f, help) in [
            (important, TaskEditScreen.importantHelp),
            (urgent, TaskEditScreen.urgentHelp),
          ]) {
            await tester.ensureVisible(f);
            await tester.pumpAndSettle();
            await tester.tap(f);
            await tester.pumpAndSettle();
            final tile = tester.widget<SwitchListTile>(
              find.descendant(of: f, matching: find.byType(SwitchListTile)),
            );
            expect(tile.value, isTrue, reason: '$label $help switched on');
            final rect = tester.getRect(f);
            expect(rect.height, greaterThanOrEqualTo(48), reason: '$label $help row height');
            expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$label $help left');
            expect(rect.right, lessThanOrEqualTo(width + 0.5), reason: '$label $help right');
            final helpText = find.descendant(of: f, matching: find.text(help));
            expect(tester.widget<Text>(helpText).maxLines, 2);
            expectAtMostLines(tester, helpText, 2, '$label $help');
            final labelText = find.descendant(
              of: f,
              matching: find.text(
                f == important ? TaskEditScreen.importantLabel : TaskEditScreen.urgentLabel,
              ),
            );
            expectAtMostLines(tester, labelText, 1, '$label $help label');
          }
          expectNoException(tester, '$label switches');
          expectTapTargets(tester, '$label switches');
          await expectReachableAndHittable(tester, saveButton, '$label switches');

          await tester.tap(saveButton);
          await tester.pumpAndSettle();
          expect(find.byType(SnackBar), findsOneWidget);
          expectNoException(tester, '$label switches + snackbar');
          await expectReachableAndHittable(tester, saveButton, '$label switches + snackbar');
        });
      });

      group('Planning row $label', () {
        final meta = find.byKey(const ValueKey('task-meta-7'));

        Future<void> pumpRow(WidgetTester tester, Task task) async {
          when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([task]));
          await pumpApp(tester, size, scale, initial: AppRouter.planningPath);
        }

        void expectInsideRow(WidgetTester tester, Finder f, String what) {
          final row = tester.getRect(
            find.descendant(of: find.byKey(const ValueKey(7)), matching: find.byType(Card)),
          );
          final r = tester.getRect(f);
          expect(r.left, greaterThanOrEqualTo(row.left - 0.5), reason: '$label: $what left');
          expect(r.right, lessThanOrEqualTo(row.right + 0.5), reason: '$label: $what right');
        }

        testWidgets('long title + description + project name + due day', (tester) async {
          await pumpRow(
            tester,
            _task(
              title: _longTitle,
              description: _longDescription,
              projectId: 2,
              due: DateTime(2026, 11, 21),
            ),
          );
          expect(find.text(_longTitle), findsOneWidget);
          expect(meta, findsOneWidget);
          expect(tester.widget<Text>(meta).data, '$_longWord · 21 Kas');
          expectNoException(tester, '$label full row');
          expectTapTargets(tester, '$label full row');
          await expectScrollableChipsReachable(tester, '$label full row');
          expectInsideRow(tester, find.text(_longTitle), 'title');
          expectInsideRow(tester, meta, 'meta');
          expectAtMostLines(tester, find.text(_longDescription), 2, '$label description');
          expectAtMostLines(tester, meta, 2, '$label meta');
          expect(
            tester.getRect(find.text(_longDescription)).bottom,
            lessThanOrEqualTo(tester.getRect(meta).top + 0.5),
            reason: 'description above the meta line',
          );
        });

        testWidgets('description only', (tester) async {
          await pumpRow(tester, _task(title: _longTitle, description: _longDescription));
          expect(meta, findsNothing);
          expectNoException(tester, '$label description only');
          expectTapTargets(tester, '$label description only');
          await expectScrollableChipsReachable(tester, '$label description only');
          expectAtMostLines(tester, find.text(_longDescription), 2, '$label description');
          expectInsideRow(tester, find.text(_longDescription), 'description');
        });

        testWidgets('meta line only (long project name + due day)', (tester) async {
          await pumpRow(tester, _task(projectId: 1, due: DateTime(2026, 11, 21)));
          expect(tester.widget<Text>(meta).data, '$_longTitle · 21 Kas');
          expectNoException(tester, '$label meta only');
          expectTapTargets(tester, '$label meta only');
          await expectScrollableChipsReachable(tester, '$label meta only');
          expectAtMostLines(tester, meta, 2, '$label meta');
          expectInsideRow(tester, meta, 'meta');
        });

        testWidgets('neither: no subtitle', (tester) async {
          await pumpRow(tester, _task(title: _longTitle));
          expect(meta, findsNothing);
          final tile = tester.widget<ListTile>(
            find.ancestor(of: find.text(_longTitle), matching: find.byType(ListTile)),
          );
          expect(tile.subtitle, isNull);
          expectNoException(tester, '$label neither');
          expectTapTargets(tester, '$label neither');
          await expectScrollableChipsReachable(tester, '$label neither');
          expectInsideRow(tester, find.text(_longTitle), 'title');
        });
      });
    }
  }
}
