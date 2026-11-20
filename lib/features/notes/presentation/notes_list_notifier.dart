import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';
import 'package:varys/features/notes/domain/note_repository.dart';
import 'package:varys/features/notes/presentation/today_note_notifier.dart';

/// Every (not deleted) note plus the tags in use with their counts.
@immutable
class NotesOverview {
  const NotesOverview({required this.notes, required this.tags});

  final List<Note> notes;
  final List<TagCount> tags;

  @override
  bool operator ==(Object other) =>
      other is NotesOverview && listEquals(other.notes, notes) && listEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(Object.hashAll(notes), Object.hashAll(tags));
}

/// Tag counts recounted from [notes], sorted by name (code point order, as
/// the server sorts them). Only an interim value until the server's counts
/// arrive with the silent refresh.
List<TagCount> countTags(List<Note> notes) {
  final counts = <String, int>{};
  for (final note in notes) {
    for (final tag in note.tags) {
      counts[tag] = (counts[tag] ?? 0) + 1;
    }
  }
  final names = counts.keys.toList()..sort();
  return [for (final n in names) TagCount(name: n, noteCount: counts[n]!)];
}

/// All notes (`GET /notes`, no filters) and `GET /tags`, loaded in parallel
/// into one state, plus create/update/delete.
///
/// Search, tag and favorite filtering happen on the client ([filterNotes]);
/// changing them sends no request.
///
/// Mutations are not optimistic: the list changes only after the server
/// answers. On success the server result is applied at once (create adds,
/// update replaces, delete removes; tag counts recounted locally as an
/// interim value), the Home card ([todayNoteProvider]) is invalidated exactly
/// once, and list and tags are re-fetched silently (no loading state; only
/// the newest refresh may write; a failed refresh keeps the current list).
/// Nothing invalidates this provider from the Home side, so there is no
/// invalidation loop. A 404 on update/delete (deleted elsewhere) also
/// re-fetches silently. The caller shows the message.
///
/// A second identical update, or a second delete, of the same note while one
/// is in flight sends no new request and returns the pending result (a
/// double tap sends one PATCH / one DELETE). A different update is sent.
class NotesListNotifier extends AutoDisposeAsyncNotifier<NotesOverview> {
  /// Bumped on every build and on dispose; async work captured with an older
  /// value must not write state.
  int _generation = 0;

  /// Numbers silent refreshes; only the newest one may apply its result.
  int _refreshSeq = 0;

  final Map<int, (NoteChanges, Future<Either<Failure, Note?>>)> _updating = {};
  final Map<int, Future<Either<Failure, void>>> _deleting = {};

  static const String unexpectedMessage = 'Beklenmeyen bir hata oluştu';

  @override
  Future<NotesOverview> build() async {
    final generation = ++_generation;
    ref.onDispose(() => _generation++);
    final repository = await ref.watch(noteRepositoryProvider.future);
    if (generation != _generation) throw const _Superseded();
    final result = await _load(repository);
    if (generation != _generation) throw const _Superseded();
    return result.fold((failure) => throw failure, (overview) => overview);
  }

  /// Whether an update (e.g. the favorite star) of [id] is in flight.
  bool isUpdating(int id) => _updating.containsKey(id);

  /// Whether a delete of [id] is in flight.
  bool isDeleting(int id) => _deleting.containsKey(id);

  Future<Either<Failure, Note>> createNote(NoteDraft draft) {
    return _mutate(
      'create',
      (repo) => repo.createNote(draft),
      apply: (list, created) => [created, ...list.where((n) => n.id != created.id)],
    );
  }

  /// Sends only [changes]. Empty changes send no request and return
  /// `Right(null)`.
  Future<Either<Failure, Note?>> updateNote(int id, NoteChanges changes) {
    if (changes.isEmpty) return Future.value(const Right(null));
    final pending = _updating[id];
    if (pending != null && pending.$1 == changes) return pending.$2;
    late final Future<Either<Failure, Note?>> future;
    future =
        _mutate<Note?>(
          'update',
          (repo) => repo.updateNote(id, changes),
          apply: (list, updated) => [for (final n in list) n.id == id ? updated! : n],
          refreshOnNotFound: true,
        ).whenComplete(() {
          if (identical(_updating[id]?.$2, future)) _updating.remove(id);
        });
    _updating[id] = (changes, future);
    return future;
  }

  /// Flips the favorite flag of [note] (`PATCH is_favorite`), not optimistic.
  Future<Either<Failure, Note?>> toggleFavorite(Note note) =>
      updateNote(note.id, NoteChanges(isFavorite: PlanField.set(!note.isFavorite)));

  Future<Either<Failure, void>> deleteNote(int id) {
    final pending = _deleting[id];
    if (pending != null) return pending;
    final future =
        _mutate<void>(
          'delete',
          (repo) => repo.deleteNote(id),
          apply: (list, _) => list.where((n) => n.id != id).toList(),
          refreshOnNotFound: true,
        ).whenComplete(() {
          // Block body: returning the removed Future would make whenComplete
          // wait on itself.
          _deleting.remove(id);
        });
    _deleting[id] = future;
    return future;
  }

