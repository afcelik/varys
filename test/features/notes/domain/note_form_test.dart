import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';

const _combiningDot = '\u0307';

Note _note({
  int id = 1,
  String title = 'Başlık',
  String? body,
  bool isFavorite = false,
  List<String> tags = const [],
}) => Note(
  id: id,
  title: title,
  body: body,
  isFavorite: isFavorite,
  tags: tags,
  createdAt: DateTime(2026, 11, 19, 10),
  updatedAt: DateTime(2026, 11, 19, 10),
);

void main() {
  group('composeTurkish (client-side stand-in for the server NFC step)', () {
    const rows = {
      'I\u0307': 'İ',
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
    for (final MapEntry(key: decomposed, value: single) in rows.entries) {
      test('${decomposed.runes.map((r) => r.toRadixString(16)).join('+')} → $single', () {
        expect(decomposed.runes, hasLength(2));
        expect(composeTurkish(decomposed), single);
        expect(composeTurkish(decomposed).runes, hasLength(1));
        // Inside a word too.
        expect(composeTurkish('a${decomposed}b'), 'a${single}b');
      });
    }

    test('characters outside the table pass through unchanged', () {
      const eAcuteDecomposed = 'e\u0301';
      for (final s in [
        eAcuteDecomposed,
        '🎯',
        '👍🏽',
        ' ',
        '\t\n',
        '0123456789',
        'abc XYZ',
        'i$_combiningDot', // NFC does not compose this either
        'İ$_combiningDot', // nor this
        'é',
        'çğıöşü ÇĞİÖŞÜ',
      ]) {
        expect(composeTurkish(s), s, reason: s.runes.toList().toString());
      }
    });
  });

  group('normalizeTagText (same results as the server tests)', () {
    // varys-api tests/test_tag_normalization.py, same inputs and outputs.
    const serverExamples = {
      'İş': 'iş',
      'ISPARTA': 'ısparta',
      'Öğrenim': 'öğrenim',
      'ÇALIŞMA': 'çalışma',
      'ılık': 'ılık',
      'Kitap': 'kitap',
    };
    for (final MapEntry(key: raw, value: expected) in serverExamples.entries) {
      test('$raw → $expected', () => expect(normalizeTagText(raw), expected));
    }

    test('İŞ → iş, with no combining dot left', () {
      final result = normalizeTagText('İŞ');
      expect(result, 'iş');
      expect(result.contains(_combiningDot), isFalse);
      expect(result.runes, hasLength(2));
    });

    test('decomposed İ (I + U+0307) gives the same tag as the single İ', () {
      // Guards the test input itself: it must really be 'I' + U+0307 (not a
      // precomposed 'İ' or a lost escape), or this test would prove nothing.
      expect('I\u0307ş'.runes.toList(), [0x49, 0x307, 0x15F]);
      expect('İş'.runes.toList(), [0x130, 0x15F]);
      final decomposed = normalizeTagText('I\u0307ş');
      expect(decomposed, normalizeTagText('İş'));
      expect(decomposed, 'iş');
      expect(decomposed.contains(_combiningDot), isFalse);
      expect(decomposed.contains('ı$_combiningDot'), isFalse);
    });

    test('decomposed Ç, Ş, Ğ, Ö, Ü give the same tag as the single letters', () {
      expect(normalizeTagText('C\u0327ALIS\u0327MA'), normalizeTagText('ÇALIŞMA'));
      expect(normalizeTagText('O\u0308G\u0306RENI\u0307M'), 'öğrenim');
      expect(normalizeTagText('U\u0308ZU\u0308M'), 'üzüm');
    });

    test('trims and collapses inner whitespace', () {
      expect(normalizeTagText('  Proje   Fikirleri \t '), 'proje fikirleri');
    });

    test('blank input becomes empty', () {
      for (final raw in ['', '   ', '\t\n']) {
        expect(normalizeTagText(raw), '');
      }
    });
  });

  group('validateTag', () {
    test('empty, comma', () {
      expect(validateTag(''), tagEmptyMessage);
      expect(validateTag(normalizeTagText('   ')), tagEmptyMessage);
      expect(validateTag(normalizeTagText('iş,ev')), tagCommaMessage);
    });

    test('40 code points allowed, 41 rejected (emoji count as one)', () {
      expect(validateTag('a' * 40), isNull);
      expect(validateTag('a' * 41), tagTooLongMessage);
      expect(validateTag('ş' * 40), isNull);
      expect(validateTag('🎯' * 40), isNull);
      expect(validateTag('🎯' * 41), tagTooLongMessage);
      expect(validateTag(normalizeTagText('  ${'a' * 40}  ')), isNull);
    });
  });

  group('normalizeTags', () {
    test('drops duplicates after normalization, first occurrence wins', () {
      expect(normalizeTags(['İş', 'ev', 'iş', ' İŞ ', 'I\u0307ş']), ['iş', 'ev']);
      expect(normalizeTags(const []), isEmpty);
    });
  });

  group('addTag', () {
    test('adds the normalized tag at the end', () {
      final r = addTag(['ev'], '  İŞ ');
      expect(r.error, isNull);
      expect(r.tags, ['ev', 'iş']);
    });

    test('an existing tag (in another spelling) leaves the list unchanged, no error', () {
      final r = addTag(['iş'], 'I\u0307Ş');
      expect(r.error, isNull);
      expect(r.tags, ['iş']);
    });

    test('invalid tag returns the error and keeps the list', () {
      expect(addTag(['ev'], ' ').error, tagEmptyMessage);
      expect(addTag(['ev'], 'a,b').error, tagCommaMessage);
      final long = addTag(['ev'], 'a' * 41);
      expect(long.error, tagTooLongMessage);
      expect(long.tags, ['ev']);
    });

    test('20 unique tags max; the 21st is rejected, a duplicate is still fine', () {
      final twenty = [for (var i = 0; i < 20; i++) 't$i'];
      expect(addTag(twenty.sublist(0, 19), 't19').tags, twenty);
      final over = addTag(twenty, 'yeni');
      expect(over.error, tagLimitMessage);
      expect(over.tags, twenty);
      expect(addTag(twenty, 'T0').error, isNull);
    });
  });

  group('applyTagInput (Enter, comma, paste)', () {
    test('typing: the part after the last comma stays in the field', () {
      final r = applyTagInput(const [], 'İş', submit: false);
      expect((r.tags, r.rest, r.error), (const <String>[], 'İş', null));
    });

    test('a typed comma adds the tag (normalized) and empties the field', () {
      final r = applyTagInput(const [], 'İş,', submit: false);
      expect(r.tags, ['iş']);
      expect(r.rest, '');
      expect(r.error, isNull);
    });

    test('Enter adds the last part; decomposed İ (I + U+0307) becomes iş', () {
      expect('I\u0307ş'.runes.toList(), [0x49, 0x307, 0x15F]);
      final r = applyTagInput(['ev'], 'I\u0307ş', submit: true);
      expect(r.tags, ['ev', 'iş']);
      expect(r.tags.last.runes.toList(), [0x69, 0x15F]);
      expect(r.rest, '');
    });

    test('Enter on a blank field or with a blank trailing part: no error', () {
      expect(applyTagInput(['ev'], '   ', submit: true).error, isNull);
      expect(applyTagInput(['ev'], '   ', submit: true).tags, ['ev']);
      final r = applyTagInput(const [], 'iş, ', submit: true);
      expect(r.tags, ['iş']);
      expect(r.error, isNull);
    });

    test("pasted 'iş, öğrenim, proje' (submit) → three tags", () {
      final r = applyTagInput(const [], 'iş, öğrenim, proje', submit: true);
      expect(r.tags, ['iş', 'öğrenim', 'proje']);
      expect(r.error, isNull);
    });

    test('duplicates are dropped silently (İş, İŞ, iş, decomposed)', () {
      final r = applyTagInput(['iş'], 'İş, İŞ, ev, I\u0307ş, ev', submit: true);
      expect(r.tags, ['iş', 'ev']);
      expect(r.error, isNull);
    });

    test('empty middle part and a part over 40 are skipped with a message', () {
      final empty = applyTagInput(const [], 'iş,,ev', submit: true);
      expect(empty.tags, ['iş', 'ev']);
      expect(empty.error, tagEmptyMessage);
      final long = applyTagInput(const [], 'iş, ${'a' * 41}, ev', submit: true);
      expect(long.tags, ['iş', 'ev']);
      expect(long.error, tagTooLongMessage);
    });

    test('20 tag limit: the rest is not added and the limit message is shown', () {
      final nineteen = [for (var i = 0; i < 19; i++) 't$i'];
      final r = applyTagInput(nineteen, 'a, b, c', submit: true);
      expect(r.tags, [...nineteen, 'a']);
      expect(r.error, tagLimitMessage);
    });
  });

  group('title and body validation', () {
    test('title is trimmed, required, at most 255 code points', () {
      expect(validateNoteTitle(''), noteTitleRequiredMessage);
      expect(validateNoteTitle('   '), noteTitleRequiredMessage);
      expect(validateNoteTitle('a' * 255), isNull);
      expect(validateNoteTitle('  ${'a' * 255}  '), isNull);
      expect(validateNoteTitle('a' * 256), noteTitleTooLongMessage);
      expect(validateNoteTitle('🎯' * 255), isNull);
      expect(validateNoteTitle('🎯' * 256), noteTitleTooLongMessage);
    });

    test('body at most 20000 code points', () {
      expect(validateNoteBody(''), isNull);
      expect(validateNoteBody('a' * 20000), isNull);
      expect(validateNoteBody('a' * 20001), noteBodyTooLongMessage);
      expect(validateNoteBody('🎯' * 20000), isNull);
    });

    test('isNoteFormValid combines the rules', () {
      expect(isNoteFormValid(title: 'Not', body: '', tags: const []), isTrue);
      expect(isNoteFormValid(title: ' ', body: '', tags: const []), isFalse);
      expect(isNoteFormValid(title: 'Not', body: 'a' * 20001, tags: const []), isFalse);
      expect(
        isNoteFormValid(title: 'Not', body: '', tags: [for (var i = 0; i < 21; i++) 't$i']),
        isFalse,
      );
    });
  });

  group('NoteDraft.toBody', () {
    test('trims the title, empty body is null, JSON-encodable', () {
      const draft = NoteDraft(title: '  Not  ', body: '  \n ', tags: ['iş'], isFavorite: true);
      final body = draft.toBody();
      expect(body, {
        'title': 'Not',
        'body': null,
        'tags': ['iş'],
        'is_favorite': true,
      });
      expect(jsonDecode(jsonEncode(body)), body);
    });

    test('body is sent exactly as typed when not blank', () {
      const draft = NoteDraft(title: 'Not', body: '  girintili\nmetin ');
      expect(draft.toBody()['body'], '  girintili\nmetin ');
      expect(draft.toBody()['tags'], isEmpty);
      expect(draft.toBody()['is_favorite'], isFalse);
    });
  });

  group('computeNoteChanges', () {
    final original = _note(title: 'Not', body: 'Gövde', tags: ['iş', 'ev'], isFavorite: false);

    NoteChanges diff({String? title, String? body, List<String>? tags, bool? isFavorite}) =>
        computeNoteChanges(
          original,
          title: title ?? 'Not',
          body: body ?? 'Gövde',
          tags: tags ?? ['iş', 'ev'],
          isFavorite: isFavorite ?? false,
        );

    test('nothing changed → empty, body {}', () {
      final c = diff();
      expect(c.isEmpty, isTrue);
      expect(c.toBody(), isEmpty);
    });

    test('same tags in another order → tags unset', () {
      final c = diff(tags: ['ev', 'iş']);
      expect(c.isEmpty, isTrue);
      expect(c.toBody().containsKey('tags'), isFalse);
    });

    test('title padded with spaces only → unset; changed → trimmed value', () {
      expect(diff(title: '  Not  ').isEmpty, isTrue);
      expect(diff(title: ' Yeni ').toBody(), {'title': 'Yeni'});
    });

    test('blank body → clear: key present with null', () {
      for (final b in ['', '   ', '\n\t']) {
        final c = diff(body: b);
        expect(c.body, const PlanField<String>.clear());
        final body = c.toBody();
        expect(body.containsKey('body'), isTrue);
        expect(body['body'], isNull);
        expect(body.keys, ['body']);
      }
    });

    test('changed body → set', () {
      expect(diff(body: 'Yeni gövde').toBody(), {'body': 'Yeni gövde'});
    });

    test('original body null and blank form body → unset', () {
      final c = computeNoteChanges(
        _note(body: null),
        title: 'Başlık',
        body: '  ',
        tags: const [],
        isFavorite: false,
      );
      expect(c.isEmpty, isTrue);
    });

    test('tags changed → full list; all removed → empty list (key present)', () {
      expect(diff(tags: ['iş', 'kitap']).toBody(), {
        'tags': ['iş', 'kitap'],
      });
      final cleared = diff(tags: const []).toBody();
      expect(cleared.containsKey('tags'), isTrue);
      expect(cleared['tags'], isEmpty);
    });

    test('favorite changed → set', () {
      expect(diff(isFavorite: true).toBody(), {'is_favorite': true});
    });

    test('several fields: only the changed ones, JSON-encodable', () {
      final body = diff(title: 'Yeni', body: '', tags: const [], isFavorite: true).toBody();
      expect(body, {'title': 'Yeni', 'body': null, 'is_favorite': true, 'tags': <String>[]});
      expect(jsonDecode(jsonEncode(body)), body);
    });
  });

  group('filterNotes', () {
    late List<Note> fixture;

    setUpAll(() {
      fixture = (jsonDecode(File('test/fixtures/notes_list.json').readAsStringSync()) as List)
          .map((e) => Note.fromJson(e as Map<String, dynamic>))
          .toList();
    });

    final tagOnly = _note(id: 10, title: 'Toplantı', tags: ['iş']);
    final titleOnly = _note(id: 11, title: 'Yeni iş başvurusu');
    final light = _note(id: 12, title: 'Lamba', tags: ['ışık']);
    final city = _note(id: 13, title: 'Isparta gezisi');
    final bodyOnly = _note(id: 14, title: 'Liste', body: 'Ekmek, BÜTÇE ve süt');
    final unrelated = _note(id: 15, title: 'Spor', body: 'Koşu');
    final all = [tagOnly, titleOnly, light, city, bodyOnly, unrelated];

    List<int> ids(List<Note> notes) => notes.map((n) => n.id).toList();

    test("'İŞ' finds the 'iş' tag and the 'iş' title", () {
      expect(ids(filterNotes(all, query: 'İŞ')), [10, 11]);
      expect(ids(filterNotes(all, query: 'I\u0307Ş')), [10, 11]);
    });

    test("ışık / ISIK / Isparta follow the Turkish I/ı rule", () {
      expect(ids(filterNotes(all, query: 'IŞIK')), [12]);
      expect(ids(filterNotes(all, query: 'ışık')), [12]);
      expect(ids(filterNotes(all, query: 'işik')), isEmpty);
      expect(ids(filterNotes(all, query: 'ISIK')), isEmpty);
      expect(ids(filterNotes(all, query: 'ISPARTA')), [13]);
      expect(ids(filterNotes(all, query: 'ısparta')), [13]);
      expect(ids(filterNotes(all, query: 'isparta')), isEmpty);
    });

    test('searches the body', () {
      expect(ids(filterNotes(all, query: 'bütçe')), [14]);
      expect(ids(filterNotes(fixture, query: 'BÜTÇE')), [1]);
      expect(ids(filterNotes(fixture, query: 'satır: öğrenim')), [3]);
    });

    test('empty or blank query matches everything (order kept)', () {
      expect(ids(filterNotes(all)), ids(all));
      expect(ids(filterNotes(all, query: '   ')), ids(all));
      expect(ids(filterNotes(all, query: '  spor ')), [15]);
    });

    test('no match → empty', () {
      expect(filterNotes(all, query: 'zzz'), isEmpty);
    });

    test('tag and favorite filters, alone and combined with the query', () {
      expect(ids(filterNotes(fixture, tag: 'öğrenim')), [3, 1]);
      expect(ids(filterNotes(fixture, favoritesOnly: true)), [1]);
      expect(ids(filterNotes(fixture, tag: 'öğrenim', favoritesOnly: true)), [1]);
      expect(ids(filterNotes(fixture, tag: 'öğrenim', query: 'günlüğü')), [3]);
      expect(filterNotes(fixture, tag: 'ışık', favoritesOnly: true), isEmpty);
    });
  });
}
