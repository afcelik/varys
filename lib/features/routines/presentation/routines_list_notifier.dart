import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/routines/presentation/routines_day_notifier.dart';

/// All routines (`GET /routines`) plus create/update/delete.
///
/// Mutations are not optimistic: the list changes only after the server
/// answers. On success the server result is applied at once, the list is
/// re-fetched silently (no loading state) and the day routines (Home card)
/// are invalidated exactly once. Nothing here invalidates this provider from
/// the day side, so there is no invalidation loop.
class RoutinesListNotifier extends AutoDisposeAsyncNotifier<List<Routine>> {
  /// Bumped on every build and on dispose; async work captured with an older
  /// value must not write state.
  int _generation = 0;

  /// Numbers silent refreshes; only the newest one may apply its result.
  int _refreshSeq = 0;

  static const String unexpectedMessage = 'Beklenmeyen bir hata oluştu';

  @override
  Future<List<Routine>> build() async {
    _generation++;
    ref.onDispose(() => _generation++);
    final repository = await ref.watch(routineRepositoryProvider.future);
    final result = await repository.getRoutines();
    return result.fold((failure) => throw failure, (routines) => routines);
  }

  Future<Either<Failure, Routine>> createRoutine({
    required String title,
    String? description,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
  }) {
    return _mutate(
      'create',
      (repo) => repo.createRoutine(
        title: title,
        description: description,
        recurrenceType: recurrenceType,
        daysOfWeek: daysOfWeek,
        dayOfMonth: dayOfMonth,
        intervalDays: intervalDays,
        startDate: startDate,
      ),
      apply: (list, created) => [...list.where((r) => r.id != created.id), created],
    );
  }

  /// Sends only [changes]. Empty changes send no request and return
  /// `Right(null)`.
  Future<Either<Failure, Routine?>> updateRoutine(int id, RoutineChanges changes) async {
    if (changes.isEmpty) return const Right(null);
    return _mutate<Routine?>(
      'update',
      (repo) => repo.updateRoutine(id, changes),
      apply: (list, updated) => [for (final r in list) r.id == id ? updated! : r],
      refreshOnNotFound: true,
    );
  }

  Future<Either<Failure, void>> deleteRoutine(int id) {
    return _mutate<void>(
      'delete',
      (repo) => repo.deleteRoutine(id),
      apply: (list, _) => list.where((r) => r.id != id).toList(),
      refreshOnNotFound: true,
    );
  }

  /// Runs [op]; keeps the provider alive while it is in flight so a closed
  /// page (no listener) does not dispose it mid-request.
  Future<Either<Failure, T>> _mutate<T>(
    String name,
    Future<Either<Failure, T>> Function(RoutineRepository repo) op, {
    required List<Routine> Function(List<Routine> list, T value) apply,
    bool refreshOnNotFound = false,
  }) async {
    final link = ref.keepAlive();
    final generation = _generation;
    try {
      final repository = await ref.read(routineRepositoryProvider.future);
      final result = await op(repository);
      return result.fold(
        (failure) {
          // The routine is gone on the server (deleted elsewhere): re-fetch
          // so the stale row disappears. The caller shows the message.
          if (refreshOnNotFound &&
              failure is ServerFailure &&
              failure.statusCode == 404 &&
              generation == _generation) {
            unawaited(_silentRefresh(generation));
          }
          return Left(failure);
        },
        (value) {
          if (generation == _generation) {
            final current = state.valueOrNull;
            if (current != null) state = AsyncData(apply(current, value));
            ref.invalidate(routinesForDayProvider);
            unawaited(_silentRefresh(generation));
          }
          return Right(value);
        },
      );
    } catch (e, stackTrace) {
      // Safety net only: repositories return Left instead of throwing.
      if (kDebugMode) debugPrint('RoutinesListNotifier.$name error: $e\n$stackTrace');
      return const Left(UnknownFailure(unexpectedMessage));
    } finally {
      link.close();
    }
  }

  /// Re-fetches the list without a loading state. Errors are ignored (the
  /// current list stays). If the first load is still running it is restarted
  /// so it cannot return a list from before the mutation.
  Future<void> _silentRefresh(int generation) async {
    if (!state.hasValue && state.isLoading) {
      ref.invalidateSelf();
      return;
    }
    final seq = ++_refreshSeq;
    try {
      final repository = await ref.read(routineRepositoryProvider.future);
      if (generation != _generation) return;
      final result = await repository.getRoutines();
      if (seq != _refreshSeq || generation != _generation) return;
      result.fold((_) {}, (fresh) => state = AsyncData(fresh));
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('RoutinesListNotifier refresh error: $e\n$stackTrace');
    }
  }
}

final routinesListProvider =
    AsyncNotifierProvider.autoDispose<RoutinesListNotifier, List<Routine>>(
        RoutinesListNotifier.new);
