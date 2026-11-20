import 'package:dartz/dartz.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';

/// Note operations. Methods never throw; errors come back as [Failure].
abstract class NoteRepository {
  /// `GET /notes` with no filters: every (not deleted) note, bodies included,
  /// newest update first. Search and filtering happen on the client.
  Future<Either<Failure, List<Note>>> getNotes();

  /// `GET /tags`: tags in use with their note counts.
  Future<Either<Failure, List<TagCount>>> getTags();

  /// `GET /notes/random?day=YYYY-MM-DD`: the note of [day]. A `null` body
  /// (no notes) is a valid answer: `Right(null)`, not a failure.
  Future<Either<Failure, Note?>> getRandomNote(DateTime day);

  /// `POST /notes` (201).
  Future<Either<Failure, Note>> createNote(NoteDraft draft);

  /// `PATCH /notes/{id}`; the body holds only the set/cleared fields.
  Future<Either<Failure, Note>> updateNote(int id, NoteChanges changes);

  /// `DELETE /notes/{id}` (204, soft delete).
  Future<Either<Failure, void>> deleteNote(int id);
}
