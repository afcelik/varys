// The Home "Öncelik Matrisi" card on its own (a small router: /home with the
// card, /eisenhower/:quadrant as a marker page). Data: real GET /tasks
// (tasks_eisenhower.json) through a mocked TaskRepository.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/presentation/widgets/eisenhower_card.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/eisenhower.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';

import '../../../helpers/varys_app_harness.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

/// Real GET /tasks: 1 doNow, 2 schedule, 3 delegate, 4 eliminate, 5 done.
List<Task> _fixture() =>
    (jsonDecode(File('test/fixtures/tasks_eisenhower.json').readAsStringSync()) as List)
        .cast<Map<String, dynamic>>()
        .map(Task.fromJson)
        .toList();

const _failure = ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);

final _longWord = 'Ç' * 255; // a title with no break opportunity at all

void main() {
  late _MockTaskRepository repo;
  late List<Task> server;
  late GoRouter router;

  setUpAll(() => registerFallbackValue(TaskFilter.all));

  setUp(() {
    repo = _MockTaskRepository();
    server = _fixture();
    when(() => repo.getTasksByFilter(any())).thenAnswer((inv) async {
      final filter = inv.positionalArguments.first as TaskFilter;
      return Right(switch (filter) {
        TaskFilter.all => server,
        TaskFilter.inProgress => server.where((t) => t.status != TaskStatus.done).toList(),
        TaskFilter.completed => server.where((t) => t.status == TaskStatus.done).toList(),
      });
    });
    when(() => repo.getTasks()).thenAnswer((_) async => Right(server));
  });

  Future<void> pumpCard(WidgetTester tester, {double width = 400, bool settle = true}) async {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.homePath,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(padding: EdgeInsets.all(16), child: EisenhowerCard()),
          ),
        ),
        GoRoute(
          path: AppRouter.eisenhowerRoutePath,
          builder: (_, state) => Scaffold(body: Text('PAGE ${state.pathParameters['quadrant']}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: [taskRepositoryProvider.overrideWith((ref) async => repo)],
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  ProviderContainer container(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(EisenhowerCard)));

  Finder quadrant(EisenhowerQuadrant q) =>
      find.byKey(ValueKey('eisenhower-quadrant-${q.pathSegment}'));
  Finder inQuadrant(EisenhowerQuadrant q, Finder f) =>
      find.descendant(of: quadrant(q), matching: f);
  String count(WidgetTester tester, EisenhowerQuadrant q) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey('eisenhower-count-${q.pathSegment}')),
          matching: find.byType(Text),
        ),
      )
      .data!;
  Map<EisenhowerQuadrant, String> counts(WidgetTester tester) => {
    for (final q in EisenhowerQuadrant.values) q: count(tester, q),
  };

  /// Step 29 method: rendered paragraph height against one line's height.
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

  group('filled', () {
    testWidgets('four quadrants with name, subtitle, count and title; done task not counted', (
      tester,
    ) async {
      await pumpCard(tester);

      expect(find.text(EisenhowerCard.title), findsOneWidget);
      // Distinguishable without colour: every quadrant carries its name as text.
      for (final q in EisenhowerQuadrant.values) {
        expect(inQuadrant(q, find.text(q.title)), findsOneWidget, reason: q.name);
        expect(inQuadrant(q, find.text(q.subtitle)), findsOneWidget, reason: q.name);
      }
      expect(counts(tester), {
        EisenhowerQuadrant.doNow: '1',
        EisenhowerQuadrant.schedule: '1',
        EisenhowerQuadrant.delegate: '1',
        EisenhowerQuadrant.eliminate: '1',
      });
      expect(
        inQuadrant(EisenhowerQuadrant.doNow, find.text('Vergi beyannamesini gönder')),
        findsOneWidget,
      );
      expect(
        inQuadrant(EisenhowerQuadrant.schedule, find.text('Haftalık hedefleri yaz')),
        findsOneWidget,
      );
      expect(
        inQuadrant(EisenhowerQuadrant.delegate, find.text('Kargo görevlisini ara')),
        findsOneWidget,
      );
      expect(
        inQuadrant(EisenhowerQuadrant.eliminate, find.text('Eski e-postaları ayıkla')),
        findsOneWidget,
      );
      expect(find.text('Kira ödemesini yap'), findsNothing, reason: 'done task left out');
      expect(find.text(EisenhowerCard.emptyText), findsNothing);
      expect(find.byKey(const ValueKey('eisenhower-loading')), findsNothing);
    });

    testWidgets('more than 3 tasks: newest 3 titles, then "+N"; count is the full number', (
      tester,
    ) async {
      final base = server.firstWhere((t) => t.id == 1);
      server = [
        for (var i = 0; i < 6; i++)
          base.copyWith(
            id: 100 + i,
            title: 'Acil iş $i',
            createdAt: base.createdAt.add(Duration(minutes: i)),
          ),
        ...server,
      ];
      await pumpCard(tester);

      expect(count(tester, EisenhowerQuadrant.doNow), '7');
      for (final i in [5, 4, 3]) {
        expect(inQuadrant(EisenhowerQuadrant.doNow, find.text('Acil iş $i')), findsOneWidget);
      }
      for (final i in [2, 1, 0]) {
        expect(find.text('Acil iş $i'), findsNothing);
      }
      expect(find.text('Vergi beyannamesini gönder'), findsNothing);
      expect(inQuadrant(EisenhowerQuadrant.doNow, find.text('+4')), findsOneWidget);
      expect(find.byKey(const ValueKey('eisenhower-more-schedule')), findsNothing);
    });

    testWidgets('names and task titles stay on one line (255-char unbroken title)', (tester) async {
      server = [for (final t in server) t.id == 1 ? t.copyWith(title: _longWord) : t];
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCard(tester, width: 360);

      expect(tester.takeException(), isNull);
      final title = find.byKey(const ValueKey('eisenhower-task-1'));
      expect(tester.widget<Text>(title).maxLines, 1);
      expectAtMostLines(tester, title, 1, 'long task title');
      for (final q in EisenhowerQuadrant.values) {
        final name = find.byKey(ValueKey('eisenhower-name-${q.pathSegment}'));
        expect(tester.widget<Text>(name).maxLines, 1);
        expectAtMostLines(tester, name, 1, '${q.name} name');
        expectAtMostLines(
          tester,
          find.byKey(ValueKey('eisenhower-subtitle-${q.pathSegment}')),
          1,
          '${q.name} subtitle',
        );
      }
      expectAtMostLines(tester, find.byKey(const ValueKey('eisenhower-title')), 1, 'card title');
    });

    testWidgets('narrow card: one column; card >= 600 wide: 2x2 grid', (tester) async {
      await pumpCard(tester, width: 400);
      final doNow = tester.getRect(quadrant(EisenhowerQuadrant.doNow));
      final schedule = tester.getRect(quadrant(EisenhowerQuadrant.schedule));
      expect(schedule.top, greaterThan(doNow.bottom), reason: 'stacked');

      await pumpCard(tester, width: 700);
      final r = {for (final q in EisenhowerQuadrant.values) q: tester.getRect(quadrant(q))};
      expect(r[EisenhowerQuadrant.doNow]!.top, r[EisenhowerQuadrant.schedule]!.top);
      expect(r[EisenhowerQuadrant.schedule]!.left, greaterThan(r[EisenhowerQuadrant.doNow]!.right));
      expect(r[EisenhowerQuadrant.delegate]!.top, greaterThan(r[EisenhowerQuadrant.doNow]!.bottom));
      expect(r[EisenhowerQuadrant.delegate]!.top, r[EisenhowerQuadrant.eliminate]!.top);
    });
  });

  group('tap', () {
    for (final q in EisenhowerQuadrant.values) {
      testWidgets('quadrant ${q.name} opens /eisenhower/${q.pathSegment} (push)', (tester) async {
        await pumpCard(tester);
        await tester.tap(quadrant(q));
        await tester.pumpAndSettle();

        expect(find.text('PAGE ${q.pathSegment}'), findsOneWidget);
        expect(router.canPop(), isTrue, reason: 'pushed, Home stays below');
      });
    }

    testWidgets('a tap on a task title inside the quadrant opens the quadrant', (tester) async {
      await pumpCard(tester);
      await tester.tap(find.text('Kargo görevlisini ara'));
      await tester.pumpAndSettle();
      expect(find.text('PAGE delegate'), findsOneWidget);
    });

    testWidgets('every quadrant is one target at least 48x48', (tester) async {
      await pumpCard(tester, width: 360);
      for (final q in EisenhowerQuadrant.values) {
        final size = tester.getSize(quadrant(q));
        expect(size.height, greaterThanOrEqualTo(48), reason: q.name);
        expect(size.width, greaterThanOrEqualTo(48), reason: q.name);
        expect(inQuadrant(q, find.byType(InkWell)), findsNothing, reason: 'no nested target');
      }
    });
  });

  group('states', () {
    testWidgets('no tasks: "Bekleyen görev yok", no quadrants', (tester) async {
      server = [];
      await pumpCard(tester);
      expect(find.text(EisenhowerCard.emptyText), findsOneWidget);
      expect(quadrant(EisenhowerQuadrant.doNow), findsNothing);
    });

    testWidgets('only done tasks: "Bekleyen görev yok"', (tester) async {
      server = server.where((t) => t.status == TaskStatus.done).toList();
      expect(server, isNotEmpty);
      await pumpCard(tester);
      expect(find.text(EisenhowerCard.emptyText), findsOneWidget);
    });

    testWidgets('loading: skeleton only (never the empty text); then filled', (tester) async {
      final gate = Completer<Either<Failure, List<Task>>>();
      when(() => repo.getTasksByFilter(any())).thenAnswer((_) => gate.future);
      await pumpCard(tester, settle: false);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byKey(const ValueKey('eisenhower-loading')), findsOneWidget);
      expect(find.text(EisenhowerCard.emptyText), findsNothing);
      expect(find.byKey(const ValueKey('eisenhower-error')), findsNothing);

      gate.complete(Right(server));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('eisenhower-loading')), findsNothing);
      expect(count(tester, EisenhowerQuadrant.doNow), '1');
    });

    testWidgets('error: userMessage + "Tekrar dene" (48x48); retry loads the card', (tester) async {
      when(() => repo.getTasksByFilter(any())).thenAnswer((_) async => const Left(_failure));
      await pumpCard(tester);

      expect(find.text(userMessage(_failure)), findsOneWidget);
      expect(find.text(EisenhowerCard.emptyText), findsNothing);
      final retry = find.byKey(const ValueKey('eisenhower-retry'));
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(retry).width, greaterThanOrEqualTo(48));

      when(() => repo.getTasksByFilter(any())).thenAnswer((_) async => Right(server));
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('eisenhower-error')), findsNothing);
      expect(count(tester, EisenhowerQuadrant.eliminate), '1');
    });
  });

  group('Planning filter does not affect the card', () {
    for (final filter in [TaskFilter.completed, TaskFilter.inProgress]) {
      testWidgets('filter "${filter.label}": same counts and titles, old content kept meanwhile', (
        tester,
      ) async {
        await pumpCard(tester);
        final before = counts(tester);
        final gate = Completer<Either<Failure, List<Task>>>();
        when(() => repo.getTasks()).thenAnswer((_) => gate.future);

        final c = container(tester);
        unawaited(c.read(taskListNotifierProvider.notifier).changeFilter(filter));
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        // Recomputing: no skeleton, old content still drawn.
        expect(find.byKey(const ValueKey('eisenhower-loading')), findsNothing);
        expect(counts(tester), before);
        expect(find.text('Vergi beyannamesini gönder'), findsOneWidget);

        gate.complete(Right(server));
        await tester.pumpAndSettle();
        expect(c.read(taskListNotifierProvider).requireValue.currentFilter, filter);
        expect(counts(tester), before);
        expect(find.text('Eski e-postaları ayıkla'), findsOneWidget);
        verify(() => repo.getTasks()).called(1);
      });
    }

    testWidgets('filter "Tümü": no unfiltered request at all', (tester) async {
      await pumpCard(tester);
      verifyNever(() => repo.getTasks());
    });
  });
}
