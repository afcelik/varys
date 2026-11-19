import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/projects/presentation/active_projects_notifier.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';

typedef _ProjectResult = Either<Failure, Project>;
typedef _VoidResult = Either<Failure, void>;

/// Fake repository holding the "server" state. Reads answer from [server]
/// and [serverLimits] (or the count of active projects in [server]); each
/// mutation is parked on a Completer so the test decides when and how the
/// server answers. Calls are counted per endpoint and caller:
/// `GET /projects` (page, no filter), `GET /projects?status=active` (Home
/// card) and `GET /projects/limits` (both).
class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this.server);

  List<Project> server;
  ProjectLimits? serverLimits;
  int maxActive = 3;

  int listCalls = 0;
  int activeCalls = 0;
  int limitsCalls = 0;

  /// When set, `GET /projects` (no filter) waits on it.
  Completer<void>? listGate;

  final creates = <(Map<String, dynamic>, Completer<_ProjectResult>)>[];
  final updates = <(int, Map<String, dynamic>, Completer<_ProjectResult>)>[];
  final deletes = <(int, Completer<_VoidResult>)>[];

  ProjectLimits get currentLimits =>
      serverLimits ??
      ProjectLimits(
        maxActive: maxActive,
        activeCount: server.where((p) => p.status == ProjectStatus.active).length,
      );

  @override
  Future<Either<Failure, List<Project>>> getProjects({ProjectStatus? status}) async {
    if (status == null) {
      listCalls++;
      final gate = listGate;
      if (gate != null) await gate.future;
      return Right(List.of(server));
    }
    activeCalls++;
    return Right(server.where((p) => p.status == status).toList());
  }

  @override
  Future<Either<Failure, ProjectLimits>> getLimits() async {
    limitsCalls++;
    return Right(currentLimits);
  }

  @override
  Future<_ProjectResult> createProject(ProjectDraft draft) {
    final c = Completer<_ProjectResult>();
    creates.add((draft.toBody(), c));
    return c.future;
  }

  @override
  Future<_ProjectResult> updateProject(int id, ProjectChanges changes) {
    final c = Completer<_ProjectResult>();
    updates.add((id, changes.toBody(), c));
    return c.future;
  }

  @override
  Future<_VoidResult> deleteProject(int id) {
    final c = Completer<_VoidResult>();
    deletes.add((id, c));
    return c.future;
  }
}

const _serverError = ServerFailure(
  'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
  statusCode: 500,
);
const _notFound = ServerFailure('Kaynak bulunamadı.', statusCode: 404);

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// Real GET /projects: ids 1..5; 1 and 2 active, 3 on hold, 4 someday,
/// 5 completed (limits fixture: 3 max, 2 active).
List<Project> _fixture() => (_read('projects_list.json') as List)
    .map((e) => Project.fromJson(e as Map<String, dynamic>))
    .toList();

/// Real POST /projects 201 body (active, no tasks), given a new id.
Project _created({int id = 6, ProjectStatus status = ProjectStatus.active}) => Project.fromJson(
  _read('project_created.json') as Map<String, dynamic>,
).copyWith(id: id, status: status);

const _draft = ProjectDraft(title: 'Yeni proje', status: ProjectStatus.active);

