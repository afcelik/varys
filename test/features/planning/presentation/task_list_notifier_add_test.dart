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
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
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

/// Real POST /tasks 201 bodies.
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

void main() {
  late _MockTaskRepository taskRepo;
  late _MockDailyPlanRepository planRepo;
  late FakeProjectRepository projectRepo;
  late Task withProject; // id 1, project 1, due 2026-11-21
  late Task plain; // id 2, no project, no due
  final a = _existing(10, 'Görev A');
  final b = _existing(11, 'Görev B');

  setUpAll(() {
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(_existing(0, 'fallback'));
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    taskRepo = _MockTaskRepository();
    planRepo = _MockDailyPlanRepository();
    projectRepo = FakeProjectRepository();
    withProject = _fixtureTask('task_created_with_project.json');
    plain = _fixtureTask('task_created_plain.json');
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([a, b]));
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
  });

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

  List<int> ids(ProviderContainer c) =>
      c.read(taskListNotifierProvider).value!.tasks.value!.map((t) => t.id).toList();

  group('addTask success', () {
    test('server task is at the top at once, before the silent refresh answers', () async {
      final c = makeContainer();
      final states = await listenAll(c);
      final refresh = Completer<Either<Failure, List<Task>>>();
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(withProject));
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) => refresh.future);

      final result = await c.read(taskListNotifierProvider.notifier).addTask(withProject);

      expect(result.isRight(), isTrue);
      expect(ids(c), [1, 10, 11]);
      expect(c.read(taskListNotifierProvider).value!.tasks.value!.first.projectId, 1);
      expect(states.any((s) => s.isLoading), isFalse, reason: 'no loading flash');

      refresh.complete(Right([withProject, a, b, _existing(12, 'Başka cihazdan')]));
      await _settle();
      expect(ids(c), [1, 10, 11, 12], reason: 'silent refresh result applied');
      expect(states.any((s) => s.isLoading || s.hasError), isFalse);
      verify(() => taskRepo.getTasksByFilter(TaskFilter.all)).called(2);
    });

    test(
      'linked project → projects list and active projects re-fetched exactly once, no loop',
      () async {
        final c = makeContainer();
        await listenAll(c);
        expect((projectRepo.listCalls, projectRepo.activeCalls), (1, 1));
        when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(withProject));

        await c.read(taskListNotifierProvider.notifier).addTask(withProject);
        await _settle();
        expect((projectRepo.listCalls, projectRepo.activeCalls), (2, 2));

        await _settle();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect((projectRepo.listCalls, projectRepo.activeCalls), (2, 2), reason: 'stable: no loop');
        // Existing Home sync: the daily plan reloads once; the task list is
        // fetched once more by the silent refresh only.
        verify(() => planRepo.getPlan(_day)).called(2);
        verify(() => taskRepo.getTasksByFilter(any())).called(2);
      },
    );

    test('no project → project providers are not touched; Home still syncs once', () async {
      final c = makeContainer();
      await listenAll(c);
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(plain));
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([plain, a, b]));

      await c.read(taskListNotifierProvider.notifier).addTask(plain);
      await _settle();

      expect(ids(c), [2, 10, 11]);
      expect((projectRepo.listCalls, projectRepo.activeCalls), (1, 1));
      verify(() => planRepo.getPlan(_day)).called(2);
    });

    test('a task outside the current filter is not inserted ("Tamamlandı")', () async {
      final c = makeContainer();
      await listenAll(c);
      when(
        () => taskRepo.getTasksByFilter(TaskFilter.completed),
      ).thenAnswer((_) async => const Right([]));
      await c.read(taskListNotifierProvider.notifier).changeFilter(TaskFilter.completed);
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(plain));

      await c.read(taskListNotifierProvider.notifier).addTask(plain);

      expect(ids(c), isEmpty);
    });
  });

  group('silent refresh', () {
    test('only the newest refresh may write (an older, slower answer is dropped)', () async {
      final c = makeContainer();
      await listenAll(c);
      final first = Completer<Either<Failure, List<Task>>>();
      final second = Completer<Either<Failure, List<Task>>>();
      final pending = [first, second];
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) => pending.removeAt(0).future);
      when(() => taskRepo.createTask(any())).thenAnswer((inv) async {
        return Right(inv.positionalArguments.first as Task);
      });
      final notifier = c.read(taskListNotifierProvider.notifier);

      await notifier.addTask(plain);
      await notifier.addTask(withProject);
      expect(ids(c), [1, 2, 10, 11]);

      second.complete(Right([withProject, plain, a, b]));
      await _settle();
      expect(ids(c), [1, 2, 10, 11]);
      first.complete(Right([plain, a, b])); // stale: from before the 2nd create
      await _settle();

      expect(ids(c), [1, 2, 10, 11], reason: 'stale first refresh must not drop task 1');
    });

    test(
      'a failed refresh keeps the list (created task included), no error/loading state',
      () async {
        final c = makeContainer();
        final states = await listenAll(c);
        when(() => taskRepo.createTask(any())).thenAnswer((_) async => Right(withProject));
        when(
          () => taskRepo.getTasksByFilter(any()),
        ).thenAnswer((_) async => const Left(NetworkFailure('Sunucuya bağlanılamıyor')));

        final result = await c.read(taskListNotifierProvider.notifier).addTask(withProject);
        await _settle();

        expect(result.isRight(), isTrue);
        expect(ids(c), [1, 10, 11]);
        expect(states.any((s) => s.isLoading || s.hasError), isFalse);
      },
    );
  });

  group('addTask failure', () {
    test('Left: list untouched, nothing re-fetched or invalidated, failure returned', () async {
      final c = makeContainer();
      await listenAll(c);
      const failure = ServerFailure('Seçilen proje bulunamadı.', statusCode: 404);
      when(() => taskRepo.createTask(any())).thenAnswer((_) async => const Left(failure));

      final result = await c.read(taskListNotifierProvider.notifier).addTask(withProject);
      await _settle();

      expect(result, const Left<Failure, void>(failure));
      expect(ids(c), [10, 11]);
      expect((projectRepo.listCalls, projectRepo.activeCalls), (1, 1));
      verify(() => taskRepo.getTasksByFilter(any())).called(1);
      verify(() => planRepo.getPlan(_day)).called(1);
    });
  });

  test('without any listener (form opened directly) the request finishes without errors', () async {
    final c = makeContainer();
    final create = Completer<Either<Failure, Task>>();
    when(() => taskRepo.createTask(any())).thenAnswer((_) => create.future);

    final pendingResult = c.read(taskListNotifierProvider.notifier).addTask(withProject);
    await _settle(); // an unkept autoDispose provider would be disposed here
    expect(c.exists(taskListNotifierProvider), isTrue, reason: 'kept alive while the request runs');
    create.complete(Right(withProject));

    expect((await pendingResult).isRight(), isTrue);
    await _settle();
    verify(() => taskRepo.createTask(any())).called(1);
  });
}
