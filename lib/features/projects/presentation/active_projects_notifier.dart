import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';

/// Active projects plus the active limit, loaded together for the Home card.
@immutable
class ActiveProjects {
  const ActiveProjects({
    required this.projects,
    required this.maxActive,
    required this.activeCount,
  });

  final List<Project> projects;
  final int maxActive;
  final int activeCount;

  @override
  bool operator ==(Object other) =>
      other is ActiveProjects &&
      other.maxActive == maxActive &&
      other.activeCount == activeCount &&
      listEquals(other.projects, projects);

  @override
  int get hashCode => Object.hash(maxActive, activeCount, Object.hashAll(projects));
}

/// `GET /projects?status=active` and `GET /projects/limits`, requested in
/// parallel and exposed as one state. If either fails, the state is that
/// [Failure] (thrown, so `AsyncError.error` is the Failure).
///
/// Refresh with `ref.invalidate(activeProjectsProvider)`: Riverpod keeps the
/// previous value while reloading (`isLoading && hasValue`), so the card keeps
/// showing it instead of flashing the skeleton. A build that was superseded
/// (invalidated, disposed) while awaiting never writes: Riverpod drops its
/// result, and [_generation] makes it stop after each await instead of
/// continuing with a stale repository or stale responses.
class ActiveProjectsNotifier extends AutoDisposeAsyncNotifier<ActiveProjects> {
  int _generation = 0;

  @override
  Future<ActiveProjects> build() async {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);

    final repository = await ref.watch(projectRepositoryProvider.future);
    if (generation != _generation) throw const _Superseded();

    final projectsFuture = repository.getProjects(status: ProjectStatus.active);
    final limitsFuture = repository.getLimits();
    final projectsResult = await projectsFuture;
    final limitsResult = await limitsFuture;
    if (generation != _generation) throw const _Superseded();

    final projects = projectsResult.fold((failure) => throw failure, (p) => p);
    final limits = limitsResult.fold((failure) => throw failure, (l) => l);
    return ActiveProjects(
      projects: projects,
      maxActive: limits.maxActive,
      activeCount: limits.activeCount,
    );
  }
}

/// Thrown by an outdated build. Riverpod ignores errors and values of a build
/// that is no longer current, so this never reaches the UI.
class _Superseded implements Exception {
  const _Superseded();
}

final activeProjectsProvider =
    AsyncNotifierProvider.autoDispose<ActiveProjectsNotifier, ActiveProjects>(
        ActiveProjectsNotifier.new);
