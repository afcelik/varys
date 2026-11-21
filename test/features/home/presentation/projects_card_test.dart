// ProjectsCard widget tests: real ActiveProjectsNotifier, fake repository
// returning real Either values; projects from real backend JSON
// (test/fixtures/projects_list.json, projects_limits.json). Active projects in
// the fixture: 1 "Ev taşıma" 1/4 done (25%), target 2026-11-20; 2 "Kitap
// okuma listesi" no tasks (progress null), no dates.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/presentation/widgets/projects_card.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/projects/presentation/active_projects_notifier.dart';

class _MockProjectRepository extends Mock implements ProjectRepository {}

const _serverError =
    ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);

void main() {
  late List<Project> all;
  late List<Project> active;
  late ProjectLimits limits;
  late _MockProjectRepository repo;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(ProjectStatus.active);
    all = (jsonDecode(File('test/fixtures/projects_list.json').readAsStringSync()) as List)
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .toList();
    active = all.where((p) => p.status == ProjectStatus.active).toList();
    limits = ProjectLimits.fromJson(
        jsonDecode(File('test/fixtures/projects_limits.json').readAsStringSync())
            as Map<String, dynamic>);
  });

  setUp(() {
    repo = _MockProjectRepository();
    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => Right(active));
    when(() => repo.getLimits()).thenAnswer((_) async => Right(limits));
  });

  Project byId(int id) => all.firstWhere((p) => p.id == id);

  Future<void> pumpCard(WidgetTester tester, {bool settle = true}) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(padding: EdgeInsets.all(16), child: ProjectsCard()),
          ),
        ),
        GoRoute(
          path: AppRouter.projectsPath,
          builder: (_, _) => const Scaffold(body: Text('projects-page')),
        ),
        GoRoute(
          path: AppRouter.projectDetailPath,
          builder: (_, state) => Scaffold(body: Text('detail-${(state.extra! as Project).id}')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [projectRepositoryProvider.overrideWith((ref) async => repo)],
      child: MaterialApp.router(routerConfig: router),
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Finder row(int id) => find.byKey(ValueKey('project-$id'));
  Finder inRow(int id, Finder f) => find.descendant(of: row(id), matching: f);
  LinearProgressIndicator bar(WidgetTester tester, int id) =>
      tester.widget<LinearProgressIndicator>(inRow(id, find.byType(LinearProgressIndicator)));

  void expectTapTarget(WidgetTester tester, Finder button) {
    expect(button, findsOneWidget);
    final size = tester.getSize(button);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  }

  testWidgets('filled: title, counter "Aktif 2/3", one row per active project', (tester) async {
    await pumpCard(tester);

    expect(find.text(ProjectsCard.title), findsOneWidget);
    expect(find.text('Aktif 2/3'), findsOneWidget);
    expect(inRow(1, find.text('Ev taşıma')), findsOneWidget);
    expect(inRow(2, find.text('Kitap okuma listesi')), findsOneWidget);
    expect(find.text('Vergi beyannamesi'), findsNothing); // completed, not in the active list
    expect(find.byKey(const ValueKey('projects-skeleton')), findsNothing);
    verify(() => repo.getProjects(status: ProjectStatus.active)).called(1);
  });

  testWidgets('1 of 4 done: bar at 25% with "%25" beside it, target "20 Kas"', (tester) async {
    await pumpCard(tester);

    expect(bar(tester, 1).value, 0.25);
    expect(inRow(1, find.text('%25')), findsOneWidget);
    expect(inRow(1, find.text('20 Kas')), findsOneWidget);
    expect(inRow(1, find.text(ProjectsCard.noTasksText)), findsNothing);
  });

  testWidgets('project with no tasks (progress null): "Henüz görev yok", no bar, no percent',
      (tester) async {
    await pumpCard(tester);

    expect(inRow(2, find.text(ProjectsCard.noTasksText)), findsOneWidget);
    expect(inRow(2, find.byType(LinearProgressIndicator)), findsNothing);
    expect(inRow(2, find.textContaining('%')), findsNothing);
    expect(inRow(2, find.byKey(const ValueKey('project-target-2'))), findsNothing); // no date
  });

  testWidgets('progress 0: empty bar and "%0" (not "Henüz görev yok")', (tester) async {
    final zero = byId(1).copyWith(doneTasks: 0, progressPercent: 0);
    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => Right([zero]));
    await pumpCard(tester);

    expect(bar(tester, 1).value, 0);
    expect(inRow(1, find.text('%0')), findsOneWidget);
    expect(find.text(ProjectsCard.noTasksText), findsNothing);
  });

  testWidgets('all tasks done: full bar and "%100"', (tester) async {
    final done = byId(5).copyWith(status: ProjectStatus.active);
    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => Right([done]));
    await pumpCard(tester);

    expect(bar(tester, 5).value, 1.0);
    expect(inRow(5, find.text('%100')), findsOneWidget);
    expect(inRow(5, find.text('31 Eki')), findsOneWidget);
  });

  testWidgets('bar sits on its own line below the title, percent beside the bar',
      (tester) async {
    await pumpCard(tester);

    final title = tester.getRect(inRow(1, find.text('Ev taşıma')));
    final barRect = tester.getRect(inRow(1, find.byType(LinearProgressIndicator)));
    final percent = tester.getRect(inRow(1, find.text('%25')));
    expect(barRect.top, greaterThanOrEqualTo(title.bottom));
    expect(percent.top, greaterThanOrEqualTo(title.bottom));
    expect(percent.left, greaterThan(barRect.right));
  });

  testWidgets('long title is limited to two lines with ellipsis', (tester) async {
    final long = byId(1).copyWith(title: 'Çok uzun proje başlığı ' * 20);
    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => Right([long]));
    await pumpCard(tester);

    final text = tester.widget<Text>(inRow(1, find.text(long.title)));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty: "Aktif proje yok" and the counter "Aktif 0/3"', (tester) async {
    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => const Right([]));
    when(() => repo.getLimits()).thenAnswer((_) async => Right(limits.copyWith(activeCount: 0)));
    await pumpCard(tester);

    expect(find.text(ProjectsCard.emptyText), findsOneWidget);
    expect(find.text('Aktif 0/3'), findsOneWidget);
  });

  testWidgets('loading: skeleton, no counter, "Daha fazla" still there', (tester) async {
    final pending = Completer<Either<Failure, List<Project>>>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(const Right([]));
    });
    when(() => repo.getProjects(status: any(named: 'status'))).thenAnswer((_) => pending.future);
    await pumpCard(tester, settle: false);
    await tester.pump();

    expect(find.byKey(const ValueKey('projects-skeleton')), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Aktif \d+/\d+$')), findsNothing);
    expect(find.text(ProjectsCard.moreText), findsOneWidget);
  });

  testWidgets('error: userMessage + "Tekrar dene" (48x48); retry reloads the card',
      (tester) async {
    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => const Left(_serverError));
    await pumpCard(tester);

    expect(find.text(userMessage(_serverError)), findsOneWidget);
    expect(find.textContaining('Instance of'), findsNothing);
    final retry =
        find.ancestor(of: find.text(ProjectsCard.retryText), matching: find.byType(OutlinedButton));
    expectTapTarget(tester, retry);

    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => Right(active));
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.text(userMessage(_serverError)), findsNothing);
    expect(find.text('Aktif 2/3'), findsOneWidget);
    verify(() => repo.getProjects(status: ProjectStatus.active)).called(2);
    verify(() => repo.getLimits()).called(2);
  });

  testWidgets('limits error alone also shows the card error', (tester) async {
    const failure = NetworkFailure('timeout');
    when(() => repo.getLimits()).thenAnswer((_) async => const Left(failure));
    await pumpCard(tester);

    expect(find.text(userMessage(failure)), findsOneWidget);
    expect(find.text(ProjectsCard.retryText), findsOneWidget);
    expect(row(1), findsNothing);
  });

  testWidgets('refresh keeps the old rows on screen (no skeleton flash)', (tester) async {
    await pumpCard(tester);
    final pending = Completer<Either<Failure, List<Project>>>();
    addTearDown(() {
      if (!pending.isCompleted) pending.complete(const Right([]));
    });
    when(() => repo.getProjects(status: any(named: 'status'))).thenAnswer((_) => pending.future);

    final container = ProviderScope.containerOf(tester.element(find.byType(ProjectsCard)));
    container.invalidate(activeProjectsProvider);
    await tester.pump();

    expect(find.byKey(const ValueKey('projects-skeleton')), findsNothing);
    expect(inRow(1, find.text('Ev taşıma')), findsOneWidget);
    expect(find.text('Aktif 2/3'), findsOneWidget);
  });

  testWidgets('"Daha fazla" is a 48x48 target and pushes /projects', (tester) async {
    await pumpCard(tester);

    final more =
        find.ancestor(of: find.text(ProjectsCard.moreText), matching: find.byType(TextButton));
    expectTapTarget(tester, more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('projects-page'), findsOneWidget);
  });

  for (final id in [1, 2]) {
    testWidgets('tapping project row $id pushes the detail page with that project; the row is '
        'at least 48 high', (tester) async {
      await pumpCard(tester);
      expect(tester.getSize(row(id)).height, greaterThanOrEqualTo(48));
      final ink = find.descendant(of: row(id), matching: find.byType(InkWell)).first;
      expect(tester.getSize(ink).height, greaterThanOrEqualTo(48));

      await tester.tap(inRow(id, find.text(byId(id).title)));
      await tester.pumpAndSettle();
      expect(find.text('detail-$id'), findsOneWidget);
      expect(find.text('projects-page'), findsNothing);
    });
  }
}
