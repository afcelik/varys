import 'package:flutter/foundation.dart';
import 'package:varys/core/text/turkish_text.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/notes/domain/note.dart';

/// Pure helpers for notes: Turkish tag normalization (same rule as the
/// backend `tag_normalization.py`), form validation (same limits as the
/// backend), the create body, the partial-update diff and the client-side
/// search filter. No Flutter widgets, no I/O.

const int noteTitleMaxLength = 255;
const int noteBodyMaxLength = 20000;
const int tagMaxLength = 40;
const int maxTagsPerNote = 20;

const String noteTitleRequiredMessage = 'Başlık gerekli';
const String noteTitleTooLongMessage = 'Başlık en fazla 255 karakter olabilir';
const String noteBodyTooLongMessage = 'Not en fazla 20000 karakter olabilir';
const String tagEmptyMessage = 'Etiket boş olamaz';
const String tagCommaMessage = 'Etiket virgül içeremez';
const String tagTooLongMessage = 'Etiket en fazla 40 karakter olabilir';
const String tagLimitMessage = 'En fazla 20 etiket eklenebilir';

/// Length in Unicode code points, as the backend (Python `len`) counts it:
/// an emoji such as 🎯 counts as one.
int _length(String s) => s.runes.length;

/// Decomposed Turkish letters (base letter + combining mark) and their
/// precomposed form. Only these sequences are composed.
///
/// The server applies full Unicode NFC and has the final say; this table is
/// only for display on the client (showing and de-duplicating tags, search).
/// Every character outside it passes through unchanged. `i` + U+0307 and
/// `İ` + U+0307 are not listed: NFC does not compose them either.
const Map<String, String> _turkishComposition = {
  'I\u0307': 'İ', // a decomposed 'İ' (later lowercased to 'i', as on the server)
  'c\u0327': 'ç',
  'C\u0327': 'Ç',
  's\u0327': 'ş',
  'S\u0327': 'Ş',
  'g\u0306': 'ğ',
  'G\u0306': 'Ğ',
  'o\u0308': 'ö',
  'O\u0308': 'Ö',
  'u\u0308': 'ü',
  'U\u0308': 'Ü',
};

/// Composes the decomposed Turkish letters of [_turkishComposition]; any
/// other text is returned unchanged. Client-side stand-in for the server's
/// NFC step (the server applies full NFC and has the final say).
String composeTurkish(String s) {
  var out = s;
  for (final MapEntry(:key, :value) in _turkishComposition.entries) {
    out = out.replaceAll(key, value);
  }
  return out;
}

final RegExp _whitespace = RegExp(r'\s+');

/// Display form of a tag: Turkish letters composed, Turkish-aware lowercase
/// (İ → i, I → ı), trimmed, inner whitespace collapsed to one space. Not
/// validated; see [validateTag].
String normalizeTagText(String raw) => turkishLower(
  composeTurkish(raw),
).trim().split(_whitespace).where((p) => p.isNotEmpty).join(' ');

/// Error of a normalized tag (empty, comma, longer than [tagMaxLength] code
/// points), or null.
String? validateTag(String normalized) {
  if (normalized.isEmpty) return tagEmptyMessage;
  if (normalized.contains(',')) return tagCommaMessage;
  if (_length(normalized) > tagMaxLength) return tagTooLongMessage;
  return null;
}

/// Normalizes every tag and drops duplicates (first occurrence wins, order
/// kept). Invalid tags are not checked here.
List<String> normalizeTags(Iterable<String> raw) =>
    {for (final t in raw) normalizeTagText(t)}.toList();

/// Result of adding one tag to the form: the new list, or an [error] (the
/// list is then unchanged).
@immutable
class TagAddResult {
  const TagAddResult(this.tags, {this.error});

  final List<String> tags;
  final String? error;
}

/// Adds [raw] (normalized) to [current]. An already present tag leaves the
/// list as it is (no error); an invalid tag or a full list returns an error.
TagAddResult addTag(List<String> current, String raw) {
  final tag = normalizeTagText(raw);
  final error = validateTag(tag);
  if (error != null) return TagAddResult(current, error: error);
  if (current.contains(tag)) return TagAddResult(current);
  if (current.length >= maxTagsPerNote) return TagAddResult(current, error: tagLimitMessage);
  return TagAddResult([...current, tag]);
}

/// Result of applying the tag text field to the tag list: the new [tags],
/// the text left in the field ([rest]) and the first [error], if any.
@immutable
class TagInputResult {
  const TagInputResult(this.tags, this.rest, {this.error});

  final List<String> tags;
  final String rest;
  final String? error;
}

/// Applies the tag field [text] to [current].
///
/// Every comma-separated part before the last comma is added (typing a
/// comma adds the tag; pasting 'iş, öğrenim, proje' adds three). The part
/// after the last comma stays in the field, unless [submit] (Enter) adds it
/// too. Duplicates (after normalization) are dropped silently. An empty part
/// between commas, a part longer than [tagMaxLength] or a tag beyond
/// [maxTagsPerNote] is skipped and reported ([TagInputResult.error], the
/// first one). A blank trailing part is ignored silently.
TagInputResult applyTagInput(List<String> current, String text, {required bool submit}) {
  final parts = text.split(',');
  var rest = parts.removeLast();
  if (submit) {
    if (rest.trim().isNotEmpty || parts.isEmpty) parts.add(rest);
    rest = '';
  }
  var tags = current;
  String? error;
  for (final part in parts) {
    if (submit && parts.length == 1 && part.trim().isEmpty) break; // Enter on a blank field
    final r = addTag(tags, part);
    tags = r.tags;
    error ??= r.error;
  }
  return TagInputResult(tags, rest, error: error);
}

String? validateNoteTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) return noteTitleRequiredMessage;
  if (_length(t) > noteTitleMaxLength) return noteTitleTooLongMessage;
  return null;
}

String? validateNoteBody(String body) =>
    _length(body) > noteBodyMaxLength ? noteBodyTooLongMessage : null;

/// Body as sent: an empty or whitespace-only body is null (no body / clear);
/// otherwise the text exactly as typed.
String? noteBodyValue(String body) => body.trim().isEmpty ? null : body;

bool isNoteFormValid({required String title, required String body, required List<String> tags}) =>
    validateNoteTitle(title) == null &&
    validateNoteBody(body) == null &&
    tags.length <= maxTagsPerNote &&
    tags.every((t) => validateTag(t) == null);

/// Body of `POST /notes`. Title is trimmed; an empty body is sent as null.
@immutable
class NoteDraft {
  const NoteDraft({required this.title, this.body, this.tags = const [], this.isFavorite = false});

  final String title;
  final String? body;
  final List<String> tags;
  final bool isFavorite;

  Map<String, dynamic> toBody() => {
    'title': title.trim(),
    'body': body == null ? null : noteBodyValue(body!),
    'tags': List<String>.of(tags),
    'is_favorite': isFavorite,
  };

  @override
  bool operator ==(Object other) =>
      other is NoteDraft &&
      other.title == title &&
      other.body == body &&
      listEquals(other.tags, tags) &&
      other.isFavorite == isFavorite;

  @override
  int get hashCode => Object.hash(title, body, Object.hashAll(tags), isFavorite);
}

/// Fields of a `PATCH /notes/{id}` body. Unset is not sent, clear sends an
/// explicit null, set sends the value. Only [body] is ever cleared (the
/// backend rejects null for title, is_favorite and tags). [tags] replaces the
/// whole list on the server; an empty list removes every tag; unset keeps
/// the current tags.
@immutable
class NoteChanges {
  const NoteChanges({
    this.title = const PlanField.unset(),
    this.body = const PlanField.unset(),
    this.isFavorite = const PlanField.unset(),
    this.tags = const PlanField.unset(),
  });

  final PlanField<String> title;
  final PlanField<String> body;
  final PlanField<bool> isFavorite;
  final PlanField<List<String>> tags;

  bool get isEmpty => title.isUnset && body.isUnset && isFavorite.isUnset && tags.isUnset;

  /// JSON-encodable body with only the set/cleared fields.
  Map<String, dynamic> toBody() {
    final body = <String, dynamic>{};
    title.writeTo(body, 'title');
    this.body.writeTo(body, 'body');
    isFavorite.writeTo(body, 'is_favorite');
    if (tags case PlanFieldSet<List<String>>(:final value)) {
      body['tags'] = List<String>.of(value);
    }
    return body;
  }

  @override
  bool operator ==(Object other) =>
      other is NoteChanges &&
      other.title == title &&
      other.body == body &&
      other.isFavorite == isFavorite &&
      _sameTags(other.tags, tags);

  static bool _sameTags(PlanField<List<String>> a, PlanField<List<String>> b) => switch ((a, b)) {
    (PlanFieldSet(value: final x), PlanFieldSet(value: final y)) => listEquals(x, y),
    _ => a.runtimeType == b.runtimeType,
  };

  @override
  int get hashCode => Object.hash(title, body, isFavorite, tags.isUnset);

  @override
  String toString() => 'NoteChanges(${toBody()})';
}

/// Difference between [original] and the form values. Title is trimmed; an
/// empty or whitespace-only body clears it; tags are compared as a set
/// (order does not matter) and sent as the full list when they differ.
/// Nothing changed → [NoteChanges.isEmpty] (no request).
NoteChanges computeNoteChanges(
  Note original, {
  required String title,
  required String body,
  required List<String> tags,
  required bool isFavorite,
}) {
  final t = title.trim();
  final b = noteBodyValue(body);
  final sameTags = setEquals(tags.toSet(), original.tags.toSet());
  return NoteChanges(
    title: t == original.title ? const PlanField.unset() : PlanField.set(t),
    body: b == original.body
        ? const PlanField.unset()
        : (b == null ? const PlanField.clear() : PlanField.set(b)),
    isFavorite: isFavorite == original.isFavorite
        ? const PlanField.unset()
        : PlanField.set(isFavorite),
    tags: sameTags ? const PlanField.unset() : PlanField.set(List<String>.of(tags)),
  );
}

/// Search key: Turkish letters composed, Turkish-aware lowercase.
String _searchKey(String s) => turkishLower(composeTurkish(s));

/// Client-side filter of the note list (no request). [query] is trimmed and
/// lowercased the Turkish way and matched as a substring of the title, the
/// body and each tag; an empty query matches every note. [tag] keeps only
/// notes with that (normalized) tag; [favoritesOnly] keeps only favorites.
/// Input order is kept.
List<Note> filterNotes(
  List<Note> notes, {
  String query = '',
  String? tag,
  bool favoritesOnly = false,
}) {
  final q = _searchKey(query.trim());
  return [
    for (final note in notes)
      if ((!favoritesOnly || note.isFavorite) &&
          (tag == null || note.tags.contains(tag)) &&
          (q.isEmpty ||
              _searchKey(note.title).contains(q) ||
              (note.body != null && _searchKey(note.body!).contains(q)) ||
              note.tags.any((t) => _searchKey(t).contains(q))))
        note,
  ];
}
