// Overflow matrix for the quadrant page (/eisenhower/:quadrant) on the real
// app router, at every layout breakpoint width (360..1800) and text scales
// 1.0 / 1.5. States: filled (an unbroken 255-character title, a long
// many-word title, a long project name with a due day), empty, error, and
// loading (pumped frame by frame, never pumpAndSettle).
//
// Every case: no exception; app bar name and subtitle 1 line each; row
// titles at most 2 lines and meta lines at most 2 (measured, Step 29
// method); every tap target (rows, BackArrow, Tekrar dene) at least 48x48
// and inside the view.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/router/router_provider.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/eisenhower_quadrant_page.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/eisenhower.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../notes/fake_note_repository.dart';
import '../../projects/fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _scales = [1.0, 1.5];

final _unbroken = 'Ğ' * 255;
final _manyWords = List.filled(40, 'Uzunbaşlıklıgörev').join(' ').substring(0, 255);
final _longWord = 'P' * 255; // a project name with no break opportunity

/// Real GET /tasks; "Planla" (schedule) gets the worst case: the unbroken
/// title (project 1, renamed to [_longWord]), the many-word title with only
/// a due day, and the real task 2 (project 1).
List<Task> _worstCase() {
  final base = (jsonDecode(File('test/fixtures/tasks_eisenhower.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>()
      .map(Task.fromJson)
      .toList();
  final schedule = base.firstWhere((t) => t.id == 2);
  return [
    schedule.copyWith(id: 21, title: _unbroken, createdAt: DateTime(2026, 11, 22)),
    schedule.copyWith(
      id: 22,
      title: _manyWords,
      projectId: null,
      dueDate: DateTime(2026, 11, 25),
      createdAt: DateTime(2026, 11, 21),
    ),
    ...base,
  ];
}

void main() {
  late _MockTaskRepository taskRepo;
  late _MockDailyPlanRepository planRepo;
  late _MockRoutineRepository routineRepo;
  late FakeProjectRepository projectRepo;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
    registerFallbackValue(TaskFilter.all);
  });

  setUp(() {
    taskRepo = _MockTaskRepository();
    planRepo = _MockDailyPlanRepository();
    routineRepo = _MockRoutineRepository();
    final projects = projectsFixture();
    projectRepo = FakeProjectRepository([
      projects[0].copyWith(title: _longWord),
      ...projects.skip(1),
    ]);
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(_worstCase()));
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => const Right([]));
  });

  /// Real app, logged in on Home; then the quadrant page is pushed. With
  /// [settle] false nothing waits with pumpAndSettle (a request is pending).
  Future<void> openPage(
    WidgetTester tester,
    double width,
    double scale,
    EisenhowerQuadrant q, {
    bool settle = true,
  }) async {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    tester.view.physicalSize = Size(width, width <= 400 ? 740 : 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      textScale: scale,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
        noteRepositoryProvider.overrideWith((ref) async => FakeNoteRepository()),
      ],
    );
    for (var i = 0; i < 30 && find.byType(HomeScreen).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    router = container.read(routerProvider);
    unawaited(router.push(AppRouter.eisenhowerPath(q)));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(find.byType(EisenhowerQuadrantPage), findsOneWidget);
  }

  /// Step 29 method: rendered height against one line of the same style.
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

  /// No exception, app bar lines, BackArrow target.
  void expectFrame(WidgetTester tester, double width, String label) {
    expect(tester.takeException(), isNull, reason: label);
    expect(drawnLines(tester, find.byKey(const ValueKey('eisenhower-page-title'))), 1);
    expect(drawnLines(tester, find.byKey(const ValueKey('eisenhower-page-subtitle'))), 1);
    expectTarget(
      tester,
      find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(IconButton)),
      width,
      '$label BackArrow',
    );
  }

  for (final width in _widths) {
    for (final scale in _scales) {
      final label = '${width.toInt()}px x$scale';

      group('quadrant page $label', () {
        testWidgets('filled: unbroken 255 title, many-word title, long project name', (
          tester,
        ) async {
          await openPage(tester, width, scale, EisenhowerQuadrant.schedule);
          expectFrame(tester, width, label);

          for (final (id, title) in [(21, _unbroken), (22, _manyWords), (2, null)]) {
            final row = find.byKey(ValueKey('eisenhower-page-task-$id'));
            await tester.ensureVisible(row);
            await tester.pump();
            expect(tester.takeException(), isNull, reason: '$label row $id');
            expectTarget(tester, row, width, '$label row $id');
            final titleText = find.descendant(
              of: row,
              matching: title == null ? find.text('Haftalık hedefleri yaz') : find.text(title),
            );
            expect(tester.widget<Text>(titleText).maxLines, 2);
            expect(drawnLines(tester, titleText), lessThanOrEqualTo(2), reason: '$label $id');
            if (title != null) {
              expect(drawnLines(tester, titleText), 2, reason: '$label $id: cut at 2 lines');
            }
          }
          // Meta lines: due day only (22), long project name only (2).
          final dueMeta = find.byKey(const ValueKey('eisenhower-page-meta-22'));
          expect(tester.widget<Text>(dueMeta).data, '25 Kas');
          expect(drawnLines(tester, dueMeta), 1);
          final projectMeta = find.byKey(const ValueKey('eisenhower-page-meta-2'));
          expect(tester.widget<Text>(projectMeta).data, _longWord);
          expect(tester.widget<Text>(projectMeta).maxLines, 2);
          expect(drawnLines(tester, projectMeta), lessThanOrEqualTo(2));
          expect(tester.getRect(projectMeta).right, lessThanOrEqualTo(width));
        });

        testWidgets('empty', (tester) async {
          when(() => taskRepo.getTasksByFilter(any())).thenAnswer(
            (_) async => Right(_worstCase().where((t) => !t.isUrgent || t.isImportant).toList()),
          );
          await openPage(tester, width, scale, EisenhowerQuadrant.delegate);
          expectFrame(tester, width, label);
          final empty = find.text(EisenhowerQuadrantPage.emptyText);
          expect(empty, findsOneWidget);
          expect(tester.getRect(empty).right, lessThanOrEqualTo(width));
        });

        testWidgets('error: message and Tekrar dene', (tester) async {
          const failure = NetworkFailure('timeout');
          when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => const Left(failure));
          await openPage(tester, width, scale, EisenhowerQuadrant.doNow);
          expectFrame(tester, width, label);
          final message = find.text(userMessage(failure));
          expect(message, findsOneWidget);
          expect(tester.getRect(message).right, lessThanOrEqualTo(width));
          expectTarget(
            tester,
            find.byKey(const ValueKey('eisenhower-page-retry')),
            width,
            '$label retry',
          );
        });

        testWidgets('loading (frame by frame, no pumpAndSettle)', (tester) async {
          final pending = Completer<Either<Failure, List<Task>>>();
          addTearDown(() {
            if (!pending.isCompleted) pending.complete(const Right([]));
          });
          when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) => pending.future);
          await openPage(tester, width, scale, EisenhowerQuadrant.eliminate, settle: false);
          expectFrame(tester, width, label);
          expect(find.byKey(const ValueKey('eisenhower-page-loading')), findsOneWidget);
          expect(find.text(EisenhowerQuadrantPage.emptyText), findsNothing);
        });
      });
    }
  }
}
