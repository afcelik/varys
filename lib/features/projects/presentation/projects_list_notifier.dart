import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/projects/presentation/active_projects_notifier.dart';

/// Every (not deleted) project plus the active limit, for the projects page
/// and the project form.
@immutable
class ProjectsOverview {
  const ProjectsOverview({required this.projects, required this.limits});

  final List<Project> projects;
  final ProjectLimits limits;

  @override
  bool operator ==(Object other) =>
      other is ProjectsOverview && other.limits == limits && listEquals(other.projects, projects);

  @override
  int get hashCode => Object.hash(limits, Object.hashAll(projects));
}

/// All projects (`GET /projects`, no status filter) and `GET /projects/limits`,
/// loaded in parallel, plus create/update/delete.
///
/// Mutations are not optimistic: the list changes only after the server
/// answers. On success the server result is applied at once (create adds,
/// update replaces, delete removes), the Home "Aktif Projeler" card
/// ([activeProjectsProvider]) is invalidated exactly once, and the list and
/// limits are re-fetched silently (no loading state; only the newest refresh
/// may write). Nothing invalidates this provider from the Home side, so there
/// is no invalidation loop.
///
/// Active count: when a server result is applied, `limits.activeCount` is
/// recounted locally from the list (the list holds every status). That value
/// is only an optimistic interim one. When the silent refresh brings the
/// server's limits, they replace it, and whether "Aktif" can be chosen
/// ([canChooseActive]) is then computed from the server value.
///
/// Failures: a 409 [ActiveProjectLimitFailure] means the local count was
/// stale, so the list and limits are re-fetched silently (the state stays
/// data, never [AsyncError]). A 404 on update/delete (deleted elsewhere)
/// also re-fetches silently. The caller shows the message.
class ProjectsListNotifier extends AutoDisposeAsyncNotifier<ProjectsOverview> {
  /// Bumped on every build and on dispose; async work captured with an older
  /// value must not write state.
  int _generation = 0;

  /// Numbers silent refreshes; only the newest one may apply its result.
  int _refreshSeq = 0;

  static const String unexpectedMessage = 'Beklenmeyen bir hata oluştu';

  @override
  Future<ProjectsOverview> build() async {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    final repository = await ref.watch(projectRepositoryProvider.future);
    if (generation != _generation) throw const _Superseded();
    final result = await _load(repository);
    if (generation != _generation) throw const _Superseded();
    return result.fold((failure) => throw failure, (overview) => overview);
  }

  Future<Either<Failure, Project>> createProject(ProjectDraft draft) {
    return _mutate(
      'create',
      (repo) => repo.createProject(draft),
      apply: (list, created) => [...list.where((p) => p.id != created.id), created],
    );
  }

  /// Sends only [changes]. Empty changes send no request and return
  /// `Right(null)`.
  Future<Either<Failure, Project?>> updateProject(int id, ProjectChanges changes) async {
    if (changes.isEmpty) return const Right(null);
    return _mutate<Project?>(
      'update',
      (repo) => repo.updateProject(id, changes),
      apply: (list, updated) => [for (final p in list) p.id == id ? updated! : p],
      refreshOnNotFound: true,
    );
  }

  Future<Either<Failure, void>> deleteProject(int id) {
    return _mutate<void>(
      'delete',
      (repo) => repo.deleteProject(id),
      apply: (list, _) => list.where((p) => p.id != id).toList(),
      refreshOnNotFound: true,
    );
  }

  static Future<Either<Failure, ProjectsOverview>> _load(ProjectRepository repository) async {
    final projectsFuture = repository.getProjects();
    final limitsFuture = repository.getLimits();
    final projectsResult = await projectsFuture;
    final limitsResult = await limitsFuture;
    return projectsResult.fold(
      Left.new,
      (projects) => limitsResult.fold(
        Left.new,
        (limits) => Right(ProjectsOverview(projects: projects, limits: limits)),
      ),
    );
  }

  /// Runs [op]; keeps the provider alive while it is in flight so a closed
  /// page (no listener) does not dispose it mid-request.
  Future<Either<Failure, T>> _mutate<T>(
    String name,
    Future<Either<Failure, T>> Function(ProjectRepository repo) op, {
    required List<Project> Function(List<Project> list, T value) apply,
    bool refreshOnNotFound = false,
  }) async {
    final link = ref.keepAlive();
    final generation = _generation;
    try {
      final repository = await ref.read(projectRepositoryProvider.future);
      final result = await op(repository);
      return result.fold(
        (failure) {
          final staleCount = failure is ActiveProjectLimitFailure;
          final goneElsewhere =
              refreshOnNotFound && failure is ServerFailure && failure.statusCode == 404;
          if ((staleCount || goneElsewhere) && generation == _generation) {
            unawaited(_silentRefresh(generation));
          }
          return Left(failure);
        },
        (value) {
          if (generation == _generation) {
            final current = state.valueOrNull;
            if (current != null) {
              final projects = apply(current.projects, value);
              state = AsyncData(
                ProjectsOverview(
                  projects: projects,
                  limits: current.limits.copyWith(
                    activeCount: projects.where((p) => p.status == ProjectStatus.active).length,
                  ),
                ),
              );
            }
            ref.invalidate(activeProjectsProvider);
            unawaited(_silentRefresh(generation));
          }
          return Right(value);
        },
      );
    } catch (e, stackTrace) {
      // Safety net only: repositories return Left instead of throwing.
      if (kDebugMode) debugPrint('ProjectsListNotifier.$name error: $e\n$stackTrace');
      return const Left(UnknownFailure(unexpectedMessage));
    } finally {
      link.close();
    }
  }

  /// Re-fetches list and limits without a loading state. Errors are ignored
  /// (the current state stays). If the first load is still running it is
  /// restarted so it cannot return data from before the mutation.
  Future<void> _silentRefresh(int generation) async {
    if (!state.hasValue && state.isLoading) {
      ref.invalidateSelf();
      return;
    }
    final seq = ++_refreshSeq;
    try {
      final repository = await ref.read(projectRepositoryProvider.future);
      if (seq != _refreshSeq || generation != _generation) return;
      final result = await _load(repository);
      if (seq != _refreshSeq || generation != _generation) return;
      result.fold((_) {}, (fresh) => state = AsyncData(fresh));
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('ProjectsListNotifier refresh error: $e\n$stackTrace');
    }
  }
}

/// Thrown by an outdated build. Riverpod ignores errors and values of a build
/// that is no longer current, so this never reaches the UI.
class _Superseded implements Exception {
  const _Superseded();
}

final projectsListProvider =
    AsyncNotifierProvider.autoDispose<ProjectsListNotifier, ProjectsOverview>(
      ProjectsListNotifier.new,
    );
