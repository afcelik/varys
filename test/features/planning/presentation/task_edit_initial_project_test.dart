// Task create form opened with an initial project (`/tasks/new` with
// TaskNewArgs, e.g. "Görev ekle" on the project detail page): that project
// starts chosen, a completed project is kept as a choice, a deleted (not
// found) project falls back to "Projesiz" with no message. The request body
// is checked through the real repository.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/core/network/api_client.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/planning/presentation/task_new_args.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../projects/fake_project_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

Map<String, dynamic> _fixtureJson(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

void main() {
  late _MockApiClient api;
  late _MockDailyPlanRepository planRepo;
  late FakeProjectRepository projectRepo;
  late List<Map<String, dynamic>> posted;
  late GoRouter router;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    api = _MockApiClient();
    planRepo = _MockDailyPlanRepository();
    // Real GET /projects: 1 "Ev taşıma" and 2 active, 3 on hold, 4 someday,
    // 5 "Vergi beyannamesi" completed.
    projectRepo = FakeProjectRepository();
    posted = [];
    when(() => api.get<List<dynamic>>(any())).thenAnswer(
      (inv) async => Response(
        requestOptions: RequestOptions(path: inv.positionalArguments.first as String),
        statusCode: 200,
        data: const <dynamic>[],
      ),
    );
    when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer((
      inv,
    ) async {
      posted.add(inv.namedArguments[#data] as Map<String, dynamic>);
      return Response(
        requestOptions: RequestOptions(path: inv.positionalArguments.first as String),
        statusCode: 201,
        data: _fixtureJson('task_created_with_project.json'),
      );
    });
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
  });

  /// Home placeholder with the form pushed on top with [args] as extra.
  Future<void> openForm(WidgetTester tester, Object? args, {bool settle = true}) async {
    tester.view.physicalSize = const Size(600, 1400);
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
          path: AppRouter.tasksNewPath,
          builder: (_, state) =>
              TaskEditScreen(initialProjectId: (state.extra as TaskNewArgs?)?.projectId),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        taskRepositoryProvider.overrideWith((ref) async => TaskRepositoryImpl(api)),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ],
    );
    await tester.pumpAndSettle();
    unawaited(router.push(AppRouter.tasksNewPath, extra: args));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
    expect(find.text(TaskEditScreen.createTitle), findsOneWidget);
  }

  final titleField = find.byKey(const ValueKey('task-title'));
  final saveButton = find.byKey(const ValueKey('task-save'));
  final projectMenu = find.byType(DropdownMenu<ProjectChoice>);

  DropdownMenu<ProjectChoice> dropdown(WidgetTester tester) =>
      tester.widget<DropdownMenu<ProjectChoice>>(projectMenu);
  List<String> choiceLabels(WidgetTester tester) =>
      dropdown(tester).dropdownMenuEntries.map((e) => e.label).toList();
  ProjectChoice? shown(WidgetTester tester) => dropdown(tester).initialSelection;

  Future<void> save(WidgetTester tester, String title) async {
    await tester.enterText(titleField, title);
    await tester.pump();
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  testWidgets('active project: chosen when the form opens; project_id sent', (tester) async {
    await openForm(tester, const TaskNewArgs(projectId: 1));

    expect(shown(tester)?.id, 1);
    expect(shown(tester)?.label, 'Ev taşıma');
    expect(choiceLabels(tester), isNot(contains('Vergi beyannamesi')));

    await save(tester, 'Kutuları al');
    expect(posted.single, {'title': 'Kutuları al', 'project_id': 1});
    expect(find.byType(TaskEditScreen), findsNothing, reason: 'saved and left');
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('completed project: kept as a choice and chosen (not Projesiz); project_id sent', (
    tester,
  ) async {
    await openForm(tester, const TaskNewArgs(projectId: 5));

    expect(choiceLabels(tester), contains('Vergi beyannamesi'));
    expect(shown(tester)?.id, 5);
    expect(shown(tester)?.label, 'Vergi beyannamesi');

    await save(tester, 'Makbuzları topla');
    expect(posted.single, {'title': 'Makbuzları topla', 'project_id': 5});
  });

  testWidgets('deleted (not found) project: Projesiz, no message; no project_id sent', (
    tester,
  ) async {
    await openForm(tester, const TaskNewArgs(projectId: 999));

    expect(shown(tester), ProjectChoice.none);
    expect(find.byType(SnackBar), findsNothing);
    expect(choiceLabels(tester).first, 'Projesiz');
    expect(choiceLabels(tester), hasLength(5), reason: 'no extra entry for the missing id');

    await save(tester, 'Sahipsiz');
    expect(posted.single, {'title': 'Sahipsiz'});
  });

  testWidgets('projects still loading: Projesiz shown; once loaded the project is chosen', (
    tester,
  ) async {
    projectRepo.listGate = Completer<void>();
    await openForm(tester, const TaskNewArgs(projectId: 3), settle: false);
    expect(choiceLabels(tester), ['Projesiz']);

    projectRepo.listGate!.complete();
    await tester.pumpAndSettle();
    expect(shown(tester)?.id, 3);
    expect(shown(tester)?.label, 'Bahçe düzenlemesi');

    await save(tester, 'Tohum ek');
    expect(posted.single, {'title': 'Tohum ek', 'project_id': 3});
  });

  testWidgets('no args: Projesiz as before; completed project not offered', (tester) async {
    await openForm(tester, null);

    expect(shown(tester), ProjectChoice.none);
    expect(choiceLabels(tester), isNot(contains('Vergi beyannamesi')));

    await save(tester, 'Düz görev');
    expect(posted.single, {'title': 'Düz görev'});
  });
}
