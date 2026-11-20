import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/features/planning/presentation/task_list_page.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task_repository.dart' show TaskRepository;
import 'package:varys/features/planning/domain/task.dart' show Task, TaskStatus, TaskFilter;
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'dart:async';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';

import '../../projects/fake_project_repository.dart';

void main() {
  group('TaskListPage Widget Tests', () {
    testWidgets('shows loading indicator when provider is loading', (WidgetTester tester) async {
      final completer = Completer<TaskRepository>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWith((ref) => completer.future),
          ],
          child: const MaterialApp(
            home: TaskListPage(),
          ),
        ),
      );

      // Verify loading indicator is shown
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message when provider fails with Failure', (WidgetTester tester) async {
      // Create a mock repository that returns a Failure
      final mockRepository = _MockTaskRepository(
        getTasksByFilterResult: Left(NetworkFailure('Sunucuya ulaşılamıyor')),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWith((ref) async => mockRepository),
          ],
          child: const MaterialApp(
            home: TaskListPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Turkish error message is displayed
      expect(find.text('Bağlantı hatası'), findsOneWidget);

      // Verify "Instance of" does NOT appear
      expect(find.textContaining('Instance of'), findsNothing);

      // Verify "Exception:" does NOT appear
      expect(find.textContaining('Exception:'), findsNothing);

      // Verify "Tekrar Dene" button is present (exact casing from UI)
      expect(find.widgetWithText(FilledButton, 'Tekrar Dene'), findsOneWidget);
    });

    testWidgets('shows error message when repository returns Left(NetworkFailure) via notifier', (WidgetTester tester) async {
      // This test uses the actual taskListNotifierProvider with a mock repository
      final mockRepository = _MockTaskRepository(
        getTasksByFilterResult: Left(NetworkFailure('Sunucuya bağlanılamıyor')),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWith((ref) async => mockRepository),
          ],
          child: const MaterialApp(
            home: TaskListPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Turkish error message is displayed
      expect(find.text('Bağlantı hatası'), findsOneWidget);

      // Verify "Instance of" does NOT appear
      expect(find.textContaining('Instance of'), findsNothing);

      // Verify "Exception:" does NOT appear
      expect(find.textContaining('Exception:'), findsNothing);

      // Verify "Tekrar Dene" button is present
      expect(find.widgetWithText(FilledButton, 'Tekrar Dene'), findsOneWidget);
    });
  });

  group('TaskListPage mutation failures (real TaskListNotifier + mocked repository)', () {
    late _MocktailTaskRepository repo;

    Task task(int id, String title, {TaskStatus status = TaskStatus.todo}) => Task(
          id: id,
          title: title,
          status: status,
          createdAt: DateTime(2026, 11, 1, 10),
          updatedAt: DateTime(2026, 11, 1, 10),
        );

    setUpAll(() {
      registerFallbackValue(task(0, 'fallback'));
      registerFallbackValue(TaskFilter.all);
    });

    setUp(() {
      repo = _MocktailTaskRepository();
      when(() => repo.getTasksByFilter(any()))
          .thenAnswer((_) async => Right([task(1, 'Görev A'), task(2, 'Görev B')]));
    });

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [taskRepositoryProvider.overrideWith((ref) async => repo)],
          child: const MaterialApp(home: TaskListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    bool checkboxValue(WidgetTester tester, String title) => tester
        .widget<Checkbox>(find.descendant(
          of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
          matching: find.byType(Checkbox),
        ))
        .value!;

    /// Planning page on a router, so "Yeni Görev" can push the create form
    /// (`/tasks/new`) on top of it, as in the app.
    Future<void> pumpRouted(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: AppRouter.planningPath,
        routes: [
          GoRoute(path: AppRouter.planningPath, builder: (_, _) => const TaskListPage()),
          GoRoute(path: AppRouter.tasksNewPath, builder: (_, _) => const TaskEditScreen()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWith((ref) async => repo),
            projectRepositoryProvider.overrideWith((ref) async => FakeProjectRepository()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    final formTitle = find.byKey(const ValueKey('task-title'));
    final formSave = find.byKey(const ValueKey('task-save'));

    Future<void> addViaForm(WidgetTester tester, String title) async {
      await tester.tap(find.text('Yeni Görev'));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditScreen), findsOneWidget, reason: 'FAB opens the form');
      await tester.enterText(formTitle, title);
      await tester.pumpAndSettle();
      await tester.tap(formSave);
      await tester.pumpAndSettle();
    }

    testWidgets('add Left(NetworkFailure) via the form: no full-page error, form keeps text, '
        'snackbar; the list behind it stays', (tester) async {
      when(() => repo.createTask(any()))
          .thenAnswer((_) async => const Left(NetworkFailure('Sunucuya bağlanılamıyor')));
      await pumpRouted(tester);

      await addViaForm(tester, 'Yeni iş');

      expect(find.text('Bir hata oluştu'), findsNothing);
      expect(find.text(TaskEditScreen.createTitle), findsOneWidget, reason: 'form stays open');
      expect(tester.widget<TextField>(formTitle).controller!.text, 'Yeni iş');
      expect(find.widgetWithText(SnackBar, 'Bağlantı hatası'), findsOneWidget);
      verify(() => repo.createTask(any())).called(1);

      // Leave the form: the list under it is unchanged, no full-page error.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.text('Bir hata oluştu'), findsNothing);
      expect(find.text('Görev A'), findsOneWidget);
      expect(find.text('Görev B'), findsOneWidget);
    });

    testWidgets('add Right via the form: form closes and the list shows the new task', (tester) async {
      await pumpRouted(tester);
      when(() => repo.createTask(any())).thenAnswer((_) async => Right(task(3, 'Yeni iş')));
      when(() => repo.getTasksByFilter(any())).thenAnswer(
          (_) async => Right([task(3, 'Yeni iş'), task(1, 'Görev A'), task(2, 'Görev B')]));

      await addViaForm(tester, 'Yeni iş');

      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.text(TaskEditScreen.createTitle), findsNothing, reason: 'form closed');
      expect(find.text('Yeni iş'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      final sent = verify(() => repo.createTask(captureAny())).captured.single as Task;
      expect(sent.title, 'Yeni iş');
    });

    testWidgets('toggle: optimistic tick, Left rolls back only that task and shows snackbar',
        (tester) async {
      final pending = Completer<Either<Failure, Task>>();
      when(() => repo.updateTaskStatus(1, TaskStatus.done)).thenAnswer((_) => pending.future);
      await pumpPage(tester);

      await tester.tap(find.descendant(
        of: find.ancestor(of: find.text('Görev A'), matching: find.byType(ListTile)),
        matching: find.byType(Checkbox),
      ));
      await tester.pump();
      expect(checkboxValue(tester, 'Görev A'), isTrue, reason: 'optimistic update');

      pending.complete(const Left(NetworkFailure('Sunucuya bağlanılamıyor')));
      await tester.pumpAndSettle();

      expect(checkboxValue(tester, 'Görev A'), isFalse);
      expect(checkboxValue(tester, 'Görev B'), isFalse);
      expect(find.text('Bir hata oluştu'), findsNothing);
      expect(find.widgetWithText(SnackBar, 'Bağlantı hatası'), findsOneWidget);
    });

    testWidgets('delete Left: task re-appears in place and snackbar is shown', (tester) async {
      when(() => repo.deleteTask(1))
          .thenAnswer((_) async => const Left(ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500)));
      await pumpPage(tester);

      await tester.tap(find.descendant(
        of: find.ancestor(of: find.text('Görev A'), matching: find.byType(ListTile)),
        matching: find.byTooltip('Sil'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Görev A'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Görev A')).dy, lessThan(tester.getTopLeft(find.text('Görev B')).dy));
      expect(find.widgetWithText(SnackBar, 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.'), findsOneWidget);
    });

    testWidgets('initial load error: "Tekrar Dene" reloads without crashing', (tester) async {
      when(() => repo.getTasksByFilter(any()))
          .thenAnswer((_) async => const Left(NetworkFailure('Sunucuya bağlanılamıyor')));
      await pumpPage(tester);
      expect(find.text('Bir hata oluştu'), findsOneWidget);

      when(() => repo.getTasksByFilter(any())).thenAnswer((_) async => Right([task(1, 'Görev A')]));
      await tester.tap(find.text('Tekrar Dene'));
      await tester.pumpAndSettle();

      expect(find.text('Bir hata oluştu'), findsNothing);
      expect(find.text('Görev A'), findsOneWidget);
    });
  });

  _subtitleTests();
  _rowTapTests();
}

class _MocktailTaskRepository extends Mock implements TaskRepository {}

void _subtitleTests() {
  group('Planning row subtitle (project name + due day)', () {
    late _MocktailTaskRepository repo;
    late FakeProjectRepository projectRepo;

    Task task(int id, String title, {String? description, int? projectId, DateTime? due}) => Task(
          id: id,
          title: title,
          description: description,
          status: TaskStatus.todo,
          createdAt: DateTime(2026, 11, 1, 10),
          updatedAt: DateTime(2026, 11, 1, 10),
          projectId: projectId,
          dueDate: due,
        );

    setUpAll(() async {
      await initializeDateFormatting('tr_TR', null);
      registerFallbackValue(TaskFilter.all);
    });

    setUp(() {
      repo = _MocktailTaskRepository();
      projectRepo = FakeProjectRepository(); // real GET /projects fixture
    });

    Future<void> pumpRows(WidgetTester tester, List<Task> tasks) async {
      when(() => repo.getTasksByFilter(any())).thenAnswer((_) async => Right(tasks));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWith((ref) async => repo),
            projectRepositoryProvider.overrideWith((ref) async => projectRepo),
          ],
          child: const MaterialApp(home: TaskListPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    ListTile tile(WidgetTester tester, String title) => tester.widget<ListTile>(
          find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
        );

    Finder meta(int id) => find.byKey(ValueKey('task-meta-$id'));

    testWidgets('project name and due day; only one; neither keeps the old look', (tester) async {
      await pumpRows(tester, [
        task(1, 'İkisi de', projectId: 1, due: DateTime(2026, 11, 21)),
        task(2, 'Yalnız proje', projectId: 3),
        task(3, 'Yalnız tarih', due: DateTime(2026, 12, 2)),
        task(4, 'Hiçbiri', description: 'Eski açıklama'),
        task(5, 'Çıplak'),
      ]);

      expect(tester.widget<Text>(meta(1)).data, 'Ev taşıma · 21 Kas');
      expect(tester.widget<Text>(meta(2)).data, 'Bahçe düzenlemesi');
      expect(tester.widget<Text>(meta(3)).data, '2 Ara');
      expect(meta(4), findsNothing);
      expect(find.text('Eski açıklama'), findsOneWidget);
      expect(meta(5), findsNothing);
      expect(tile(tester, 'Çıplak').subtitle, isNull, reason: 'no subtitle at all, as before');
    });

    testWidgets('description and meta line are both shown, description first', (tester) async {
      await pumpRows(tester, [task(1, 'Görev', description: 'Not', projectId: 2)]);

      expect(find.text('Not'), findsOneWidget);
      expect(tester.widget<Text>(meta(1)).data, 'Kitap okuma listesi');
      expect(tester.getTopLeft(find.text('Not')).dy, lessThan(tester.getTopLeft(meta(1)).dy));
    });

    testWidgets("description '' (old dialog) draws no empty line: only the meta line", (tester) async {
      await pumpRows(tester, [
        task(1, 'Projeli boş açıklama', description: '', projectId: 1),
        task(2, 'Boş açıklama', description: ''),
      ]);

      final column = tile(tester, 'Projeli boş açıklama').subtitle as Column;
      expect(column.children, hasLength(1));
      expect((column.children.single as Text).data, 'Ev taşıma');
      expect(tile(tester, 'Boş açıklama').subtitle, isNull);
    });

    testWidgets('a completed project is still named', (tester) async {
      await pumpRows(tester, [task(1, 'Eski iş', projectId: 5)]);

      expect(tester.widget<Text>(meta(1)).data, 'Vergi beyannamesi');
    });

    testWidgets('unknown project id (deleted) shows no name and does not crash', (tester) async {
      await pumpRows(tester, [
        task(1, 'Silinmiş projeli', projectId: 999),
        task(2, 'Silinmiş projeli tarihli', projectId: 999, due: DateTime(2026, 11, 21)),
      ]);

      expect(tester.takeException(), isNull);
      expect(meta(1), findsNothing);
      expect(tile(tester, 'Silinmiş projeli').subtitle, isNull);
      expect(tester.widget<Text>(meta(2)).data, '21 Kas');
    });

    testWidgets('projects failing to load: rows still render, names simply absent', (tester) async {
      projectRepo.listFailure = const NetworkFailure('Sunucuya bağlanılamıyor');
      await pumpRows(tester, [task(1, 'Projeli', projectId: 1, due: DateTime(2026, 11, 21))]);

      expect(tester.takeException(), isNull);
      expect(find.text('Projeli'), findsOneWidget);
      expect(tester.widget<Text>(meta(1)).data, '21 Kas');
      expect(find.text('Bir hata oluştu'), findsNothing, reason: 'no full-page error');
    });
  });
}

/// Planning row gestures: the body opens the edit form (it used to toggle
/// completion); the checkbox completes, Sil deletes, a swipe asks to delete,
/// and none of those opens the form.
void _rowTapTests() {
  group('Planning row: body tap opens the edit form; checkbox, Sil and swipe keep working', () {
    late _MocktailTaskRepository repo;
    late GoRouter router;

    Task task(int id, String title) => Task(
          id: id,
          title: title,
          status: TaskStatus.todo,
          createdAt: DateTime(2026, 11, 1, 10),
          updatedAt: DateTime(2026, 11, 1, 10),
        );

    setUpAll(() async {
      await initializeDateFormatting('tr_TR', null);
      registerFallbackValue(TaskFilter.all);
      registerFallbackValue(TaskStatus.todo);
    });

    setUp(() {
      repo = _MocktailTaskRepository();
      when(() => repo.getTasksByFilter(any()))
          .thenAnswer((_) async => Right([task(1, 'Görev A'), task(2, 'Görev B')]));
    });

    Future<void> pumpRouted(WidgetTester tester) async {
      router = GoRouter(
        initialLocation: AppRouter.planningPath,
        routes: [
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWith((ref) async => repo),
            projectRepositoryProvider.overrideWith((ref) async => FakeProjectRepository()),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder row(String title) =>
        find.ancestor(of: find.text(title), matching: find.byType(ListTile));
    Finder inRow(String title, Finder matching) =>
        find.descendant(of: row(title), matching: matching);
    bool checked(WidgetTester tester, String title) =>
        tester.widget<Checkbox>(inRow(title, find.byType(Checkbox))).value!;

    testWidgets('body tap opens the form for THAT task and does not complete it', (tester) async {
      await pumpRouted(tester);

      await tester.tap(find.text('Görev A'));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsOneWidget);
      expect(tester.widget<TaskEditScreen>(find.byType(TaskEditScreen)).task?.id, 1);
      expect(find.text(TaskEditScreen.editTitle), findsOneWidget);
      verifyNever(() => repo.updateTaskStatus(any(), any()));

      router.pop();
      await tester.pumpAndSettle();
      expect(checked(tester, 'Görev A'), isFalse, reason: 'still not completed');
    });

    testWidgets('checkbox tap completes the task and does NOT open the form', (tester) async {
      when(() => repo.updateTaskStatus(1, TaskStatus.done))
          .thenAnswer((_) async => Right(task(1, 'Görev A').copyWith(status: TaskStatus.done)));
      await pumpRouted(tester);

      await tester.tap(inRow('Görev A', find.byType(Checkbox)));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsNothing);
      verify(() => repo.updateTaskStatus(1, TaskStatus.done)).called(1);
      expect(checked(tester, 'Görev A'), isTrue);
    });

    testWidgets('Sil button deletes and does NOT open the form', (tester) async {
      when(() => repo.deleteTask(1)).thenAnswer((_) async => const Right(null));
      await pumpRouted(tester);

      await tester.tap(inRow('Görev A', find.byTooltip('Sil')));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsNothing);
      verify(() => repo.deleteTask(1)).called(1);
      expect(find.text('Görev A'), findsNothing);
    });

    testWidgets('short horizontal drag (below the dismiss threshold): no form, row snaps back', (
      tester,
    ) async {
      await pumpRouted(tester);
      final before = tester.getTopLeft(row('Görev A'));

      await tester.drag(find.text('Görev A'), const Offset(-60, 0));
      await tester.pumpAndSettle();

      expect(find.byType(TaskEditScreen), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.getTopLeft(row('Görev A')), before, reason: 'back in place');
      verifyNever(() => repo.deleteTask(any()));
      verifyNever(() => repo.updateTaskStatus(any(), any()));
    });

    testWidgets('drag past the threshold opens the delete confirmation, not the form', (
      tester,
    ) async {
      await pumpRouted(tester);

      await tester.drag(find.text('Görev A'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(AlertDialog, 'Görevi Sil'), findsOneWidget);
      expect(find.byType(TaskEditScreen), findsNothing);

      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(find.text('Görev A'), findsOneWidget, reason: 'cancel keeps the row');
      verifyNever(() => repo.deleteTask(any()));
    });

    testWidgets('tap targets: row, checkbox and Sil are at least 48x48', (tester) async {
      await pumpRouted(tester);

      expect(tester.getSize(row('Görev A')).height, greaterThanOrEqualTo(48));
      final checkbox = tester.getSize(inRow('Görev A', find.byType(Checkbox)));
      expect(checkbox.width, greaterThanOrEqualTo(48));
      expect(checkbox.height, greaterThanOrEqualTo(48));
      final delete = tester.getSize(inRow('Görev A', find.byType(IconButton)));
      expect(delete.width, greaterThanOrEqualTo(48));
      expect(delete.height, greaterThanOrEqualTo(48));
    });
  });
}

class _MockTaskRepository implements TaskRepository {
  final Either<Failure, List<Task>> getTasksByFilterResult;

  _MockTaskRepository({required this.getTasksByFilterResult});

  @override
  Future<Either<Failure, List<Task>>> getTasks() async => const Right([]);

  @override
  Future<Either<Failure, List<Task>>> getTasksByFilter(TaskFilter filter) async => getTasksByFilterResult;

  @override
  Future<Either<Failure, Task>> createTask(Task task) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Task>> updateTask(
    int id, {
    String? title,
    PlanField<String> description = const PlanField.unset(),
    TaskStatus? status,
    PlanField<DateTime> plannedDate = const PlanField.unset(),
    PlanField<DateTime> dueDate = const PlanField.unset(),
    PlanField<int> projectId = const PlanField.unset(),
    bool? isImportant,
    bool? isUrgent,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, void>> deleteTask(int id) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Task>> planForDay(int id, DateTime day) async => throw UnimplementedError();
}