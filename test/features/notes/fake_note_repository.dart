import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';
import 'package:varys/features/notes/domain/note_repository.dart';

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// Real GET /notes: ids 5..1. 1 favorite (İş toplantısı notları, tags iş and
/// öğrenim, short body), 2 a 255-character title (tags çiçek, ışık, no body),
/// 3 a long body (4 tags), 4 and 5 no body and no tags.
List<Note> notesFixture() => (_read('notes_list.json') as List)
    .map((e) => Note.fromJson(e as Map<String, dynamic>))
    .toList();

/// Real POST /notes 201 body.
Note createdNoteFixture() => Note.fromJson(_read('note_created.json') as Map<String, dynamic>);

/// Python `date.toordinal()` of the calendar day of [d].
int _ordinal(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(1, 1, 1)).inDays + 1;

/// In-memory stand-in for the backend behind [NoteRepository], used by
/// notifier, widget, route and integration tests. It behaves like the
/// server: the list is newest update first, tag counts are counted from
/// [server], the note of the day is `notes by id [ordinal(day) % n]` (null
/// with no notes), tags are normalized and replaced as a whole, unknown ids
/// answer 404. Every request is recorded. Gates park an answer; `on*` hooks
/// and failures replace it.
class FakeNoteRepository implements NoteRepository {
  FakeNoteRepository([List<Note>? initial]) : server = initial ?? notesFixture();

  List<Note> server;

  /// When set, `GET /tags` answers this instead of the counts from [server]
  /// (a server value that differs from a local recount).
  List<TagCount>? tagsOverride;

  Completer<void>? listGate;
  Completer<void>? randomGate;
  Failure? listFailure;
  Failure? tagsFailure;
  Failure? randomFailure;

  /// Replaces one `GET /notes` answer (e.g. a parked Completer per call).
  Future<Either<Failure, List<Note>>> Function()? onList;
  Future<Either<Failure, Note>> Function(NoteDraft draft)? onCreate;
  Future<Either<Failure, Note>> Function(int id, NoteChanges changes)? onUpdate;
  Future<Either<Failure, void>> Function(int id)? onDelete;

  int listCalls = 0;
  int tagsCalls = 0;
  int randomCalls = 0;
  final randomDays = <DateTime>[];
  final createBodies = <Map<String, dynamic>>[];
  final updateCalls = <(int, Map<String, dynamic>)>[];
  final deleteIds = <int>[];

  int _nextId = 100;
  int _clock = 0;

  static const notFound = ServerFailure('Kaynak bulunamadı.', statusCode: 404);

  DateTime _now() => DateTime(2026, 11, 20, 9).add(Duration(seconds: _clock++));

  List<Note> get sortedForList => List.of(server)
    ..sort((a, b) {
      final byUpdate = b.updatedAt.compareTo(a.updatedAt);
      return byUpdate != 0 ? byUpdate : b.id.compareTo(a.id);
    });

  List<TagCount> get serverTags {
    final counts = <String, int>{};
    for (final n in server) {
      for (final t in n.tags) {
        counts.update(t, (c) => c + 1, ifAbsent: () => 1);
      }
    }
    final names = counts.keys.toList()..sort();
    return [for (final n in names) TagCount(name: n, noteCount: counts[n]!)];
  }

  @override
  Future<Either<Failure, List<Note>>> getNotes() async {
    listCalls++;
    final hook = onList;
    if (hook != null) return hook();
    final gate = listGate;
    if (gate != null) await gate.future;
    final failure = listFailure;
    if (failure != null) return Left(failure);
    return Right(sortedForList);
  }

  @override
  Future<Either<Failure, List<TagCount>>> getTags() async {
    tagsCalls++;
    final failure = tagsFailure;
    if (failure != null) return Left(failure);
    return Right(tagsOverride ?? serverTags);
  }

  @override
  Future<Either<Failure, Note?>> getRandomNote(DateTime day) async {
    randomCalls++;
    randomDays.add(day);
    final gate = randomGate;
    if (gate != null) await gate.future;
    final failure = randomFailure;
    if (failure != null) return Left(failure);
    if (server.isEmpty) return const Right(null);
    final byId = List.of(server)..sort((a, b) => a.id.compareTo(b.id));
    return Right(byId[_ordinal(day) % byId.length]);
  }

  @override
  Future<Either<Failure, Note>> createNote(NoteDraft draft) {
    final body = draft.toBody();
    createBodies.add(body);
    final hook = onCreate;
    if (hook != null) return hook(draft);
    final now = _now();
    final tagList = normalizeTags(body['tags'] as List<String>)..sort();
    final created = createdNoteFixture().copyWith(
      id: _nextId++,
      title: body['title'] as String,
      body: body['body'] as String?,
      isFavorite: body['is_favorite'] as bool,
      tags: tagList,
      createdAt: now,
      updatedAt: now,
    );
    server = [...server, created];
    return Future.value(Right(created));
  }

  @override
  Future<Either<Failure, Note>> updateNote(int id, NoteChanges changes) {
    updateCalls.add((id, changes.toBody()));
    final hook = onUpdate;
    if (hook != null) return hook(id, changes);
    final index = server.indexWhere((n) => n.id == id);
    if (index < 0) return Future.value(const Left(notFound));
    T? pick<T>(PlanField<T> f, T? current) => switch (f) {
      PlanFieldUnset<T>() => current,
      PlanFieldSet<T>(:final value) => value,
      PlanFieldClear<T>() => null,
    };
    final n = server[index];
    final updated = n.copyWith(
      title: pick(changes.title, n.title)!,
      body: pick(changes.body, n.body),
      isFavorite: pick(changes.isFavorite, n.isFavorite)!,
      tags: switch (changes.tags) {
        PlanFieldSet<List<String>>(:final value) => normalizeTags(value)..sort(),
        _ => n.tags,
      },
      updatedAt: _now(),
    );
    server = [...server]..[index] = updated;
    return Future.value(Right(updated));
  }

  @override
  Future<Either<Failure, void>> deleteNote(int id) {
    deleteIds.add(id);
    final hook = onDelete;
    if (hook != null) return hook(id);
    if (!server.any((n) => n.id == id)) return Future.value(const Left(notFound));
    server = server.where((n) => n.id != id).toList();
    return Future.value(const Right(null));
  }
}
