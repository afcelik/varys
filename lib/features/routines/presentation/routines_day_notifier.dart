import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';

/// Routines scheduled on one day (the family argument), with completion and
/// streaks. Toggles are optimistic; only the affected item is rolled back.
class RoutinesDayNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<RoutineDayItem>, DateTime> {
  /// Bumped on every build and on dispose. Async work captured with an older
  /// value must not write state (list reloaded, provider disposed).
  int _generation = 0;

  /// Numbers silent refreshes; only the newest one may apply its result.
  int _refreshSeq = 0;

  /// Routine ids with a mark/undo request in flight.
  final Set<int> _inFlight = <int>{};

  static const String notLoadedMessage = 'Rutinler henüz yüklenmedi.';
  static const String unexpectedMessage = 'Beklenmeyen bir hata oluştu';

  @override
  Future<List<RoutineDayItem>> build(DateTime day) async {
    _generation++;
    ref.onDispose(() => _generation++);
    final repository = await ref.watch(routineRepositoryProvider.future);
    final result = await repository.getRoutinesForDay(day);
    return result.fold((failure) => throw failure, (items) => items);
  }

  /// Whether a mark/undo request for [routineId] is in flight.
  bool isPending(int routineId) => _inFlight.contains(routineId);

  /// Flips completion of [routineId] on this day.
  ///
  /// Returns Left on failure (the caller shows `userMessage`); the item's
  /// previous completion is restored. While a request for the same routine is
  /// in flight, a second call sends nothing and returns Right.
  Future<Either<Failure, void>> toggle(int routineId) async {
    final items = state.valueOrNull;
    if (items == null) return const Left(ValidationFailure(notLoadedMessage));
    final index = items.indexWhere((i) => i.id == routineId);
    if (index < 0) return const Left(ValidationFailure(notLoadedMessage));
    if (_inFlight.contains(routineId)) return const Right(null);

    final day = arg;
    final generation = _generation;
    final wasCompleted = items[index].completed;

    _inFlight.add(routineId);
    _setCompleted(routineId, !wasCompleted);

    try {
      final repository = await ref.read(routineRepositoryProvider.future);
      if (!_isCurrent(generation)) return const Right(null);

      final result = wasCompleted
          ? await repository.undo(routineId, day)
          : await repository.markDone(routineId, day);

      return result.fold(
        (failure) {
          if (_isCurrent(generation)) _setCompleted(routineId, wasCompleted);
          return Left(failure);
        },
        (_) {
          if (_isCurrent(generation)) unawaited(_silentRefresh(generation));
          return const Right(null);
        },
      );
    } catch (e, stackTrace) {
      // Safety net only: repositories return Left instead of throwing.
      if (kDebugMode) debugPrint('RoutinesDayNotifier.toggle error: $e\n$stackTrace');
      if (_isCurrent(generation)) _setCompleted(routineId, wasCompleted);
      return const Left(UnknownFailure(unexpectedMessage));
    } finally {
      _inFlight.remove(routineId);
    }
  }

  /// Re-fetches the day after a successful toggle so streaks update. Never
  /// shows loading and never surfaces errors: on failure the optimistic state
  /// stays. Only the newest refresh applies; items still in flight keep their
  /// optimistic completion.
  Future<void> _silentRefresh(int generation) async {
    final seq = ++_refreshSeq;
    try {
      final repository = await ref.read(routineRepositoryProvider.future);
      if (!_isCurrent(generation)) return;
      final result = await repository.getRoutinesForDay(arg);
      if (seq != _refreshSeq || !_isCurrent(generation)) return;
      final current = state.valueOrNull;
      if (current == null) return;
      result.fold((_) {}, (fresh) {
        final optimistic = {
          for (final item in current)
            if (_inFlight.contains(item.id)) item.id: item.completed,
        };
        state = AsyncData([
          for (final item in fresh)
            optimistic.containsKey(item.id)
                ? item.copyWith(completed: optimistic[item.id]!)
                : item,
        ]);
      });
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('RoutinesDayNotifier refresh error: $e\n$stackTrace');
    }
  }

  bool _isCurrent(int generation) =>
      generation == _generation && state.valueOrNull != null;

  /// Changes only [routineId] in the latest state.
  void _setCompleted(int routineId, bool completed) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final item in current)
        item.id == routineId ? item.copyWith(completed: completed) : item,
    ]);
  }
}

/// Routines for a given plain calendar day.
final routinesForDayProvider = AsyncNotifierProvider.autoDispose
    .family<RoutinesDayNotifier, List<RoutineDayItem>, DateTime>(RoutinesDayNotifier.new);

/// Today's routines; follows [todayProvider], so a day change loads the new day.
final todayRoutinesProvider = Provider.autoDispose<AsyncValue<List<RoutineDayItem>>>((ref) {
  return ref.watch(routinesForDayProvider(ref.watch(todayProvider)));
});
