import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/domain/note.dart';

/// The note of the day for the Home "Günün Notu" card:
/// `POST /notes/of-day?day=` with the device's local day from [todayProvider]
/// (the server stores the day's pick; repeated calls return the same note
/// unless it was deleted). A new day sends one new request.
/// `null` means there are no notes (a valid state, not an error). On failure
/// the state is that Failure (thrown, so `AsyncError.error` is the Failure).
///
/// Refresh with `ref.invalidate(todayNoteProvider)`: Riverpod keeps the
/// previous value while reloading, so the card keeps showing it. A
/// superseded build (invalidated, disposed) stops after each await and never
/// writes ([_generation]).
class TodayNoteNotifier extends AutoDisposeAsyncNotifier<Note?> {
  int _generation = 0;

  @override
  Future<Note?> build() async {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    final day = ref.watch(todayProvider);
    final repository = await ref.watch(noteRepositoryProvider.future);
    if (generation != _generation) throw const _Superseded();
    final result = await repository.getNoteOfDay(day);
    if (generation != _generation) throw const _Superseded();
    return result.fold((failure) => throw failure, (note) => note);
  }
}

/// Thrown by an outdated build. Riverpod ignores errors and values of a build
/// that is no longer current, so this never reaches the UI.
class _Superseded implements Exception {
  const _Superseded();
}

final todayNoteProvider = AsyncNotifierProvider.autoDispose<TodayNoteNotifier, Note?>(
  TodayNoteNotifier.new,
);