  static Future<Either<Failure, NotesOverview>> _load(NoteRepository repository) async {
    final notesFuture = repository.getNotes();
    final tagsFuture = repository.getTags();
    final notesResult = await notesFuture;
    final tagsResult = await tagsFuture;
    return notesResult.fold(
      Left.new,
      (notes) =>
          tagsResult.fold(Left.new, (tags) => Right(NotesOverview(notes: notes, tags: tags))),
    );
  }

  /// Runs [op]; keeps the provider alive while it is in flight so a closed
  /// page (no listener) does not dispose it mid-request.
  Future<Either<Failure, T>> _mutate<T>(
    String name,
    Future<Either<Failure, T>> Function(NoteRepository repo) op, {
    required List<Note> Function(List<Note> list, T value) apply,
    bool refreshOnNotFound = false,
  }) async {
    final link = ref.keepAlive();
    final generation = _generation;
    try {
      final repository = await ref.read(noteRepositoryProvider.future);
      final result = await op(repository);
      return result.fold(
        (failure) {
          final goneElsewhere =
              refreshOnNotFound && failure is ServerFailure && failure.statusCode == 404;
          if (goneElsewhere && generation == _generation) {
            unawaited(_silentRefresh(generation));
          }
          return Left(failure);
        },
        (value) {
          if (generation == _generation) {
            // Read the state again: it may have changed while awaiting.
            final current = state.valueOrNull;
            if (current != null) {
              final notes = apply(current.notes, value);
              state = AsyncData(NotesOverview(notes: notes, tags: countTags(notes)));
            }
            ref.invalidate(todayNoteProvider);
            unawaited(_silentRefresh(generation));
          }
          return Right(value);
        },
      );
    } catch (e, stackTrace) {
      // Safety net only: repositories return Left instead of throwing.
      if (kDebugMode) debugPrint('NotesListNotifier.$name error: $e\n$stackTrace');
      return const Left(UnknownFailure(unexpectedMessage));
    } finally {
      link.close();
    }
  }

  /// Re-fetches notes and tags without a loading state. Errors are ignored
  /// (the current state stays). If the first load is still running it is
  /// restarted so it cannot return data from before the mutation.
  Future<void> _silentRefresh(int generation) async {
    if (!state.hasValue && state.isLoading) {
      ref.invalidateSelf();
      return;
    }
    final seq = ++_refreshSeq;
    try {
      final repository = await ref.read(noteRepositoryProvider.future);
      if (seq != _refreshSeq || generation != _generation) return;
      final result = await _load(repository);
      if (seq != _refreshSeq || generation != _generation) return;
      result.fold((_) {}, (fresh) => state = AsyncData(fresh));
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('NotesListNotifier refresh error: $e\n$stackTrace');
    }
  }
}

/// Thrown by an outdated build. Riverpod ignores errors and values of a build
/// that is no longer current, so this never reaches the UI.
class _Superseded implements Exception {
  const _Superseded();
}

final notesListProvider = AsyncNotifierProvider.autoDispose<NotesListNotifier, NotesOverview>(
  NotesListNotifier.new,
);

/// Client-side filters of the notes page: search text, one selected tag and
/// "Favoriler". Changing them never sends a request; the page applies them
/// to the loaded list with [filterNotes]. Lives while the page is open (kept
/// while the form is pushed on top).
@immutable
class NotesFilter {
  const NotesFilter({this.query = '', this.tag, this.favoritesOnly = false});

  final String query;
  final String? tag;
  final bool favoritesOnly;

  bool get isActive => query.trim().isNotEmpty || tag != null || favoritesOnly;

  @override
  bool operator ==(Object other) =>
      other is NotesFilter &&
      other.query == query &&
      other.tag == tag &&
      other.favoritesOnly == favoritesOnly;

  @override
  int get hashCode => Object.hash(query, tag, favoritesOnly);
}

class NotesFilterNotifier extends AutoDisposeNotifier<NotesFilter> {
  @override
  NotesFilter build() => const NotesFilter();

  void setQuery(String query) =>
      state = NotesFilter(query: query, tag: state.tag, favoritesOnly: state.favoritesOnly);

  /// Selects [tag]; tapping the selected tag again removes it.
  void toggleTag(String tag) => state = NotesFilter(
    query: state.query,
    tag: state.tag == tag ? null : tag,
    favoritesOnly: state.favoritesOnly,
  );

  void toggleFavorites() =>
      state = NotesFilter(query: state.query, tag: state.tag, favoritesOnly: !state.favoritesOnly);

  void clear() => state = const NotesFilter();
}

final notesFilterProvider = NotifierProvider.autoDispose<NotesFilterNotifier, NotesFilter>(
  NotesFilterNotifier.new,
);
