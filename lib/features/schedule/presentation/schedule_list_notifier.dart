import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/domain/schedule_repository.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';

/// All blocks (`GET /schedule`, the /schedule page) plus create/update/delete.
///
/// Mutations are not optimistic: the list changes only after the server
/// answers. On success the server result is applied at once (in start
/// time/id order), the list is re-fetched silently (no loading state, newest
/// refresh wins, a failed refresh keeps the list) and the day lists (Home
/// card) are invalidated exactly once. The day side never invalidates this
/// provider on rebuild, so there is no invalidation loop. A 404 (block gone
/// elsewhere) also refreshes silently and invalidates the day lists once.
class ScheduleListNotifier extends AutoDisposeAsyncNotifier<List<ScheduleBlock>> {
  /// Bumped on every build and on dispose; async work captured with an older
  /// value must not write state.
  int _generation = 0;

  /// Numbers silent refreshes; only the newest one may apply its result.
  int _refreshSeq = 0;

  static const String unexpectedMessage = 'Beklenmeyen bir hata oluştu';

  @override
  Future<List<ScheduleBlock>> build() async {
    _generation++;
    ref.onDispose(() => _generation++);
    final repository = await ref.watch(scheduleRepositoryProvider.future);
    final result = await repository.getBlocks();
    return result.fold((failure) => throw failure, sortBlocks);
  }

  Future<Either<Failure, ScheduleBlock>> createBlock({
    required String title,
    String? description,
    required ScheduleTime startTime,
    required ScheduleTime endTime,
    required RecurrenceType recurrenceType,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
    required DateTime startDate,
  }) {
    return _mutate(
      'create',
      (repo) => repo.createBlock(
        title: title,
        description: description,
        startTime: startTime,
        endTime: endTime,
        recurrenceType: recurrenceType,
        daysOfWeek: daysOfWeek,
        dayOfMonth: dayOfMonth,
        intervalDays: intervalDays,
        startDate: startDate,
      ),
      apply: (list, created) => [...list.where((b) => b.id != created.id), created],
    );
  }

  /// Sends only [changes]. Empty changes send no request and return
  /// `Right(null)`.
  Future<Either<Failure, ScheduleBlock?>> updateBlock(int id, ScheduleChanges changes) async {
    if (changes.isEmpty) return const Right(null);
    return _mutate<ScheduleBlock?>(
      'update',
      (repo) => repo.updateBlock(id, changes),
      apply: (list, updated) => [for (final b in list) b.id == id ? updated! : b],
      refreshOnNotFound: true,
    );
  }

  Future<Either<Failure, void>> deleteBlock(int id) {
    return _mutate<void>(
      'delete',
      (repo) => repo.deleteBlock(id),
      apply: (list, _) => list.where((b) => b.id != id).toList(),
      refreshOnNotFound: true,
    );
  }

  /// Runs [op]; keeps the provider alive while it is in flight so a closed
  /// page (no listener) does not dispose it mid-request.
  Future<Either<Failure, T>> _mutate<T>(
    String name,
    Future<Either<Failure, T>> Function(ScheduleRepository repo) op, {
    required List<ScheduleBlock> Function(List<ScheduleBlock> list, T value) apply,
    bool refreshOnNotFound = false,
  }) async {
    final link = ref.keepAlive();
    final generation = _generation;
    try {
      final repository = await ref.read(scheduleRepositoryProvider.future);
      final result = await op(repository);
      return result.fold(
        (failure) {
          if (refreshOnNotFound &&
              failure is ServerFailure &&
              failure.statusCode == 404 &&
              generation == _generation) {
            ref.invalidate(scheduleForDayProvider);
            unawaited(_silentRefresh(generation));
          }
          return Left(failure);
        },
        (value) {
          if (generation == _generation) {
            final current = state.valueOrNull;
            if (current != null) state = AsyncData(sortBlocks(apply(current, value)));
            ref.invalidate(scheduleForDayProvider);
            unawaited(_silentRefresh(generation));
          }
          return Right(value);
        },
      );
    } catch (e, stackTrace) {
      // Safety net only: repositories return Left instead of throwing.
      if (kDebugMode) debugPrint('ScheduleListNotifier.$name error: $e\n$stackTrace');
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
      final repository = await ref.read(scheduleRepositoryProvider.future);
      if (generation != _generation) return;
      final result = await repository.getBlocks();
      if (seq != _refreshSeq || generation != _generation) return;
      result.fold((_) {}, (fresh) => state = AsyncData(sortBlocks(fresh)));
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('ScheduleListNotifier refresh error: $e\n$stackTrace');
    }
  }
}

final scheduleBlocksProvider =
    AsyncNotifierProvider.autoDispose<ScheduleListNotifier, List<ScheduleBlock>>(
      ScheduleListNotifier.new,
    );
