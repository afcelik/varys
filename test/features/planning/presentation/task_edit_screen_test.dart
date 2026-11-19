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
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
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

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockApiClient extends Mock implements ApiClient {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

typedef _TaskResult = Either<Failure, Task>;

Map<String, dynamic> _fixtureJson(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

/// Real POST /tasks 201: id 1, project 1, due 2026-11-21.
Task _createdWithProject() => Task.fromJson(_fixtureJson('task_created_with_project.json'));

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);
const _projectGone = ServerFailure('Seçilen proje bulunamadı.', statusCode: 404);

void main() {
  late _MockTaskRepository taskRepo;
  late _MockDailyPlanRepository planRepo;
  late FakeProjectRepository projectRepo;
  late GoRouter router;

  /// The fake server's task list: GET answers it, a successful create adds
  /// to it (so the silent refresh after a create sees the new task).
  late List<Task> serverTasks;

  final existing = Task(
    id: 10,
    title: 'Görev A',
    status: TaskStatus.todo,
    createdAt: DateTime(2026, 11, 1),
    updatedAt: DateTime(2026, 11, 1),
  );

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(existing);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    taskRepo = _MockTaskRepository();
    planRepo = _MockDailyPlanRepository();
    // Real GET /projects: 1, 2 active; 3 on hold; 4 someday; 5 completed.
    projectRepo = FakeProjectRepository();
    serverTasks = [existing];
    when(
      () => taskRepo.getTasksByFilter(any()),
    ).thenAnswer((_) async => Right(List.of(serverTasks)));
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
  });

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Real app root (Turkish delegates) with a small router: Planning, the
  /// form and a Home placeholder. [initial] is where the app starts.
  Future<void> pumpApp(
    WidgetTester tester, {
    String initial = AppRouter.planningPath,
    Size size = const Size(600, 1400),
    double? textScale,
    TaskRepository? taskRepository,
    bool settle = true,
  }) async {
    setSize(tester, size);
    router = GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.planningPath, builder: (_, _) => const TaskListPage()),
        GoRoute(path: AppRouter.tasksNewPath, builder: (_, _) => const TaskEditScreen()),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      textScale: textScale,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        taskRepositoryProvider.overrideWith((ref) async => taskRepository ?? taskRepo),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ],
    );
    if (settle) await tester.pumpAndSettle();
  }

  /// The server creates [task]: it joins the server list and is returned.
  Future<_TaskResult> created(Task task) async {
    serverTasks = [task, ...serverTasks];
    return Right(task);
  }

  /// Planning first, then the form pushed on top (the normal flow).
  Future<void> openForm(
    WidgetTester tester, {
    Size size = const Size(600, 1400),
    double? textScale,
    TaskRepository? taskRepository,
  }) async {
    await pumpApp(tester, size: size, textScale: textScale, taskRepository: taskRepository);
    router.push(AppRouter.tasksNewPath);
    await tester.pumpAndSettle();
    expect(find.text(TaskEditScreen.createTitle), findsOneWidget);
  }

  final titleField = find.byKey(const ValueKey('task-title'));
  final descriptionField = find.byKey(const ValueKey('task-description'));
  final saveButton = find.byKey(const ValueKey('task-save'));
  final projectMenu = find.byType(DropdownMenu<ProjectChoice>);
  final dueButton = find.byKey(const ValueKey('task-due-date-button'));
  final dueClear = find.byKey(const ValueKey('task-due-date-clear'));

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
  int? shownProjectId(WidgetTester tester) => dropdown(tester).initialSelection?.id;
  String dueText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('task-due-date-text'))).data!;
  Finder snack(String text) =>
      find.descendant(of: find.byType(SnackBar), matching: find.text(text));
  Task sentTask() => verify(() => taskRepo.createTask(captureAny())).captured.last as Task;

  Future<void> selectProject(WidgetTester tester, String label) async {
    await tester.ensureVisible(projectMenu);
    await tester.tap(projectMenu);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, label).last);
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    await tester.ensureVisible(dueButton);
    await tester.tap(dueButton);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  }

  Future<void> tapDay(WidgetTester tester, int day) async {
    await tester.tap(
      find.descendant(of: find.byType(DatePickerDialog), matching: find.text('$day')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickDay(WidgetTester tester, int day) async {
    await openPicker(tester);
    await tapDay(tester, day);
    await tester.tap(find.text('Tamam'));
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
  }

  group('validation and Kaydet', () {
    testWidgets('empty title: Kaydet disabled, no error until edited; whitespace → required', (
      tester,
    ) async {
      await openForm(tester);
      expect(saveEnabled(tester), isFalse);
      expect(find.text(taskTitleRequiredMessage), findsNothing);

      await tester.enterText(titleField, '   ');
      await tester.pumpAndSettle();
      expect(find.text(taskTitleRequiredMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(titleField, 'İş');
      await tester.pumpAndSettle();
      expect(find.text(taskTitleRequiredMessage), findsNothing);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('title 255 ok, 256 too long; 255 emoji ok (counted as characters)', (tester) async {
      await openForm(tester);
      await tester.enterText(titleField, 'a' * 256);
      await tester.pumpAndSettle();
      expect(find.text(taskTitleTooLongMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(titleField, 'a' * 255);
      await tester.pumpAndSettle();
      expect(find.text(taskTitleTooLongMessage), findsNothing);
      expect(saveEnabled(tester), isTrue);

      await tester.enterText(titleField, '🚀' * 255);
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('description over 2000 characters: error and Kaydet disabled', (tester) async {
      await openForm(tester);
      await tester.enterText(titleField, 'İş');
      await tester.enterText(descriptionField, 'b' * 2001);
      await tester.pumpAndSettle();
      expect(find.text(taskDescriptionTooLongMessage), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.enterText(descriptionField, 'b' * 2000);
      await tester.pumpAndSettle();
      expect(find.text(taskDescriptionTooLongMessage), findsNothing);
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('Kaydet disabled while the request runs; double tap sends one request', (
      tester,
    ) async {
      final pending = Completer<_TaskResult>();
      when(() => taskRepo.createTask(any())).thenAnswer((_) => pending.future);
      await openForm(tester);
      await tester.enterText(titleField, 'İş');
      await tester.pumpAndSettle();

      await tapSave(tester);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      expect(saveEnabled(tester), isFalse);
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();

      pending.complete(Right(_createdWithProject()));
      await tester.pumpAndSettle();
      verify(() => taskRepo.createTask(any())).called(1);
    });
  });

  group('project choice', () {
    testWidgets('Projesiz first and selected; active/on hold/someday offered; completed hidden', (
      tester,
    ) async {
      await openForm(tester);

      expect(choiceLabels(tester), [
        'Projesiz',
        'Ev taşıma',
        'Kitap okuma listesi',
        'Bahçe düzenlemesi',
        'Gitar öğrenmek',
      ]);
      expect(choiceLabels(tester), isNot(contains('Vergi beyannamesi')));
      expect(shownProjectId(tester), isNull);
      expect(dropdown(tester).initialSelection, ProjectChoice.none);

      await tester.tap(projectMenu);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Beklemede'), findsOneWidget);
      expect(find.widgetWithText(MenuItemButton, 'İleride'), findsOneWidget);
    });

    testWidgets('chosen project is sent; switching back to Projesiz sends none', (tester) async {
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(_createdWithProject()));
      await openForm(tester);
      await tester.enterText(titleField, 'İş');
      await selectProject(tester, 'Gitar öğrenmek');
      expect(shownProjectId(tester), 4);
      await selectProject(tester, 'Bahçe düzenlemesi');
      expect(shownProjectId(tester), 3);

      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(sentTask().projectId, 3);

      router.push(AppRouter.tasksNewPath);
      await tester.pumpAndSettle();
      await tester.enterText(titleField, 'İş 2');
      await selectProject(tester, 'Ev taşıma');
      await selectProject(tester, 'Projesiz');
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(sentTask().projectId, isNull);
    });

    testWidgets('projects still loading: only Projesiz, Kaydet enabled, saves with Projesiz', (
      tester,
    ) async {
      projectRepo.listGate = Completer<void>();
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(_createdWithProject()));
      // The progress bar animates while the projects load: pump, not settle.
      await pumpApp(tester, initial: AppRouter.tasksNewPath, settle: false);
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('task-projects-loading')), findsOneWidget);
      expect(choiceLabels(tester), ['Projesiz']);
      await tester.enterText(titleField, 'Yükleme sırasında');
      await tester.pump();
      expect(saveEnabled(tester), isTrue, reason: 'the project is optional');

      await tapSave(tester);
      await tester.pumpAndSettle();
      final sent = sentTask();
      expect(sent.title, 'Yükleme sırasında');
      expect(sent.projectId, isNull);
      expect(find.byType(TaskEditScreen), findsNothing, reason: 'saved and left');
      projectRepo.listGate!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('projects failed to load: note + Tekrar dene (48x48); the task is still created', (
      tester,
    ) async {
      projectRepo.listFailure = const NetworkFailure('Sunucuya bağlanılamıyor');
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(_createdWithProject()));
      await pumpApp(tester, initial: AppRouter.tasksNewPath);

      expect(find.text('Projeler yüklenemedi'), findsOneWidget);
      final retry = find.byKey(const ValueKey('task-projects-retry'));
      expect(retry, findsOneWidget);
      expect(tester.getSize(retry).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      expect(choiceLabels(tester), ['Projesiz']);

      await tester.enterText(titleField, 'Yine de');
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(sentTask().projectId, isNull);
      expect(find.byType(TaskEditScreen), findsNothing);
    });

    testWidgets('Tekrar dene reloads the projects, values kept', (tester) async {
      projectRepo.listFailure = const NetworkFailure('Sunucuya bağlanılamıyor');
      await pumpApp(tester, initial: AppRouter.tasksNewPath);
      await tester.enterText(titleField, 'Bekleyen');
      await tester.pumpAndSettle();

      projectRepo.listFailure = null;
      await tester.tap(find.byKey(const ValueKey('task-projects-retry')));
      await tester.pumpAndSettle();

      expect(find.text('Projeler yüklenemedi'), findsNothing);
      expect(choiceLabels(tester), hasLength(5));
      expect(fieldText(tester, titleField), 'Bekleyen');
    });
  });

  group('due date', () {
    testWidgets('picker: 2000-01-01..2100-12-31, starts on today; pick → shown and sent as day', (
      tester,
    ) async {
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(_createdWithProject()));
      await openForm(tester);
      await tester.enterText(titleField, 'İş');
      expect(dueText(tester), TaskEditScreen.noDateText);

      await openPicker(tester);
      final picker = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.firstDate, DateTime(2000, 1, 1));
      expect(picker.lastDate, DateTime(2100, 12, 31));
      expect(picker.initialDate, _day);
      await tapDay(tester, 21);
      await tester.tap(find.text('Tamam'));
      await tester.pumpAndSettle();
      expect(dueText(tester), '21.11.2026');

      await tapSave(tester);
      await tester.pumpAndSettle();
      final sent = sentTask();
      expect(sent.dueDate, DateTime(2026, 11, 21));
      expect(sent.plannedDate, isNull, reason: 'planned_date is Home\'s');
    });

    testWidgets('× (48x48) clears the date; nothing is sent', (tester) async {
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(_createdWithProject()));
      await openForm(tester);
      await tester.enterText(titleField, 'İş');
      expect(dueClear, findsNothing);
      await pickDay(tester, 21);

      expect(tester.getSize(dueClear).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(dueClear).height, greaterThanOrEqualTo(48));
      await tester.tap(dueClear);
      await tester.pumpAndSettle();
      expect(dueText(tester), TaskEditScreen.noDateText);

      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(sentTask().dueDate, isNull);
    });

    testWidgets('picker closed with İptal keeps every value (title, description, project, date)', (
      tester,
    ) async {
      await openForm(tester);
      await tester.enterText(titleField, 'Başlık');
      await tester.enterText(descriptionField, 'Açıklama metni');
      await selectProject(tester, 'Kitap okuma listesi');

      // First open with no date: İptal leaves it empty.
      await openPicker(tester);
      expect(find.text('Cancel'), findsNothing, reason: 'Turkish delegates');
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(dueText(tester), TaskEditScreen.noDateText);

      await pickDay(tester, 21);
      // Re-open, tap another day, then İptal: the old date stays.
      await openPicker(tester);
      await tapDay(tester, 25);
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();

      expect(find.byType(DatePickerDialog), findsNothing);
      expect(dueText(tester), '21.11.2026');
      expect(fieldText(tester, titleField), 'Başlık');
      expect(fieldText(tester, descriptionField), 'Açıklama metni');
      expect(shownProjectId(tester), 2);
      expect(saveEnabled(tester), isTrue);
    });
  });

  group('server answers', () {
    testWidgets('success: pops back to Planning; the new task shows with its project and date', (
      tester,
    ) async {
      when(() => taskRepo.createTask(any())).thenAnswer((_) => created(_createdWithProject()));
      await openForm(tester);
      await tester.enterText(titleField, '  Giriş ekranını bitir  ');
      await tester.enterText(descriptionField, 'Form ve hata mesajları');
      await selectProject(tester, 'Ev taşıma');
      await pickDay(tester, 21);
      await tapSave(tester);
      await tester.pumpAndSettle();

      final sent = sentTask();
      expect(sent.title, 'Giriş ekranını bitir');
      expect(sent.description, 'Form ve hata mesajları');
      expect(sent.projectId, 1);
      expect(sent.dueDate, DateTime(2026, 11, 21));
      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.byType(TaskListPage), findsOneWidget);
      expect(find.text('Giriş ekranını bitir'), findsOneWidget);
      expect(find.text('Ev taşıma · 21 Kas'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('success with nothing to pop (/tasks/new opened directly): goes to Planning', (
      tester,
    ) async {
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(_createdWithProject()));
      await pumpApp(tester, initial: AppRouter.tasksNewPath);
      expect(router.canPop(), isFalse);
      await tester.enterText(titleField, 'Doğrudan');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsNothing);
      expect(router.routerDelegate.currentConfiguration.uri.path, AppRouter.planningPath);
      expect(find.byType(TaskListPage), findsOneWidget);
    });

    testWidgets('server error: form open, every value kept, snackbar, Kaydet re-enabled', (
      tester,
    ) async {
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => const Left(_serverError));
      await openForm(tester);
      final listCallsBefore = projectRepo.listCalls;
      await tester.enterText(titleField, 'Kalıcı');
      await tester.enterText(descriptionField, 'Not');
      await selectProject(tester, 'Ev taşıma');
      await pickDay(tester, 21);
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(snack('Sunucu hatası. Lütfen daha sonra tekrar deneyin.'), findsOneWidget);
      expect(fieldText(tester, titleField), 'Kalıcı');
      expect(fieldText(tester, descriptionField), 'Not');
      expect(shownProjectId(tester), 1, reason: 'a non-404 error keeps the project');
      expect(dueText(tester), '21.11.2026');
      expect(saveEnabled(tester), isTrue);
      expect(projectRepo.listCalls, listCallsBefore, reason: 'no project reload');
    });

    testWidgets('project 404 (deleted elsewhere): form open, choice back to Projesiz, list '
        'reloaded silently, message; saving again sends no project', (tester) async {
      await openForm(tester);
      await tester.enterText(titleField, 'Bahçe işi');
      await tester.enterText(descriptionField, 'Çit');
      await selectProject(tester, 'Bahçe düzenlemesi');
      await pickDay(tester, 21);
      // Deleted on another device, after the form loaded the list.
      projectRepo.server = projectRepo.server.where((p) => p.id != 3).toList();
      final listCallsBefore = projectRepo.listCalls;
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => const Left(_projectGone));

      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(snack('Seçilen proje bulunamadı.'), findsOneWidget);
      expect(shownProjectId(tester), isNull);
      expect(dropdown(tester).initialSelection, ProjectChoice.none);
      expect(projectRepo.listCalls, listCallsBefore + 1);
      expect(choiceLabels(tester), isNot(contains('Bahçe düzenlemesi')));
      expect(find.byKey(const ValueKey('task-projects-loading')), findsNothing, reason: 'silent');
      expect(fieldText(tester, titleField), 'Bahçe işi');
      expect(fieldText(tester, descriptionField), 'Çit');
      expect(dueText(tester), '21.11.2026');
      expect(saveEnabled(tester), isTrue);

      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(_createdWithProject()));
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(sentTask().projectId, isNull);
    });
  });

  group('request body through the real repository', () {
    late _MockApiClient api;
    late List<Map<String, dynamic>> posted;

    setUp(() {
      api = _MockApiClient();
      posted = [];
      when(() => api.get<List<dynamic>>(any())).thenAnswer(
        (inv) async => Response(
          requestOptions: RequestOptions(path: inv.positionalArguments.first as String),
          statusCode: 200,
          data: const <dynamic>[],
        ),
      );
    });

    void answerPost(String fixture) {
      when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer((
        inv,
      ) async {
        posted.add(inv.namedArguments[#data] as Map<String, dynamic>);
        return Response(
          requestOptions: RequestOptions(path: inv.positionalArguments.first as String),
          statusCode: 201,
          data: _fixtureJson(fixture),
        );
      });
    }

    testWidgets('empty or blank description: no description key; no project/date keys', (
      tester,
    ) async {
      answerPost('task_created_plain.json');
      await openForm(tester, taskRepository: TaskRepositoryImpl(api));
      await tester.enterText(titleField, ' Market alışverişi ');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      router.push(AppRouter.tasksNewPath);
      await tester.pumpAndSettle();
      await tester.enterText(titleField, 'İkinci');
      await tester.enterText(descriptionField, '   ');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(posted, hasLength(2));
      expect(posted[0], {'title': 'Market alışverişi'});
      expect(posted[0].containsKey('description'), isFalse, reason: "no '' as the dialog sent");
      expect(posted[1], {'title': 'İkinci'});
    });

    testWidgets('project + date + description: project_id int, due_date YYYY-MM-DDT00:00:00', (
      tester,
    ) async {
      answerPost('task_created_with_project.json');
      await openForm(tester, taskRepository: TaskRepositoryImpl(api));
      await tester.enterText(titleField, 'Giriş ekranını bitir');
      await tester.enterText(descriptionField, 'Form ve hata mesajları');
      await selectProject(tester, 'Ev taşıma');
      await pickDay(tester, 21);
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(posted.single, {
        'title': 'Giriş ekranını bitir',
        'description': 'Form ve hata mesajları',
        'due_date': '2026-11-21T00:00:00',
        'project_id': 1,
      });
      expect(() => jsonEncode(posted.single), returnsNormally);
    });
  });

  group('keyboard open (narrow screen)', () {
    testWidgets('360px x1.5 with a 300px keyboard: Kaydet above the keyboard and tappable; '
        'the error snackbar does not cover it', (tester) async {
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => const Left(_serverError));
      await openForm(tester, size: const Size(360, 640), textScale: 1.5);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();

      await tester.enterText(titleField, 'Klavye');
      await tester.enterText(descriptionField, 'Uzun bir açıklama ' * 6);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(saveButton);
      expect(rect.bottom, lessThanOrEqualTo(640 - 300), reason: 'above the keyboard');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      verify(() => taskRepo.createTask(any())).called(1);
      final snackRect = tester.getRect(find.byType(SnackBar));
      final saveRect = tester.getRect(saveButton);
      expect(snackRect.bottom, lessThanOrEqualTo(saveRect.top), reason: 'snackbar above Kaydet');
      expect(saveEnabled(tester), isTrue);

      // Kaydet is still hit-testable while the snackbar shows.
      await tester.tap(saveButton);
      await tester.pumpAndSettle();
      verify(() => taskRepo.createTask(any())).called(1);
      expect(tester.takeException(), isNull);
    });
  });

  group('page closed while saving (mounted checks)', () {
    testWidgets('Planning below: close during the request, no exception, list updated', (
      tester,
    ) async {
      final pending = Completer<_TaskResult>();
      when(() => taskRepo.createTask(any())).thenAnswer((_) => pending.future);
      await openForm(tester);
      await tester.enterText(titleField, 'Giriş ekranını bitir');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.byType(TaskListPage), findsOneWidget);

      pending.complete(await created(_createdWithProject()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TaskListPage), findsOneWidget, reason: 'no extra pop');
      expect(find.text('Giriş ekranını bitir'), findsOneWidget, reason: 'list still updated');
      verify(() => taskRepo.createTask(any())).called(1);
    });

    testWidgets('/tasks/new opened directly: close during the request, no exception', (
      tester,
    ) async {
      final pending = Completer<_TaskResult>();
      when(() => taskRepo.createTask(any())).thenAnswer((_) => pending.future);
      await pumpApp(tester, initial: AppRouter.tasksNewPath);
      expect(find.byType(TaskListPage), findsNothing);
      expect(router.canPop(), isFalse);
      await tester.enterText(titleField, 'Doğrudan');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pump();

      router.go(AppRouter.homePath);
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.text('HOME'), findsOneWidget);

      pending.complete(Right(_createdWithProject()));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('HOME'), findsOneWidget, reason: 'no navigation after close');
      verify(() => taskRepo.createTask(any())).called(1);
    });
  });
}
