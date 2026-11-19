import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/projects/presentation/active_projects_notifier.dart';

class _MockProjectRepository extends Mock implements ProjectRepository {}

const _failure = ServerFailure('Sunucu hatası. Lütfen daha sonra tekrar deneyin.', statusCode: 500);
const _network = NetworkFailure('timeout');

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late List<Project> active;
  late ProjectLimits limits;
  late _MockProjectRepository repo;
  late ProviderContainer container;

  setUpAll(() {
    registerFallbackValue(ProjectStatus.active);
    active = (jsonDecode(File('test/fixtures/projects_list.json').readAsStringSync()) as List)
        .map((e) => Project.fromJson(e as Map<String, dynamic>))
        .where((p) => p.status == ProjectStatus.active)
        .toList();
    limits = ProjectLimits.fromJson(
        jsonDecode(File('test/fixtures/projects_limits.json').readAsStringSync())
            as Map<String, dynamic>);
  });

  setUp(() {
    repo = _MockProjectRepository();
    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => Right(active));
    when(() => repo.getLimits()).thenAnswer((_) async => Right(limits));
    container = ProviderContainer(overrides: [
      projectRepositoryProvider.overrideWith((ref) async => repo),
    ]);
    // Keep the autoDispose provider alive, as the Home card would.
    container.listen(activeProjectsProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  test('loads the active list and the limits into one state', () async {
    final value = await container.read(activeProjectsProvider.future);

    expect(value.projects, active);
    expect(value.projects.map((p) => p.id), [1, 2]);
    expect(value.maxActive, 3);
    expect(value.activeCount, 2);
    verify(() => repo.getProjects(status: ProjectStatus.active)).called(1);
    verify(() => repo.getLimits()).called(1);
  });

  test('both requests start before either answers (parallel)', () async {
    final projects = Completer<Either<Failure, List<Project>>>();
    when(() => repo.getProjects(status: any(named: 'status'))).thenAnswer((_) => projects.future);
    container.invalidate(activeProjectsProvider);
    await _flush();

    verify(() => repo.getLimits()).called(1); // asked while the list is pending
    projects.complete(Right(active));
    await _flush();
    expect(container.read(activeProjectsProvider).requireValue.projects, active);
  });

  test('list failure -> error state is that Failure', () async {
    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) async => const Left(_failure));
    await _flush();

    final value = container.read(activeProjectsProvider);
    expect(value.hasError, isTrue);
    expect(value.error, _failure);
    expect(value.hasValue, isFalse);
  });

  test('limits failure -> error state even though the list loaded', () async {
    when(() => repo.getLimits()).thenAnswer((_) async => const Left(_network));
    await _flush();

    final value = container.read(activeProjectsProvider);
    expect(value.error, _network);
    expect(value.hasValue, isFalse);
  });

  test('refresh keeps the previous data while reloading, then shows the new data', () async {
    await container.read(activeProjectsProvider.future);
    final pending = Completer<Either<Failure, List<Project>>>();
    when(() => repo.getProjects(status: any(named: 'status'))).thenAnswer((_) => pending.future);

    container.invalidate(activeProjectsProvider);
    await _flush();

    final during = container.read(activeProjectsProvider);
    expect(during.isLoading, isTrue);
    expect(during.hasValue, isTrue, reason: 'old data stays on screen (no skeleton flash)');
    expect(during.requireValue.projects, active);

    pending.complete(Right([active.last]));
    await _flush();
    final after = container.read(activeProjectsProvider);
    expect(after.isLoading, isFalse);
    expect(after.requireValue.projects, [active.last]);
  });

  test('failed refresh after data: error state, previous value still available', () async {
    await container.read(activeProjectsProvider.future);
    when(() => repo.getLimits()).thenAnswer((_) async => const Left(_failure));

    container.invalidate(activeProjectsProvider);
    await _flush();

    final value = container.read(activeProjectsProvider);
    expect(value.error, _failure);
    expect(value.isLoading, isFalse);
  });

  test('invalidate while a load is in flight: no crash, the stale answer is never shown',
      () async {
    final first = Completer<Either<Failure, List<Project>>>();
    final second = Completer<Either<Failure, List<Project>>>();
    final answers = [first, second];
    when(() => repo.getProjects(status: any(named: 'status')))
        .thenAnswer((_) => answers.removeAt(0).future);
    container.invalidate(activeProjectsProvider);
    await _flush();

    container.invalidate(activeProjectsProvider); // while `first` is pending
    await _flush();

    second.complete(Right([active.last]));
    await _flush();
    expect(container.read(activeProjectsProvider).requireValue.projects, [active.last]);

    first.complete(Right(active)); // stale build answers late
    await _flush();
    final value = container.read(activeProjectsProvider);
    expect(value.hasError, isFalse);
    expect(value.requireValue.projects, [active.last]);
  });

  test('dispose while a load is in flight: no error, no state change after dispose', () async {
    final pending = Completer<Either<Failure, List<Project>>>();
    when(() => repo.getProjects(status: any(named: 'status'))).thenAnswer((_) => pending.future);
    final own = ProviderContainer(overrides: [
      projectRepositoryProvider.overrideWith((ref) async => repo),
    ]);
    final seen = <AsyncValue<ActiveProjects>>[];
    own.listen(activeProjectsProvider, (_, next) => seen.add(next), fireImmediately: true);
    await _flush();
    expect(own.read(activeProjectsProvider).isLoading, isTrue);
    verify(() => repo.getProjects(status: ProjectStatus.active)).called(greaterThanOrEqualTo(1));
    final seenBeforeDispose = seen.length;

    own.dispose();
    pending.complete(Right(active)); // answers after dispose
    await _flush();

    expect(seen.length, seenBeforeDispose, reason: 'a disposed provider must not emit');
    expect(seen.whereType<AsyncError<ActiveProjects>>(), isEmpty);
  });
}
