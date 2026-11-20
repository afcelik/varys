import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/presentation/active_projects_notifier.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';

import '../../projects/fake_project_repository.dart';

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

/// Real PATCH /tasks/{id} 200 bodies.
Task _fixtureTask(String name) => Task.fromJson(
  jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>,
);

Task _existing(int id, String title) => Task(
  id: id,
  title: title,
  status: TaskStatus.todo,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
);

/// Lets every pending rebuild/fetch run (and any loop show itself).
Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

const _taskGone = ServerFailure('Kaynak bulunamadı.', statusCode: 404);
const _projectGone = ServerFailure('Seçilen proje bulunamadı.', statusCode: 404);

void main() {
  late _MockTaskRepository taskRepo;
  late _MockDailyPlanRepository planRepo;
  late FakeProjectRepository projectRepo;

  /// The task as the list holds it before the edit: id 1, project 1.
  late Task original;

  /// PATCH response: id 1, project 2, due 2026-11-25 (task_update_set.json).
  late Task movedToProject2;

  /// PATCH response: id 1, everything cleared (task_update_cleared.json).
  late Task cleared;

  final a = _existing(10, 'Görev A');
  final b = _existing(11, 'Görev B');

  setUpAll(() {
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(const PlanField<String>.unset());
    registerFallbackValue(const PlanField<int>.unset());
    registerFallbackValue(const PlanField<DateTime>.unset());
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    taskRepo = _MockTaskRepository();
    planRepo = _MockDailyPlanRepository();
    projectRepo = FakeProjectRepository();
    movedToProject2 = _fixtureTask('task_update_set.json');
    cleared = _fixtureTask('task_update_cleared.json');
    original = movedToProject2.copyWith(title: 'Giriş ekranını bitir', projectId: 1, dueDate: null);
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([original, a, b]));
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
  });

  void answerUpdate(Future<Either<Failure, Task>> Function() answer) {
    when(
      () => taskRepo.updateTask(
        any(),
        title: any(named: 'title'),
        description: any(named: 'description'),
        status: any(named: 'status'),
        plannedDate: any(named: 'plannedDate'),
        dueDate: any(named: 'dueDate'),
        projectId: any(named: 'projectId'),
      ),
    ).thenAnswer((_) => answer());
  }

  void verifyNoUpdate() => verifyNever(
    () => taskRepo.updateTask(
      any(),
      title: any(named: 'title'),
      description: any(named: 'description'),
      status: any(named: 'status'),
      plannedDate: any(named: 'plannedDate'),
      dueDate: any(named: 'dueDate'),
      projectId: any(named: 'projectId'),
    ),
  );

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Everything a user could have on screen: Planning, the projects page
  /// list, the Home projects card and the daily plan.
  Future<List<AsyncValue<TaskListState>>> listenAll(ProviderContainer c) async {
    final states = <AsyncValue<TaskListState>>[];
    c.listen(taskListNotifierProvider, (_, next) => states.add(next));
    c.listen(projectsListProvider, (_, _) {});
    c.listen(activeProjectsProvider, (_, _) {});
    c.listen(dailyPlanProvider, (_, _) {});
    await c.read(taskListNotifierProvider.future);
    await c.read(projectsListProvider.future);
    await c.read(activeProjectsProvider.future);
    await c.read(dailyPlanProvider.future);
    states.clear();
    return states;
  }

  List<Task> tasks(ProviderContainer c) => c.read(taskListNotifierProvider).value!.tasks.value!;
  List<int> ids(ProviderContainer c) => tasks(c).map((t) => t.id).toList();

  const moveToProject2 = TaskChanges(
    title: 'Giriş ekranını bitir ve test et',
    projectId: PlanField.set(2),
  );

  group('updateTask success', () {
    test('server task replaces the row at once (same place), before the silent refresh', () async {
      final c = makeContainer();
      final states = await listenAll(c);
      final refresh = Completer<Either<Failure, List<Task>>>();
      answerUpdate(() async => Right(movedToProject2));
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) => refresh.future);

      final result = await c
          .read(taskListNotifierProvider.notifier)
          .updateTask(original, moveToProject2);

      expect(result, Right<Failure, Task>(movedToProject2));
      expect(ids(c), [1, 10, 11]);
      expect(tasks(c).first.projectId, 2);
      expect(tasks(c).first.title, 'Giriş ekranını bitir ve test et');
      expect(states.any((s) => s.isLoading), isFalse, reason: 'no skeleton flash');

      refresh.complete(Right([movedToProject2, a, b, _existing(12, 'Başka cihazdan')]));
      await _settle();
      expect(ids(c), [1, 10, 11, 12], reason: 'silent refresh result applied');
      expect(states.any((s) => s.isLoading || s.hasError), isFalse);
      verify(() => taskRepo.getTasksByFilter(TaskFilter.all)).called(2);
    });

    test('the changes are forwarded field by field (clear stays clear, rest unset)', () async {
      final c = makeContainer();
      await listenAll(c);
      answerUpdate(() async => Right(cleared));

      await c
          .read(taskListNotifierProvider.notifier)
          .updateTask(
            original,
            const TaskChanges(
              description: PlanField.clear(),
              projectId: PlanField.clear(),
              plannedDate: PlanField.clear(),
            ),
          );

      verify(
        () => taskRepo.updateTask(
          1,
          title: null,
          description: const PlanField<String>.clear(),
          status: null,
          plannedDate: const PlanField<DateTime>.clear(),
          dueDate: const PlanField<DateTime>.unset(),
          projectId: const PlanField<int>.clear(),
        ),
      ).called(1);
    });

    test('a result outside the current filter leaves the list', () async {
      final c = makeContainer();
      await listenAll(c);
      when(
        () => taskRepo.getTasksByFilter(TaskFilter.inProgress),
      ).thenAnswer((_) async => Right([original, a]));
      await c.read(taskListNotifierProvider.notifier).changeFilter(TaskFilter.inProgress);
      final refresh = Completer<Either<Failure, List<Task>>>();
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) => refresh.future);
      // Completed elsewhere meanwhile: the server answer is "done".
      answerUpdate(() async => Right(movedToProject2.copyWith(status: TaskStatus.done)));

      await c.read(taskListNotifierProvider.notifier).updateTask(original, moveToProject2);

      expect(ids(c), [10], reason: 'removed at once, not after the refresh');
    });

    test('project changed (1 → 2): project providers re-fetched exactly once, no loop', () async {
      final c = makeContainer();
      await listenAll(c);
      expect((projectRepo.listCalls, projectRepo.activeCalls), (1, 1));
      answerUpdate(() async => Right(movedToProject2));

      await c.read(taskListNotifierProvider.notifier).updateTask(original, moveToProject2);
      await _settle();
      expect((projectRepo.listCalls, projectRepo.activeCalls), (2, 2));

      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect((projectRepo.listCalls, projectRepo.activeCalls), (2, 2), reason: 'stable: no loop');
      verify(() => planRepo.getPlan(_day)).called(2); // Home synced once
      verify(() => taskRepo.getTasksByFilter(any())).called(2); // + silent refresh only
    });

    test('project cleared (1 → none) also re-fetches the project providers once', () async {
      final c = makeContainer();
      await listenAll(c);
      answerUpdate(() async => Right(cleared));
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([cleared, a, b]));

      await c
          .read(taskListNotifierProvider.notifier)
          .updateTask(original, const TaskChanges(projectId: PlanField.clear()));
      await _settle();

      expect((projectRepo.listCalls, projectRepo.activeCalls), (2, 2));
      expect(tasks(c).first.projectId, isNull);
    });

    test('project unchanged: project providers untouched; Home still syncs once', () async {
      final c = makeContainer();
      await listenAll(c);
      final renamed = original.copyWith(title: 'Yeni ad');
      answerUpdate(() async => Right(renamed));
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([renamed, a, b]));

      await c
          .read(taskListNotifierProvider.notifier)
          .updateTask(original, const TaskChanges(title: 'Yeni ad'));
      await _settle();

      expect((projectRepo.listCalls, projectRepo.activeCalls), (1, 1));
      verify(() => planRepo.getPlan(_day)).called(2);
      expect(tasks(c).first.title, 'Yeni ad');
    });

    test('a failed silent refresh keeps the updated row; no error or loading state', () async {
      final c = makeContainer();
      final states = await listenAll(c);
      answerUpdate(() async => Right(movedToProject2));
      when(
        () => taskRepo.getTasksByFilter(any()),
      ).thenAnswer((_) async => const Left(NetworkFailure('Sunucuya bağlanılamıyor')));

      final result = await c
          .read(taskListNotifierProvider.notifier)
          .updateTask(original, moveToProject2);
      await _settle();

      expect(result.isRight(), isTrue);
      expect(ids(c), [1, 10, 11]);
      expect(tasks(c).first.projectId, 2);
      expect(states.any((s) => s.isLoading || s.hasError), isFalse);
    });
  });

  test('no changes: no request, original returned, nothing re-fetched or invalidated', () async {
    final c = makeContainer();
    await listenAll(c);
    answerUpdate(() async => Right(movedToProject2));

    final result = await c
        .read(taskListNotifierProvider.notifier)
        .updateTask(original, const TaskChanges());
    await _settle();

    expect(result, Right<Failure, Task>(original));
    verifyNoUpdate();
    expect(ids(c), [1, 10, 11]);
    expect((projectRepo.listCalls, projectRepo.activeCalls), (1, 1));
    verify(() => planRepo.getPlan(_day)).called(1);
    verify(() => taskRepo.getTasksByFilter(any())).called(1);
  });

  group('updateTask failure', () {
    test('task 404 (deleted elsewhere): silent refresh drops the stale row; Left', () async {
      final c = makeContainer();
      final states = await listenAll(c);
      answerUpdate(() async => const Left(_taskGone));
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([a, b]));

      final result = await c
          .read(taskListNotifierProvider.notifier)
          .updateTask(original, const TaskChanges(title: 'x'));
      expect(ids(c), [1, 10, 11], reason: 'not removed optimistically');
      await _settle();

      expect(result, const Left<Failure, Task>(_taskGone));
      expect(ids(c), [10, 11]);
      expect(states.any((s) => s.isLoading || s.hasError), isFalse);
      verify(() => planRepo.getPlan(_day)).called(1); // no Home sync on failure
      expect((projectRepo.listCalls, projectRepo.activeCalls), (1, 1));
    });

    test('project 404: Left with the project message, row kept, list re-fetched', () async {
      final c = makeContainer();
      await listenAll(c);
      answerUpdate(() async => const Left(_projectGone));

      final result = await c
          .read(taskListNotifierProvider.notifier)
          .updateTask(original, moveToProject2);
      await _settle();

      expect(result, const Left<Failure, Task>(_projectGone));
      expect(ids(c), [1, 10, 11]);
      expect(tasks(c).first.projectId, 1, reason: 'nothing applied');
      verify(() => taskRepo.getTasksByFilter(any())).called(2);
    });

    test('other failure (500): list untouched, nothing re-fetched or invalidated', () async {
      final c = makeContainer();
      await listenAll(c);
      const failure = ServerFailure(
        'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
        statusCode: 500,
      );
      answerUpdate(() async => const Left(failure));

      final result = await c
          .read(taskListNotifierProvider.notifier)
          .updateTask(original, moveToProject2);
      await _settle();

      expect(result, const Left<Failure, Task>(failure));
      expect(tasks(c), [original, a, b]);
      verify(() => taskRepo.getTasksByFilter(any())).called(1);
      verify(() => planRepo.getPlan(_day)).called(1);
      expect((projectRepo.listCalls, projectRepo.activeCalls), (1, 1));
    });
  });

  test('without any listener (form opened directly) the request finishes without errors', () async {
    final c = makeContainer();
    final update = Completer<Either<Failure, Task>>();
    answerUpdate(() => update.future);

    final pending = c.read(taskListNotifierProvider.notifier).updateTask(original, moveToProject2);
    await _settle(); // an unkept autoDispose provider would be disposed here
    expect(c.exists(taskListNotifierProvider), isTrue, reason: 'kept alive while the request runs');
    update.complete(Right(movedToProject2));

    expect(await pending, Right<Failure, Task>(movedToProject2));
    await _settle();
    expect(c.exists(taskListNotifierProvider), isFalse, reason: 'released after the refresh');
  });

  test('Eisenhower flags are forwarded as given; untouched flags stay null', () async {
    final c = makeContainer();
    await listenAll(c);
    final flagged = movedToProject2.copyWith(isUrgent: true);
    when(
      () => taskRepo.updateTask(
        any(),
        title: any(named: 'title'),
        description: any(named: 'description'),
        status: any(named: 'status'),
        plannedDate: any(named: 'plannedDate'),
        dueDate: any(named: 'dueDate'),
        projectId: any(named: 'projectId'),
        isImportant: any(named: 'isImportant'),
        isUrgent: any(named: 'isUrgent'),
      ),
    ).thenAnswer((_) async => Right(flagged));

    final result = await c
        .read(taskListNotifierProvider.notifier)
        .updateTask(original, const TaskChanges(isUrgent: true));

    expect(result, Right<Failure, Task>(flagged));
    final captured = verify(
      () => taskRepo.updateTask(
        1,
        title: any(named: 'title'),
        description: any(named: 'description'),
        status: any(named: 'status'),
        plannedDate: any(named: 'plannedDate'),
        dueDate: any(named: 'dueDate'),
        projectId: any(named: 'projectId'),
        isImportant: captureAny(named: 'isImportant'),
        isUrgent: captureAny(named: 'isUrgent'),
      ),
    ).captured;
    expect(captured, [null, true]);
    expect(tasks(c).first.isUrgent, isTrue, reason: 'server task replaced the row');
  });
}