Future<void> _flush() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _FakeProjectRepository repo;
  late ProviderContainer container;
  late List<Project> base;

  ProjectsListNotifier notifier() => container.read(projectsListProvider.notifier);
  ProjectsOverview overview() => container.read(projectsListProvider).requireValue;
  List<int> ids() => overview().projects.map((p) => p.id).toList();

  setUp(() async {
    base = _fixture();
    repo = _FakeProjectRepository(List.of(base));
    container = ProviderContainer(
      overrides: [projectRepositoryProvider.overrideWith((ref) async => repo)],
    );
    container.listen(projectsListProvider, (_, _) {}); // open /projects page
    await _flush();
  });

  tearDown(() => container.dispose());

  /// Also keeps the Home "Aktif Projeler" card alive.
  Future<void> listenHomeCard() async {
    container.listen(activeProjectsProvider, (_, _) {});
    await _flush();
  }

  test('build loads every project (no status filter) and the limits in parallel', () {
    expect(ids(), [1, 2, 3, 4, 5]);
    expect(overview().limits, const ProjectLimits(maxActive: 3, activeCount: 2));
    expect((repo.listCalls, repo.limitsCalls, repo.activeCalls), (1, 1, 0));
  });

  test('build failure -> AsyncError holding the Failure', () async {
    final failing = _FailingRepository();
    final c = ProviderContainer(
      overrides: [projectRepositoryProvider.overrideWith((ref) async => failing)],
    );
    addTearDown(c.dispose);
    c.listen(projectsListProvider, (_, _) {});
    await _flush();
    expect(c.read(projectsListProvider).error, _serverError);
  });

  group('createProject', () {
    test('not optimistic: nothing changes until the server answers', () async {
      final future = notifier().createProject(_draft);
      await _flush();
      expect(ids(), [1, 2, 3, 4, 5]);
      expect(repo.creates.single.$1['title'], 'Yeni proje');

      repo.creates.single.$2.complete(Right(_created()));
      expect(await future, isA<Right<Failure, Project>>());
    });

    test(
      'server result applied at once; active count recounted locally as interim value',
      () async {
        repo.listGate = Completer<void>(); // hold the silent refresh
        final future = notifier().createProject(_draft);
        await _flush();
        repo.server = [...base, _created()];
        repo.creates.single.$2.complete(Right(_created()));
        await future;

        expect(ids(), [1, 2, 3, 4, 5, 6], reason: 'applied before the refresh answers');
        expect(overview().limits.activeCount, 3);
        repo.listGate!.complete();
      },
    );

    test('success: Home card invalidated exactly once, one silent refresh, no loop', () async {
      await listenHomeCard();
      // Initial: page list + limits, card active list + limits.
      expect((repo.listCalls, repo.activeCalls, repo.limitsCalls), (1, 1, 2));

      final future = notifier().createProject(_draft);
      await _flush();
      repo.server = [...base, _created()];
      repo.creates.single.$2.complete(Right(_created()));
      await future;
      await _flush();

      // One page refresh (list + limits) and one card reload (active + limits).
      expect((repo.listCalls, repo.activeCalls, repo.limitsCalls), (2, 2, 4));
      expect(container.read(activeProjectsProvider).requireValue.projects.map((p) => p.id), [
        1,
        2,
        6,
      ]);

      // Nothing keeps going on its own: no loop.
      await _flush();
      await _flush();
      expect((repo.listCalls, repo.activeCalls, repo.limitsCalls), (2, 2, 4));

      // Reloading the card (its "Tekrar dene") does not reload the page list.
      container.invalidate(activeProjectsProvider);
      await _flush();
      expect((repo.listCalls, repo.activeCalls, repo.limitsCalls), (2, 3, 5));
    });

    test('silent refresh replaces the local active count with the server limits', () async {
      final future = notifier().createProject(_draft);
      await _flush();
      // Meanwhile another client put project 1 on hold: the server counts 2.
      repo.server = [
        for (final p in base) p.id == 1 ? p.copyWith(status: ProjectStatus.onHold) : p,
        _created(),
      ];
      repo.serverLimits = const ProjectLimits(maxActive: 3, activeCount: 2);
      repo.listGate = Completer<void>();
      repo.creates.single.$2.complete(Right(_created()));
      await future;

      expect(overview().limits.activeCount, 3, reason: 'interim local count');
      expect(canChooseActive(overview().limits), isFalse);

      repo.listGate!.complete();
      await _flush();
      expect(overview().limits, const ProjectLimits(maxActive: 3, activeCount: 2));
      expect(canChooseActive(overview().limits), isTrue, reason: 'computed from server value');
    });

    test('409 with a stale local count (2/3): list and limits re-fetched, limits become 3/3, '
        'state never AsyncError and the old list stays meanwhile', () async {
      await listenHomeCard();
      expect(overview().limits, const ProjectLimits(maxActive: 3, activeCount: 2));
      expect(canChooseActive(overview().limits), isTrue);
      final callsBefore = (repo.listCalls, repo.limitsCalls, repo.activeCalls);

      // Another client activated project 3: the server is full.
      final serverList = [
        for (final p in base) p.id == 3 ? p.copyWith(status: ProjectStatus.active) : p,
      ];
      repo.server = serverList;
      repo.listGate = Completer<void>();

      final states = <AsyncValue<ProjectsOverview>>[];
      container.listen(projectsListProvider, (_, next) => states.add(next));

      final future = notifier().createProject(_draft);
      await _flush();
      repo.creates.single.$2.complete(const Left(ActiveProjectLimitFailure()));
      final result = await future;

      expect(result.fold((f) => f, (_) => null), isA<ActiveProjectLimitFailure>());
      await _flush();
      // Refresh in flight: the old list is still shown, no loading/error.
      expect(container.read(projectsListProvider).hasError, isFalse);
      expect(container.read(projectsListProvider).isLoading, isFalse);
      expect(ids(), [1, 2, 3, 4, 5]);
      expect(overview().projects.firstWhere((p) => p.id == 3).status, ProjectStatus.onHold);

      repo.listGate!.complete();
      await _flush();
      expect(overview().projects, serverList);
      expect(overview().limits, const ProjectLimits(maxActive: 3, activeCount: 3));
      expect(canChooseActive(overview().limits), isFalse);
      expect(states.any((s) => s.hasError), isFalse);

      // Exactly one page refresh; the failed request does not touch the card.
      expect(
        (repo.listCalls, repo.limitsCalls, repo.activeCalls),
        (callsBefore.$1 + 1, callsBefore.$2 + 1, callsBefore.$3),
      );
    });

    test('other failure: Left, list unchanged, no refresh, card not invalidated', () async {
      await listenHomeCard();
      final calls = (repo.listCalls, repo.limitsCalls, repo.activeCalls);

      final future = notifier().createProject(_draft);
      await _flush();
      repo.creates.single.$2.complete(const Left(_serverError));

      expect((await future).fold((f) => f, (_) => null), _serverError);
      await _flush();
      expect(ids(), [1, 2, 3, 4, 5]);
      expect((repo.listCalls, repo.limitsCalls, repo.activeCalls), calls);
    });
  });

  group('updateProject', () {
    test('sends only the changes; result replaces the row at once', () async {
      repo.listGate = Completer<void>();
      final updated = base[0].copyWith(title: 'Yeni ad', status: ProjectStatus.onHold);
      final future = notifier().updateProject(
        1,
        const ProjectChanges(
          title: PlanField.set('Yeni ad'),
          status: PlanField.set(ProjectStatus.onHold),
        ),
      );
      await _flush();
      expect(repo.updates.single.$1, 1);
      expect(repo.updates.single.$2, {'title': 'Yeni ad', 'status': 'on_hold'});

      repo.server = [updated, ...base.skip(1)];
      repo.updates.single.$3.complete(Right(updated));
      await future;

      expect(overview().projects.first.title, 'Yeni ad');
      expect(overview().limits.activeCount, 1);
      repo.listGate!.complete();
      await _flush();
      expect(overview().projects.first, updated);
    });

    test('a pending older refresh cannot overwrite a newer result', () async {
      // First mutation's refresh is held on the gate...
      repo.listGate = Completer<void>();
      final first = notifier().deleteProject(4);
      await _flush();
      repo.deletes.single.$2.complete(const Right(null));
      await first;
      final oldGate = repo.listGate!;

      // ...a second mutation starts a newer refresh that answers first.
      repo.listGate = null;
      final renamed = base[0].copyWith(title: 'Sonraki');
      repo.server = [renamed, base[1], base[2], base[4]];
      final second = notifier().updateProject(
        1,
        const ProjectChanges(title: PlanField.set('Sonraki')),
      );
      await _flush();
      repo.updates.single.$3.complete(Right(renamed));
      await second;
      await _flush();
      expect(overview().projects.first.title, 'Sonraki');

      // The stale refresh now answers; its result is dropped.
      repo.server = base;
      oldGate.complete();
      await _flush();
      expect(ids(), [1, 2, 3, 5]);
      expect(overview().projects.first.title, 'Sonraki');
    });

    test('empty changes: Right(null), no request, nothing invalidated', () async {
      await listenHomeCard();
      final calls = (repo.listCalls, repo.limitsCalls, repo.activeCalls);

      final result = await notifier().updateProject(1, const ProjectChanges());

      expect(result, const Right<Failure, Project?>(null));
      await _flush();
      expect(repo.updates, isEmpty);
      expect((repo.listCalls, repo.limitsCalls, repo.activeCalls), calls);
    });

    test('409 on activation: Left(limit) and a silent refresh', () async {
      final calls = repo.listCalls;
      final future = notifier().updateProject(
        3,
        const ProjectChanges(status: PlanField.set(ProjectStatus.active)),
      );
      await _flush();
      repo.updates.single.$3.complete(const Left(ActiveProjectLimitFailure()));

      expect((await future).fold((f) => f, (_) => null), isA<ActiveProjectLimitFailure>());
      await _flush();
      expect(repo.listCalls, calls + 1);
      expect(container.read(projectsListProvider).hasError, isFalse);
    });

    test('404 (deleted elsewhere): Left with fixed text; silent refresh drops the row', () async {
      final future = notifier().updateProject(2, const ProjectChanges(title: PlanField.set('X')));
      await _flush();
      repo.server = base.where((p) => p.id != 2).toList();
      repo.updates.single.$3.complete(const Left(_notFound));

      final failure = (await future).fold((f) => f, (_) => null);
      expect(failure, _notFound);
      expect(failure!.userMessage, 'Kaynak bulunamadı.');
      await _flush();
      expect(ids(), [1, 3, 4, 5]);
      expect(overview().limits.activeCount, 1);
      expect(container.read(projectsListProvider).hasError, isFalse);
    });

    test('non-404 failure: no re-fetch, old list stays', () async {
      final calls = repo.listCalls;
      final future = notifier().updateProject(2, const ProjectChanges(title: PlanField.set('X')));
      await _flush();
      repo.updates.single.$3.complete(const Left(_serverError));
      await future;
      await _flush();
      expect(repo.listCalls, calls);
      expect(overview().projects[1].title, base[1].title);
    });
  });

  group('deleteProject', () {
    test('success: row removed at once, count recounted, card invalidated once', () async {
      await listenHomeCard();
      repo.listGate = Completer<void>();
      final future = notifier().deleteProject(1);
      await _flush();
      repo.server = base.skip(1).toList();
      repo.deletes.single.$2.complete(const Right(null));
      await future;

      expect(ids(), [2, 3, 4, 5]);
      expect(overview().limits.activeCount, 1);
      await _flush();
      expect(repo.activeCalls, 2);
      expect(container.read(activeProjectsProvider).requireValue.projects.map((p) => p.id), [2]);
      repo.listGate!.complete();
      await _flush();
      expect(repo.listCalls, 2);
      expect(repo.activeCalls, 2);
    });

    test('404: Left and a silent refresh', () async {
      final future = notifier().deleteProject(5);
      await _flush();
      repo.server = base.take(4).toList();
      repo.deletes.single.$2.complete(const Left(_notFound));
      expect((await future).fold((f) => f, (_) => null), _notFound);
      await _flush();
      expect(ids(), [1, 2, 3, 4]);
    });

    test('failure: old list stays', () async {
      final future = notifier().deleteProject(1);
      await _flush();
      repo.deletes.single.$2.complete(const Left(_serverError));
      await future;
      await _flush();
      expect(ids(), [1, 2, 3, 4, 5]);
    });
  });

  group('lifecycle', () {
    test('list invalidated while a mutation is in flight: no crash, no stale write', () async {
      final future = notifier().createProject(_draft);
      await _flush();
      container.invalidate(projectsListProvider);
      await _flush();
      final callsAfterRebuild = repo.listCalls;
      repo.server = [...base, _created()];
      repo.creates.single.$2.complete(Right(_created()));

      expect(await future, isA<Right<Failure, Project>>());
      await _flush();
      // The rebuilt state is its own load; the outdated mutation neither
      // patches it nor starts a refresh.
      expect(ids(), [1, 2, 3, 4, 5]);
      expect(repo.listCalls, callsAfterRebuild);
    });

    test('session-end style invalidation of both providers mid-request: no exception', () async {
      await listenHomeCard();
      final future = notifier().deleteProject(1);
      await _flush();
      container.invalidate(projectsListProvider);
      container.invalidate(activeProjectsProvider);
      repo.deletes.single.$2.complete(const Right(null));
      expect(await future, const Right<Failure, void>(null));
      await _flush();
      expect(container.read(projectsListProvider).hasError, isFalse);
    });

    test('container disposed while a mutation is in flight: completes without throwing', () async {
      final future = notifier().createProject(_draft);
      await _flush();
      container.dispose();
      repo.creates.single.$2.complete(Right(_created()));
      expect(await future, isA<Right<Failure, Project>>());
      container = ProviderContainer(); // for tearDown
    });

    test('no listener (form opened directly): request completes, no exception', () async {
      final c = ProviderContainer(
        overrides: [projectRepositoryProvider.overrideWith((ref) async => repo)],
      );
      addTearDown(c.dispose);
      final future = c.read(projectsListProvider.notifier).createProject(_draft);
      await _flush();
      repo.creates.single.$2.complete(Right(_created()));
      expect(await future, isA<Right<Failure, Project>>());
      await _flush();
    });

    test('mutation during the first load restarts it instead of applying stale data', () async {
      final c = ProviderContainer(
        overrides: [projectRepositoryProvider.overrideWith((ref) async => repo)],
      );
      addTearDown(c.dispose);
      repo.listGate = Completer<void>();
      c.listen(projectsListProvider, (_, _) {});
      await _flush();
      expect(c.read(projectsListProvider).isLoading, isTrue);

      final future = c.read(projectsListProvider.notifier).createProject(_draft);
      await _flush();
      repo.server = [...base, _created()];
      repo.creates.single.$2.complete(Right(_created()));
      await future;
      repo.listGate!.complete();
      repo.listGate = null;
      await _flush();
      expect(c.read(projectsListProvider).requireValue.projects.map((p) => p.id), [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
    });
  });
}

class _FailingRepository extends _FakeProjectRepository {
  _FailingRepository() : super(const []);

  @override
  Future<Either<Failure, List<Project>>> getProjects({ProjectStatus? status}) async =>
      const Left(_serverError);
}
