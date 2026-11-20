import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_list_notifier.dart';

/// Blocks scheduled on one plain calendar day (the family argument), ordered
/// by start time then id. A different day is a different family member, so a
/// day change makes exactly one new request and the old day's answer can
/// never be written into the new day's state.
class ScheduleDayNotifier extends AutoDisposeFamilyAsyncNotifier<List<ScheduleBlock>, DateTime> {
  /// Bumped on every build and on dispose; async work captured with an older
  /// value must not write state.
  int _generation = 0;

  /// Numbers silent refreshes; only the newest one may apply its result.
  int _refreshSeq = 0;

  bool _quickAddInFlight = false;

  static const String unexpectedMessage = 'Beklenmeyen bir hata oluştu';

  @override
  Future<List<ScheduleBlock>> build(DateTime day) async {
    _generation++;
    ref.onDispose(() => _generation++);
    final repository = await ref.watch(scheduleRepositoryProvider.future);
    final result = await repository.getBlocksForDay(day);
    return result.fold((failure) => throw failure, sortBlocks);
  }

  /// Whether a quick-add request is in flight.
  bool get isQuickAdding => _quickAddInFlight;

  /// Creates a daily block starting on this day from a parsed quick-add line.
  ///
  /// Not optimistic: the server result is inserted at once (in order), then
  /// the day is re-fetched silently. The /schedule list is invalidated only if
  /// it already exists (nothing is created here; no loop: the list never
  /// invalidates on its own rebuild). While a request is in flight, another
  /// call sends nothing and returns `Right(null)`.
  Future<Either<Failure, ScheduleBlock?>> quickAdd(QuickAddOk parsed) async {
    if (_quickAddInFlight) return const Right(null);
    _quickAddInFlight = true;
    final link = ref.keepAlive();
    final generation = _generation;
    final day = arg;
    try {
      final repository = await ref.read(scheduleRepositoryProvider.future);
      final result = await repository.createBlock(
        title: parsed.title,
        startTime: parsed.start,
        endTime: parsed.end,
        recurrenceType: RecurrenceType.daily,
        startDate: day,
      );
      return result.fold((failure) => Left(failure), (created) {
        if (generation == _generation) {
          final current = state.valueOrNull;
          if (current != null) {
            state = AsyncData(sortBlocks([...current.where((b) => b.id != created.id), created]));
          }
          unawaited(_silentRefresh(generation));
        }
        if (ref.exists(scheduleBlocksProvider)) ref.invalidate(scheduleBlocksProvider);
        return Right(created);
      });
    } catch (e, stackTrace) {
      // Safety net only: repositories return Left instead of throwing.
      if (kDebugMode) debugPrint('ScheduleDayNotifier.quickAdd error: $e\n$stackTrace');
      return const Left(UnknownFailure(unexpectedMessage));
    } finally {
      _quickAddInFlight = false;
      link.close();
    }
  }

  /// Re-fetches the day without a loading state; errors keep the current
  /// list. If the first load is still running it is restarted instead.
  Future<void> _silentRefresh(int generation) async {
    if (!state.hasValue && state.isLoading) {
      ref.invalidateSelf();
      return;
    }
    final seq = ++_refreshSeq;
    try {
      final repository = await ref.read(scheduleRepositoryProvider.future);
      if (generation != _generation) return;
      final result = await repository.getBlocksForDay(arg);
      if (seq != _refreshSeq || generation != _generation) return;
      result.fold((_) {}, (fresh) => state = AsyncData(sortBlocks(fresh)));
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('ScheduleDayNotifier refresh error: $e\n$stackTrace');
    }
  }
}

/// Blocks for a given plain calendar day.
final scheduleForDayProvider = AsyncNotifierProvider.autoDispose
    .family<ScheduleDayNotifier, List<ScheduleBlock>, DateTime>(ScheduleDayNotifier.new);

/// Today's blocks (Home card); follows [todayProvider], so a day change
/// (resume or midnight) loads the new day.
final todayScheduleProvider = Provider.autoDispose<AsyncValue<List<ScheduleBlock>>>((ref) {
  return ref.watch(scheduleForDayProvider(ref.watch(todayProvider)));
});
