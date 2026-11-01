import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/features/home/presentation/focus_task_selection_page.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task_repository.dart' show TaskRepository;
import 'package:varys/features/planning/domain/task.dart' show Task, TaskStatus, TaskFilter;
import 'package:varys/core/errors/failure.dart';
import 'dart:async';

void main() {
  group('FocusTaskSelectionPage Widget Tests', () {
    testWidgets('shows loading indicator when provider is loading', (WidgetTester tester) async {
      final completer = Completer<TaskRepository>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWith((ref) => completer.future),
          ],
          child: const MaterialApp(
            home: FocusTaskSelectionPage(),
          ),
        ),
      );

      // Verify loading indicator is shown
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error message when provider fails with NetworkFailure', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWith((ref) async => throw NetworkFailure('Sunucuya bağlanılamıyor')),
          ],
          child: const MaterialApp(
            home: FocusTaskSelectionPage(),
          ),
        ),
      );

      // Wait for error state
      await tester.pumpAndSettle();

      // Verify Turkish error message is displayed
      expect(find.text('Bağlantı hatası'), findsOneWidget);

      // Verify "Instance of" does NOT appear
      expect(find.textContaining('Instance of'), findsNothing);

      // Verify "Exception:" does NOT appear
      expect(find.textContaining('Exception:'), findsNothing);

      // Verify "Tekrar dene" button is present (exact casing from UI)
      expect(find.widgetWithText(FilledButton, 'Tekrar Dene'), findsOneWidget);
    });

    testWidgets('shows error message when repository returns Left(NetworkFailure)', (WidgetTester tester) async {
      final mockRepository = _MockTaskRepository(
        getTasksByFilterResult: Left(NetworkFailure('Sunucuya ulaşılamıyor')),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            taskRepositoryProvider.overrideWith((ref) async => mockRepository),
          ],
          child: const MaterialApp(
            home: FocusTaskSelectionPage(),
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

      // Verify "Tekrar dene" button is present
      expect(find.widgetWithText(FilledButton, 'Tekrar Dene'), findsOneWidget);
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
  Future<Either<Failure, Task>> updateTask(Task task) async => throw UnimplementedError();

  @override
  Future<Either<Failure, void>> deleteTask(int id) async => throw UnimplementedError();

  @override
  Future<Either<Failure, Task>> updateTaskStatus(int id, TaskStatus status) async => throw UnimplementedError();
}