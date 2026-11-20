import 'package:freezed_annotation/freezed_annotation.dart';

part 'note.freezed.dart';
part 'note.g.dart';

/// A note as returned by the backend (NoteRead).
///
/// [body] is plain text (no Markdown rendering yet) and may be null.
/// [tags] are normalized by the server (Turkish-aware lowercase) and sorted.
@freezed
abstract class Note with _$Note {
  const factory Note({
    required int id,
    required String title,
    String? body,
    required bool isFavorite,
    required List<String> tags,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);
}

/// A tag with the number of (not deleted) notes using it (`GET /tags`).
@freezed
abstract class TagCount with _$TagCount {
  const factory TagCount({required String name, required int noteCount}) = _TagCount;

  factory TagCount.fromJson(Map<String, dynamic> json) => _$TagCountFromJson(json);
}
