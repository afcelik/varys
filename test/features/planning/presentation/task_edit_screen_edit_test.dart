// Edit mode of the task form (/tasks/edit) through the REAL TaskRepositoryImpl:
// ApiClient is mocked as a small fake server (GET /tasks answers its JSON
// state, PATCH applies the body to it), so every assertion on a body is the
// exact JSON map the app would send.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/planning/presentation/task_list_page.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';

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

/// An answer the fake server gives to the next PATCH instead of applying it.
typedef _PatchError = (int status, Map<String, dynamic> body);

void main() {
  late _MockApiClient api;
  late _MockDailyPlanRepository planRepo;
  late FakeProjectRepository projectRepo;
  late GoRouter router;

  /// Fake server state: task JSON by id, in list order.
  late Map<int, Map<String, dynamic>> server;

  /// Every PATCH: (path, body) exactly as the repository sent it.
  late List<(String, Map<String, dynamic>)> patches;

  /// When set, the next PATCHes answer this error (not applied).
  _PatchError? patchError;

  /// When set, PATCH waits on it before answering.
  Completer<void>? patchGate;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    api = _MockApiClient();
    planRepo = _MockDailyPlanRepository();
    // Real GET /projects: 1, 2 active; 3 on hold; 4 someday; 5 completed.
    projectRepo = FakeProjectRepository();
    patches = [];
    patchError = null;
    patchGate = null;
    // Task 1: real PATCH 200 (project 2 "Kitap okuma listesi", due 25.11,
    // planned 19.11, description). Task 10: real POST 201 plain body.
    server = {
      1: _fixtureJson('task_update_set.json'),
      10: _fixtureJson('task_created_plain.json')..['id'] = 10,
    };

    when(() => api.get<List<dynamic>>(any())).thenAnswer(
      (inv) async => Response(
        requestOptions: RequestOptions(path: inv.positionalArguments.first as String),
        statusCode: 200,
        data: server.values.map((t) => Map<String, dynamic>.from(t)).toList(),
      ),
    );
    when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer((
      inv,
    ) async {
      final path = inv.positionalArguments.first as String;
      final body = Map<String, dynamic>.from(inv.namedArguments[#data] as Map);
      patches.add((path, body));
      final gate = patchGate;
      if (gate != null) await gate.future;
      final options = RequestOptions(path: path);
      final id = int.parse(path.split('/').last);
      final error =
          patchError ??
          (server.containsKey(id) ? null : (404, _fixtureJson('task_update_404.json')));
      if (error != null) {
        throw DioException(
          requestOptions: options,
          response: Response<Map<String, dynamic>>(
            requestOptions: options,
            statusCode: error.$1,
            data: error.$2,
          ),
          type: DioExceptionType.badResponse,
        );
      }
      server[id] = {...server[id]!, ...body};
      return Response(requestOptions: options, statusCode: 200, data: Map.of(server[id]!));
    });
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
  });

  Task serverTask(int id) => Task.fromJson(Map.of(server[id]!));

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Real app root (Turkish delegates) with a small router: Home placeholder,
  /// Planning, and both form routes built like AppRouter's.
  Future<void> pumpApp(
    WidgetTester tester, {
    String initial = AppRouter.planningPath,
    Object? initialExtra,
    Size size = const Size(600, 1400),
    double? textScale,
  }) async {
    setSize(tester, size);
    router = GoRouter(
      initialLocation: initial,
      initialExtra: initialExtra,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.planningPath, builder: (_, _) => const TaskListPage()),
        GoRoute(path: AppRouter.tasksNewPath, builder: (_, _) => const TaskEditScreen()),
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
      textScale: textScale,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        taskRepositoryProvider.overrideWith((ref) async => TaskRepositoryImpl(api)),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ],
    );
    await tester.pumpAndSettle();
  }

  /// Planning first, then the edit form for task [id] pushed on top.
  Future<void> openEdit(
    WidgetTester tester, {
    int id = 1,
    Size size = const Size(600, 1400),
    double? textScale,
    bool settle = true,
  }) async {
    await pumpApp(tester, size: size, textScale: textScale);
    unawaited(router.push(AppRouter.tasksEditPath, extra: serverTask(id)));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
    expect(find.text(TaskEditScreen.editTitle), findsOneWidget);
  }

  final titleField = find.byKey(const ValueKey('task-title'));
  final descriptionField = find.byKey(const ValueKey('task-description'));
  final saveButton = find.byKey(const ValueKey('task-save'));
  final projectMenu = find.byType(DropdownMenu<ProjectChoice>);
  final dueClear = find.byKey(const ValueKey('task-due-date-clear'));
  final plannedButton = find.byKey(const ValueKey('task-planned-date-button'));
  final plannedClear = find.byKey(const ValueKey('task-planned-date-clear'));
  final projectsRetry = find.byKey(const ValueKey('task-projects-retry'));

  String fieldText(WidgetTester tester, Finder field) => tester
      .widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
      .controller
      .text;
  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton).onPressed != null;
  DropdownMenu<ProjectChoice> dropdown(WidgetTester tester) =>
      tester.widget<DropdownMenu<ProjectChoice>>(projectMenu);
  List<String> choiceLabels(WidgetTester tester) =>
      dropdown(tester).dropdownMenuEntries.map((e) => e.label).toList();
  ProjectChoice? shown(WidgetTester tester) => dropdown(tester).initialSelection;
  String dayText(WidgetTester tester, String prefix) =>
      tester.widget<Text>(find.byKey(ValueKey('$prefix-text'))).data!;
  Finder snack(String text) =>
      find.descendant(of: find.byType(SnackBar), matching: find.text(text));
  Map<String, dynamic> lastBody() => patches.last.$2;

  Future<void> selectProject(WidgetTester tester, String label) async {
    await tester.ensureVisible(projectMenu);
    await tester.tap(projectMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, label).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
  }

  Future<void> tapRow(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  group('prefilled form', () {
    testWidgets('every field shows the current value; no status; Kaydet disabled', (tester) async {
      await openEdit(tester);

      expect(fieldText(tester, titleField), 'Giriş ekranını bitir ve test et');
      expect(fieldText(tester, descriptionField), 'Form ve hata mesajları');
      expect(shown(tester)?.id, 2);
      expect(shown(tester)?.label, 'Kitap okuma listesi');
      expect(dayText(tester, 'task-due-date'), '25.11.2026');
      expect(dayText(tester, 'task-planned-date'), '19.11.2026');
      expect(find.text(TaskEditScreen.plannedDateLabel), findsOneWidget);
      expect(find.text('Boş bırakırsan görev günlük listeden çıkar'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing, reason: 'no status in this form');
      expect(find.textContaining('Durum'), findsNothing);
      expect(saveEnabled(tester), isFalse, reason: 'nothing changed yet');
    });

    testWidgets('a change enables Kaydet; changing it back disables it again', (tester) async {
      await openEdit(tester);

      await tester.enterText(titleField, 'Başka');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await tester.enterText(titleField, '  Giriş ekranını bitir ve test et ');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isFalse, reason: 'trimmed value equals the original');

      await selectProject(tester, 'Ev taşıma');
      expect(saveEnabled(tester), isTrue);
      await selectProject(tester, 'Kitap okuma listesi');
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('whitespace-only title: Kaydet disabled, error shown', (tester) async {
      await openEdit(tester);
      await tester.enterText(titleField, '   ');
      await tester.pumpAndSettle();

      expect(saveEnabled(tester), isFalse);
      expect(find.text(taskTitleRequiredMessage), findsOneWidget);
    });

    testWidgets('create mode is unchanged: no planned day field, create title', (tester) async {
      await pumpApp(tester);
      unawaited(router.push(AppRouter.tasksNewPath));
      await tester.pumpAndSettle();

      expect(find.text(TaskEditScreen.createTitle), findsOneWidget);
      expect(plannedButton, findsNothing);
      expect(find.text(TaskEditScreen.plannedDateLabel), findsNothing);
    });
  });

  group('PATCH body carries only the changed field (end to end)', () {
    testWidgets('title only; then Projesiz only; then × due only — reopened from the row', (
      tester,
    ) async {
      await openEdit(tester);

      await tester.enterText(titleField, '  Yeni başlık ');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(patches.single.$1, '/tasks/1');
      expect(lastBody(), {'title': 'Yeni başlık'});
      for (final key in ['project_id', 'description', 'due_date', 'planned_date', 'status']) {
        expect(lastBody().containsKey(key), isFalse, reason: key);
      }
      expect(find.byType(TaskEditScreen), findsNothing, reason: 'back on Planning');

      await tapRow(tester, 'Yeni başlık');
      expect(fieldText(tester, titleField), 'Yeni başlık', reason: 'reopened with server values');
      await selectProject(tester, noProjectLabel);
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(lastBody(), {'project_id': null});
      expect(lastBody().containsKey('project_id'), isTrue);

      await tapRow(tester, 'Yeni başlık');
      await tester.ensureVisible(dueClear);
      await tester.tap(dueClear);
      await tester.pumpAndSettle();
      expect(dayText(tester, 'task-due-date'), TaskEditScreen.noDateText);
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(lastBody(), {'due_date': null});

      expect(patches, hasLength(3));
      for (final (_, body) in patches) {
        expect(() => jsonEncode(body), returnsNormally);
      }
    });

    testWidgets('description emptied → {description: null}; planned day × → {planned_date: null}', (
      tester,
    ) async {
      await openEdit(tester);
      await tester.enterText(descriptionField, '   ');
      await tester.ensureVisible(plannedClear);
      await tester.tap(plannedClear);
      await tester.pumpAndSettle();
      expect(dayText(tester, 'task-planned-date'), TaskEditScreen.noDateText);
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(lastBody(), {'description': null, 'planned_date': null});
    });

    testWidgets('another project and a picked planned day: int id, YYYY-MM-DDT00:00:00', (
      tester,
    ) async {
      await openEdit(tester);
      await selectProject(tester, 'Bahçe düzenlemesi');
      await tester.ensureVisible(plannedButton);
      await tester.tap(plannedButton);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(DatePickerDialog), matching: find.text('21')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(dayText(tester, 'task-planned-date'), '21.11.2026');
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(lastBody(), {'project_id': 3, 'planned_date': '2026-11-21T00:00:00'});
      expect(lastBody()['project_id'], isA<int>());
    });

    testWidgets('double tap on Kaydet sends one request', (tester) async {
      patchGate = Completer<void>();
      await openEdit(tester);
      await tester.enterText(titleField, 'Bir kez');
      await tester.pumpAndSettle();

      await tapSave(tester);
      await tester.pump();
      expect(saveEnabled(tester), isFalse, reason: 'disabled while saving');
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      patchGate!.complete();
      await tester.pumpAndSettle();

      expect(patches, hasLength(1));
    });
  });

  group('project choices in edit mode', () {
    testWidgets("the task's completed project is offered and shown; other completed hidden", (
      tester,
    ) async {
      final completed = projectRepo.server.singleWhere((p) => p.id == 5);
      expect(completed.status, ProjectStatus.completed);
      projectRepo.server = [...projectRepo.server, completed.copyWith(id: 6, title: 'Eski iş')];
      server[1]!['project_id'] = 5;
      await openEdit(tester);

      expect(shown(tester)?.id, 5);
      expect(shown(tester)?.label, 'Vergi beyannamesi');
      expect(shown(tester)?.statusLabel, 'Tamamlanan');
      expect(choiceLabels(tester), contains('Vergi beyannamesi'));
      expect(choiceLabels(tester), isNot(contains('Eski iş')));
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('a task on an active project: completed projects are not offered', (tester) async {
      await openEdit(tester);
      expect(choiceLabels(tester), isNot(contains('Vergi beyannamesi')));
    });

    testWidgets('project deleted (loaded list lacks it): Projesiz, counts as a change', (
      tester,
    ) async {
      server[1]!['project_id'] = 77;
      await openEdit(tester);

      expect(shown(tester), ProjectChoice.none);
      expect(saveEnabled(tester), isTrue, reason: 'the fallback is a change');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(lastBody(), {'project_id': null});
    });

    testWidgets('projects loading: "Mevcut proje", disabled, never Projesiz; project not sent', (
      tester,
    ) async {
      projectRepo.listGate = Completer<void>();
      await openEdit(tester, settle: false);
      await tester.pump(const Duration(milliseconds: 100));

      expect(choiceLabels(tester), [TaskEditScreen.currentProjectLabel]);
      expect(shown(tester)?.id, 2);
      expect(dropdown(tester).enabled, isFalse);
      expect(find.byKey(const ValueKey('task-projects-loading')), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(titleField, 'Yüklenirken');
      await tester.pump();
      expect(saveEnabled(tester), isTrue);
      await tapSave(tester);
      await tester.pump();
      await tester.pump();
      expect(lastBody(), {'title': 'Yüklenirken'}, reason: 'project_id unset while loading');

      projectRepo.listGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('loaded after loading: real name, selection kept, NOT a change', (tester) async {
      projectRepo.listGate = Completer<void>();
      await openEdit(tester, settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(choiceLabels(tester), [TaskEditScreen.currentProjectLabel]);

      projectRepo.listGate!.complete();
      await tester.pumpAndSettle();

      expect(shown(tester)?.label, 'Kitap okuma listesi');
      expect(shown(tester)?.id, 2);
      expect(dropdown(tester).enabled, isTrue);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('load error: "Mevcut proje" + Tekrar dene; after reload the real name, Kaydet '
        'stays disabled', (tester) async {
      projectRepo.listFailure = FakeProjectRepository.notFound;
      await openEdit(tester);

      expect(choiceLabels(tester), [TaskEditScreen.currentProjectLabel]);
      expect(dropdown(tester).enabled, isFalse);
      expect(find.text(TaskEditScreen.projectsErrorText), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      projectRepo.listFailure = null;
      await tester.ensureVisible(projectsRetry);
      await tester.tap(projectsRetry);
      await tester.pumpAndSettle();

      expect(shown(tester)?.label, 'Kitap okuma listesi');
      expect(shown(tester)?.id, 2);
      expect(find.text(TaskEditScreen.projectsErrorText), findsNothing);
      expect(saveEnabled(tester), isFalse, reason: 'loading the name is not a change');
    });

    testWidgets('a task without a project is never pending: Projesiz while loading', (
      tester,
    ) async {
      projectRepo.listGate = Completer<void>();
      await openEdit(tester, id: 10, settle: false);
      await tester.pump(const Duration(milliseconds: 100));

      expect(shown(tester), ProjectChoice.none);
      expect(dropdown(tester).enabled, isTrue);
      expect(saveEnabled(tester), isFalse);
      projectRepo.listGate!.complete();
      await tester.pumpAndSettle();
    });
  });

  group('failures keep the form', () {
    testWidgets('server error: form open, every value kept, snackbar, Kaydet re-enabled', (
      tester,
    ) async {
      patchError = (500, {'detail': 'Internal Server Error'});
      await openEdit(tester);
      await tester.enterText(titleField, 'Değişti');
      await tester.enterText(descriptionField, 'Yeni not');
      await selectProject(tester, 'Ev taşıma');
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(snack('Sunucu hatası. Lütfen daha sonra tekrar deneyin.'), findsOneWidget);
      expect(find.textContaining('Internal'), findsNothing);
      expect(fieldText(tester, titleField), 'Değişti');
      expect(fieldText(tester, descriptionField), 'Yeni not');
      expect(shown(tester)?.label, 'Ev taşıma');
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('task 404 (deleted elsewhere): message, form open; back on Planning the row is '
        'gone', (tester) async {
      await openEdit(tester);
      server.remove(1);
      await tester.enterText(titleField, 'Silinmiş');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(snack('Kaynak bulunamadı.'), findsOneWidget);
      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(fieldText(tester, titleField), 'Silinmiş');
      expect(find.textContaining('Task with id'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(TaskListPage), findsOneWidget);
      expect(find.text('Giriş ekranını bitir ve test et'), findsNothing, reason: 'stale row gone');
      expect(find.text('Market alışverişi'), findsOneWidget);
    });

    testWidgets('project 404: message, form open, choice back to Projesiz, projects reloaded', (
      tester,
    ) async {
      await openEdit(tester);
      final listCallsBefore = projectRepo.listCalls;
      await selectProject(tester, 'Gitar öğrenmek');
      patchError = (404, _fixtureJson('task_update_project_404.json'));
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(lastBody(), {'project_id': 4});
      expect(snack('Seçilen proje bulunamadı.'), findsOneWidget);
      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(shown(tester), ProjectChoice.none);
      expect(projectRepo.listCalls, greaterThan(listCallsBefore), reason: 'list reloaded');
      expect(saveEnabled(tester), isTrue, reason: 'Projesiz differs from project 2');
    });
  });

  group('keyboard open (narrow screen)', () {
    testWidgets('360px x1.5 with a 300px keyboard: Kaydet above the keyboard and tappable; '
        'the error snackbar does not cover it', (tester) async {
      patchError = (500, {'detail': 'x'});
      await openEdit(tester, size: const Size(360, 640), textScale: 1.5);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(titleField, 'Klavye');
      await tester.enterText(descriptionField, 'Uzun bir açıklama ' * 6);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(saveButton).bottom, lessThanOrEqualTo(640 - 300));
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(patches, hasLength(1));
      final snackRect = tester.getRect(find.byType(SnackBar));
      final saveRect = tester.getRect(saveButton);
      expect(snackRect.bottom, lessThanOrEqualTo(saveRect.top), reason: 'snackbar above Kaydet');
      expect(saveEnabled(tester), isTrue);

      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      expect(patches, hasLength(2), reason: 'Kaydet still hit-testable with the snackbar');
      expect(tester.takeException(), isNull);
    });
  });

  group('page closed while saving', () {
    testWidgets('Planning below: close during the request, no exception, row updated', (
      tester,
    ) async {
      patchGate = Completer<void>();
      await openEdit(tester);
      await tester.enterText(titleField, 'Kapatırken');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.byType(TaskListPage), findsOneWidget);

      patchGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TaskListPage), findsOneWidget, reason: 'no extra pop');
      expect(find.text('Kapatırken'), findsOneWidget, reason: 'list still updated');
    });

    testWidgets('opened with a Task and nothing below: close during the request, no exception', (
      tester,
    ) async {
      patchGate = Completer<void>();
      await pumpApp(tester, initial: AppRouter.tasksEditPath, initialExtra: serverTask(1));
      expect(find.byType(TaskListPage), findsNothing);
      expect(router.canPop(), isFalse);
      await tester.enterText(titleField, 'Doğrudan');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();

      router.go(AppRouter.homePath);
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      patchGate!.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HOME'), findsOneWidget);
      expect(serverTask(1).title, 'Doğrudan', reason: 'the request still finished');
    });

    testWidgets('/tasks/edit opened directly without a Task: error page, no form', (tester) async {
      await pumpApp(tester, initial: AppRouter.tasksEditPath);
      expect(find.text(TaskEditUnavailablePage.message), findsOneWidget);
      expect(find.byType(TaskEditScreen), findsNothing);
      expect(patches, isEmpty);
    });
  });
}
