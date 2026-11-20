import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/notes/domain/note.dart';

/// Contract tests against real backend JSON (test/fixtures, generated with the
/// backend TestClient).
void main() {
  dynamic read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

  group('Note.fromJson (GET /notes)', () {
    late List<Note> notes;
    late List<dynamic> raw;

    setUpAll(() {
      raw = read('notes_list.json') as List<dynamic>;
      notes = raw.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
    });

    test('parses every note, newest update first as the server sent it', () {
      expect(notes.map((n) => n.id), [5, 4, 3, 2, 1]);
    });

    test('favorite note with Turkish title, body and normalized tags', () {
      final n = notes.firstWhere((n) => n.id == 1);
      expect(n.title, 'İş toplantısı notları');
      expect(n.body, 'Pazartesi sunumu hazırla.\nBütçe tablosunu güncelle.');
      expect(n.isFavorite, isTrue);
      expect(n.tags, ['iş', 'öğrenim']);
      expect(n.createdAt, DateTime(2026, 11, 19, 19, 36, 18));
      expect(n.updatedAt, DateTime(2026, 11, 19, 19, 36, 18));
    });

    test('255-character title, no body, tags ışık and çiçek', () {
      final n = notes.firstWhere((n) => n.id == 2);
      expect(n.title.runes.length, 255);
      expect(n.title.startsWith('Ç'), isTrue);
      expect(n.title.endsWith('Ş'), isTrue);
      expect(n.body, isNull);
      expect(n.isFavorite, isFalse);
      expect(n.tags, ['çiçek', 'ışık']);
    });

    test('long body and four tags (server lowercased ISPARTA to ısparta)', () {
      final n = notes.firstWhere((n) => n.id == 3);
      expect(n.title, 'Öğrenim planı');
      expect(n.body!.length, greaterThan(4000));
      expect(n.body!.split('\n'), hasLength(60));
      expect(n.tags, ['kitap', 'proje fikirleri', 'öğrenim', 'ısparta']);
    });

    test('note with no tags and no body', () {
      final n = notes.firstWhere((n) => n.id == 4);
      expect(n.title, 'Alışveriş listesi');
      expect(n.body, isNull);
      expect(n.tags, isEmpty);
      expect(n.isFavorite, isFalse);
    });

    test('toJson round-trip keeps every field (snake_case keys)', () {
      for (final n in notes) {
        final json = n.toJson();
        expect(json.keys.toSet(), {
          'id',
          'title',
          'body',
          'is_favorite',
          'tags',
          'created_at',
          'updated_at',
        });
        expect(Note.fromJson(jsonDecode(jsonEncode(json)) as Map<String, dynamic>), n);
      }
    });
  });

  group('single note responses', () {
    test('POST /notes 201 body', () {
      final n = Note.fromJson(read('note_created.json') as Map<String, dynamic>);
      expect(n.id, 1);
      expect(n.isFavorite, isTrue);
      expect(n.tags, ['iş', 'öğrenim']);
    });

    test('PATCH 200 with body and tags cleared: body null, tags empty', () {
      final n = Note.fromJson(read('note_update_cleared.json') as Map<String, dynamic>);
      expect(n.id, 5);
      expect(n.title, 'Çiçek bakımı');
      expect(n.body, isNull);
      expect(n.tags, isEmpty);
    });

    test('POST /notes/of-day filled: body and normalized tags', () {
      final n = Note.fromJson(read('note_of_day.json') as Map<String, dynamic>);
      expect(n.id, 1);
      expect(n.title, 'İş toplantısı notları');
      expect(n.body, 'Gündem: bütçe\nKarar: ışık sistemi yenilenecek');
      expect(n.isFavorite, isFalse);
      expect(n.tags, ['iş', 'öğrenim', 'ışık']);
      expect(n.createdAt, DateTime(2026, 11, 20, 5, 34, 57));
      expect(n.updatedAt, DateTime(2026, 11, 20, 5, 34, 57));
      expect(Note.fromJson(n.toJson()), n);
    });

    test('POST /notes/of-day with no notes is a JSON null', () {
      expect(read('note_of_day_null.json'), isNull);
    });
  });

  group('TagCount.fromJson (GET /tags)', () {
    test('parses names and counts; öğrenim is used by two notes', () {
      final tags = (read('tags_list.json') as List<dynamic>)
          .map((e) => TagCount.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(tags.map((t) => t.name), [
        'iş',
        'kitap',
        'proje fikirleri',
        'çiçek',
        'öğrenim',
        'ısparta',
        'ışık',
      ]);
      expect(tags.firstWhere((t) => t.name == 'öğrenim').noteCount, 2);
      expect(tags.where((t) => t.name != 'öğrenim').every((t) => t.noteCount == 1), isTrue);
      for (final t in tags) {
        expect(t.toJson(), {'name': t.name, 'note_count': t.noteCount});
        expect(TagCount.fromJson(t.toJson()), t);
      }
    });
  });
}
