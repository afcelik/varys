import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/features/planning/presentation/task_list_page.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task_repository.dart' show TaskRepository;
import 'package:varys/features/planning/domain/task.dart' show Task, TaskStatus, TaskFilter;
import 'package:varys/core/errors/failure.dart';
import 'dart:async';
import 'package:mocktail/mocktail.dart';

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

    testWidgets('add Left(NetworkFailure): no full-page error, list stays, dialog keeps text, snackbar',
        (tester) async {
      when(() => repo.createTask(any()))
          .thenAnswer((_) async => const Left(NetworkFailure('Sunucuya bağlanılamıyor')));
      await pumpPage(tester);

      await tester.tap(find.text('Yeni Görev'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Yeni iş');
      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();

      expect(find.text('Bir hata oluştu'), findsNothing);
      expect(find.text('Görev A'), findsOneWidget);
      expect(find.text('Görev B'), findsOneWidget);
      expect(find.text('Yeni Görev Ekle'), findsOneWidget, reason: 'dialog stays open');
      final titleField = tester.widget<TextField>(find.byType(TextField).first);
      expect(titleField.controller!.text, 'Yeni iş');
      expect(find.widgetWithText(SnackBar, 'Bağlantı hatası'), findsOneWidget);
    });

    testWidgets('add Right: dialog closes and the refreshed list shows the new task', (tester) async {
      await pumpPage(tester);
      when(() => repo.createTask(any())).thenAnswer((_) async => Right(task(3, 'Yeni iş')));
      when(() => repo.getTasksByFilter(any())).thenAnswer(
          (_) async => Right([task(1, 'Görev A'), task(2, 'Görev B'), task(3, 'Yeni iş')]));

      await tester.tap(find.text('Yeni Görev'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Yeni iş');
      await tester.tap(find.text('Ekle'));
      await tester.pumpAndSettle();

      expect(find.text('Yeni Görev Ekle'), findsNothing);
      expect(find.text('Yeni iş'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
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
}

class _MocktailTaskRepository extends Mock implements TaskRepository {}

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
  Future<Either<Failure, Task>> updateTask(Task task) async => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> deleteTask(int id) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Task>> planForDay(int id, DateTime day) async => throw UnimplementedError();
}