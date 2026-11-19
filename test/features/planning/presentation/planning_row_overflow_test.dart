// Overflow matrix for the Planning page and row at every layout breakpoint
// width (360..1800) and text scales 1.0 / 1.5 — the states NOT already in
// task_form_overflow_test.dart (which covers the row with project + due +
// description + long title, description only, meta only, and neither):
// - completed row (struck-through title, long title, description, meta line),
// - page loading (pumped frame by frame, never pumpAndSettle),
// - page error (initial load failed: message + Tekrar Dene),
// - empty list.
//
// Every case: no exception; every visible tap target (checkbox, Sil, chips,
// FAB, buttons) at least 48x48; the row 48+ high; description and meta line
// clamped to 2 lines and inside the row; the title wraps inside the row.

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
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_list_page.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../projects/fake_project_repository.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _scales = [1.0, 1.5];

final _longTitle = List.filled(40, 'Uzunbaşlıklıgörev').join(' ').substring(0, 255);
final _longWord = 'P' * 255; // a project name with no break opportunity at all
final _longDescription = List.filled(250, 'açıklama').join(' ').substring(0, 2000);

/// Completed, with every subtitle part: long title, description, project 2
/// (long unbreakable name) and a due day.
final _completed = Task(
  id: 7,
  title: _longTitle,
  description: _longDescription,
  status: TaskStatus.done,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  projectId: 2,
  dueDate: DateTime(2026, 11, 21),
);

void main() {
  late FakeProjectRepository projectRepo;
  late _MockTaskRepository taskRepo;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    final base = projectsFixture();
    projectRepo = FakeProjectRepository([
      base[0],
      base[1].copyWith(title: _longWord),
      ...base.skip(2),
    ]);
    taskRepo = _MockTaskRepository();
  });

  Future<void> pumpPlanning(
    WidgetTester tester,
    Size size,
    double scale, {
    bool settle = true,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.planningPath,
      routes: [GoRoute(path: AppRouter.planningPath, builder: (_, _) => const TaskListPage())],
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

  void expectNoException(WidgetTester tester, String label) {
    expect(tester.takeException(), isNull, reason: label);
  }

  /// Every on-screen, hit-testable tap target is at least 48x48; outside a
  /// horizontal scroller (the filter chips) it is also inside the view.
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
      final axis = Scrollable.maybeOf(element)?.axisDirection;
      if (axis == AxisDirection.left || axis == AxisDirection.right) continue;
      expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$label: ${element.widget} left');
      expect(
        rect.right,
        lessThanOrEqualTo(viewWidth + 0.5),
        reason: '$label: ${element.widget} right',
      );
    }
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

  for (final width in _widths) {
    for (final scale in _scales) {
      final label = '${width.toInt()}px x$scale';
      final size = Size(width, width <= 400 ? 740 : 900);

      group('Planning $label', () {
        testWidgets('completed row: struck-through long title, description, meta line', (
          tester,
        ) async {
          when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([_completed]));
          await pumpPlanning(tester, size, scale);

          final title = find.text(_longTitle);
          final description = find.text(_longDescription);
          final meta = find.byKey(const ValueKey('task-meta-7'));
          expect(tester.widget<Text>(title).style?.decoration, TextDecoration.lineThrough);
          expect(tester.widget<Text>(meta).data, '$_longWord · 21 Kas');
          expect(
            tester.widget<Checkbox>(find.byType(Checkbox)).value,
            isTrue,
            reason: 'completed row',
          );

          expectNoException(tester, '$label completed');
          expectTapTargets(tester, '$label completed');
          expectAtMostLines(tester, description, 2, '$label description');
          expectAtMostLines(tester, meta, 2, '$label meta');

          final card = tester.getRect(
            find.descendant(of: find.byKey(const ValueKey(7)), matching: find.byType(Card)),
          );
          expect(card.height, greaterThanOrEqualTo(48), reason: '$label: row tap target');
          for (final (what, f) in [
            ('title', title),
            ('description', description),
            ('meta', meta),
          ]) {
            final r = tester.getRect(f);
            expect(r.left, greaterThanOrEqualTo(card.left - 0.5), reason: '$label: $what left');
            expect(r.right, lessThanOrEqualTo(card.right + 0.5), reason: '$label: $what right');
            expect(r.bottom, lessThanOrEqualTo(card.bottom + 0.5), reason: '$label: $what bottom');
          }
        });

        testWidgets('loading (frame by frame, no pumpAndSettle)', (tester) async {
          final pending = Completer<Either<Failure, List<Task>>>();
          when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) => pending.future);
          await pumpPlanning(tester, size, scale, settle: false);
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expectNoException(tester, '$label loading');
          expectTapTargets(tester, '$label loading');

          pending.complete(Right([_completed]));
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.text(_longTitle), findsOneWidget);
          expectNoException(tester, '$label loaded');
        });

        testWidgets('initial load error: message and Tekrar Dene', (tester) async {
          when(
            () => taskRepo.getTasksByFilter(any()),
          ).thenAnswer((_) async => const Left(NetworkFailure('Sunucuya bağlanılamıyor')));
          await pumpPlanning(tester, size, scale);

          expect(find.text('Bir hata oluştu'), findsOneWidget);
          expect(find.text('Bağlantı hatası'), findsOneWidget);
          final retry = find.widgetWithText(FilledButton, 'Tekrar Dene');
          expect(retry, findsOneWidget);
          expectNoException(tester, '$label error');
          expectTapTargets(tester, '$label error');
          final r = tester.getRect(retry);
          expect(r.right, lessThanOrEqualTo(width + 0.5), reason: '$label: retry inside view');
        });

        testWidgets('empty list', (tester) async {
          when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Right([]));
          await pumpPlanning(tester, size, scale);

          expect(find.text('Görev bulunamadı'), findsOneWidget);
          expectNoException(tester, '$label empty');
          expectTapTargets(tester, '$label empty');
        });
      });
    }
  }
}
