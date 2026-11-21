// Completing (or reopening) a task changes its project's progress: a
// successful toggle of a task linked to a project reloads the projects page
// list and the Home "Aktif Projeler" card once each; a task without a project
// or a failed toggle reloads neither.

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
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

Task _task(int id, {int? projectId, TaskStatus status = TaskStatus.todo}) => Task(
  id: id,
  title: 'Görev $id',
  status: status,
  createdAt: DateTime(2026, 11, 1),
  updatedAt: DateTime(2026, 11, 1),
  projectId: projectId,
);

void main() {
  late _MockTaskRepository taskRepo;
  late _MockDailyPlanRepository planRepo;
  late FakeProjectRepository projectRepo;
  late ProviderContainer container;

  final linked = _task(1, projectId: 1);
  final loose = _task(2);

  setUpAll(() {
    registerFallbackValue(TaskFilter.all);
    registerFallbackValue(TaskStatus.todo);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() async {
    taskRepo = _MockTaskRepository();
    planRepo = _MockDailyPlanRepository();
    projectRepo = FakeProjectRepository();
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([linked, loose]));
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
    container = ProviderContainer(
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        taskRepositoryProvider.overrideWith((ref) async => taskRepo),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectRepo),
      ],
    );
    container.listen(taskListNotifierProvider, (_, _) {});
    container.listen(projectsListProvider, (_, _) {});
    container.listen(activeProjectsProvider, (_, _) {});
    await container.read(taskListNotifierProvider.future);
    await container.read(projectsListProvider.future);
    await container.read(activeProjectsProvider.future);
    expect(projectRepo.listCalls, 1);
    expect(projectRepo.activeCalls, 1);
  });

  tearDown(() => container.dispose());

  Future<void> settle() async {
    await container.read(projectsListProvider.future);
    await container.read(activeProjectsProvider.future);
    await Future<void>.delayed(Duration.zero);
  }

  test('task with a project done: projects list and Home card reloaded once each', () async {
    when(
      () => taskRepo.updateTaskStatus(1, TaskStatus.done),
    ).thenAnswer((_) async => Right(linked.copyWith(status: TaskStatus.done)));

    final result = await container.read(taskListNotifierProvider.notifier).toggleTaskCompletion(1);
    await settle();

    expect(result.isRight(), isTrue);
    expect(projectRepo.listCalls, 2);
    expect(projectRepo.activeCalls, 2);
  });

  test('reopening a done task with a project also reloads them once', () async {
    final done = _task(3, projectId: 2, status: TaskStatus.done);
    when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right([done]));
    container.invalidate(taskListNotifierProvider);
    await container.read(taskListNotifierProvider.future);
    when(
      () => taskRepo.updateTaskStatus(3, TaskStatus.todo),
    ).thenAnswer((_) async => Right(done.copyWith(status: TaskStatus.todo)));

    final result = await container.read(taskListNotifierProvider.notifier).toggleTaskCompletion(3);
    await settle();

    expect(result.isRight(), isTrue);
    expect(projectRepo.listCalls, 2);
    expect(projectRepo.activeCalls, 2);
  });

  test('task without a project: projects are not reloaded', () async {
    when(
      () => taskRepo.updateTaskStatus(2, TaskStatus.done),
    ).thenAnswer((_) async => Right(loose.copyWith(status: TaskStatus.done)));

    final result = await container.read(taskListNotifierProvider.notifier).toggleTaskCompletion(2);
    await settle();

    expect(result.isRight(), isTrue);
    expect(projectRepo.listCalls, 1);
    expect(projectRepo.activeCalls, 1);
  });

  test('failed toggle of a task with a project: rolled back, projects not reloaded', () async {
    when(
      () => taskRepo.updateTaskStatus(1, TaskStatus.done),
    ).thenAnswer((_) async => const Left(NetworkFailure('Sunucuya bağlanılamıyor')));

    final result = await container.read(taskListNotifierProvider.notifier).toggleTaskCompletion(1);
    await settle();

    expect(result.isLeft(), isTrue);
    final tasks = container.read(taskListNotifierProvider).value!.tasks.value!;
    expect(tasks.firstWhere((t) => t.id == 1).status, TaskStatus.todo);
    expect(projectRepo.listCalls, 1);
    expect(projectRepo.activeCalls, 1);
  });
}
