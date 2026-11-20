import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';

class _MockApiClient extends Mock implements ApiClient {}

Response<T> _ok<T>(String path, int status, T? data) => Response<T>(
  requestOptions: RequestOptions(path: path),
  statusCode: status,
  data: data,
);

DioException _bad(String path, int status, {Object? body}) {
  final options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: body),
  );
}

DioException _timeout(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.receiveTimeout,
);

Failure _left<T>(Either<Failure, T> result) => result.fold((f) => f, (_) => fail('expected Left'));

T _right<T>(Either<Failure, T> result) =>
    result.fold((f) => fail('expected Right, got $f'), (v) => v);

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  late _MockApiClient api;
  late NoteRepositoryImpl repository;

  setUp(() {
    api = _MockApiClient();
    repository = NoteRepositoryImpl(api);
  });

  /// The PATCH body the repository sent (and that it is JSON-encodable).
  Map<String, dynamic> sentPatchBody() {
    final captured = verify(
      () => api.patch<Map<String, dynamic>>(captureAny(), data: captureAny(named: 'data')),
    ).captured;
    final body = captured[1] as Map<String, dynamic>;
    expect(jsonDecode(jsonEncode(body)), body);
    return body;
  }

  group('getNotes', () {
    test('GET /notes with no query parameters; parses the fixture', () async {
      when(
        () => api.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => _ok('/notes', 200, _read('notes_list.json') as List<dynamic>));

      final notes = _right(await repository.getNotes());

      expect(notes.map((n) => n.id), [5, 4, 3, 2, 1]);
      final captured = verify(
        () => api.get<List<dynamic>>(
          captureAny(),
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured[0], '/notes');
      expect(captured[1], isNull, reason: 'no ?tag / ?favorite: filtering is client-side');
    });

    test('timeout → NetworkFailure with the fixed message', () async {
      when(
        () => api.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenThrow(_timeout('/notes'));
      final failure = _left(await repository.getNotes());
      expect(failure, isA<NetworkFailure>());
      expect(failure.userMessage, 'Bağlantı hatası');
    });
  });

  group('getTags', () {
    test('GET /tags parses names and counts', () async {
      when(
        () => api.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => _ok('/tags', 200, _read('tags_list.json') as List<dynamic>));
      final tags = _right(await repository.getTags());
      expect(
        tags.firstWhere((t) => t.name == 'öğrenim'),
        const TagCount(name: 'öğrenim', noteCount: 2),
      );
      verify(() => api.get<List<dynamic>>('/tags')).called(1);
    });
  });

  group('getNoteOfDay', () {
    void stubOfDay(Object? data) {
      when(
        () => api.post<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer((_) async => _ok<dynamic>('/notes/of-day', 200, data));
    }

    void stubOfDayError(DioException e) {
      when(
        () => api.post<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenThrow(e);
    }

    test('POST /notes/of-day?day=YYYY-MM-DD (date only, no time, no zone), no body', () async {
      stubOfDay(_read('note_of_day.json'));
      await repository.getNoteOfDay(DateTime(2026, 11, 20, 23, 59));
      final captured = verify(
        () => api.post<dynamic>(
          captureAny(),
          data: captureAny(named: 'data'),
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured;
      expect(captured[0], '/notes/of-day');
      expect(captured[1], isNull, reason: 'the day goes in the query, never in a body');
      expect(captured[2], {'day': '2026-11-20'});
      // The old GET /notes/random is no longer called by the client.
      verifyNever(() => api.get<dynamic>(any(), queryParameters: any(named: 'queryParameters')));
    });

    test('filled body → Right(Note) with body and normalized tags', () async {
      stubOfDay(_read('note_of_day.json'));
      final note = _right(await repository.getNoteOfDay(DateTime(2026, 11, 20)));
      expect(note!.id, 1);
      expect(note.title, 'İş toplantısı notları');
      expect(note.body, 'Gündem: bütçe\nKarar: ışık sistemi yenilenecek');
      expect(note.tags, ['iş', 'öğrenim', 'ışık']);
      expect(note.isFavorite, isFalse);
    });

    test('200 with a null body is Right(null), not a failure', () async {
      stubOfDay(_read('note_of_day_null.json'));
      final result = await repository.getNoteOfDay(DateTime(2026, 11, 20));
      expect(result.isRight(), isTrue);
      expect(_right(result), isNull);
    });

    test('404 → fixed message; detail never leaks', () async {
      stubOfDayError(_bad('/notes/of-day', 404, body: {'detail': 'Not Found xyz'}));
      final failure = _left(await repository.getNoteOfDay(DateTime(2026, 11, 20)));
      expect(failure, isA<ServerFailure>());
      expect((failure as ServerFailure).statusCode, 404);
      expect(failure.userMessage, 'Kaynak bulunamadı.');
      expect(failure.userMessage.contains('xyz'), isFalse);
    });

    test('422 (day out of range) → fixed message; detail never leaks', () async {
      stubOfDayError(
        _bad(
          '/notes/of-day',
          422,
          body: {
            'detail': [
              {
                'type': 'less_than_equal',
                'loc': ['query', 'day'],
                'msg': 'day too late xyz',
              },
            ],
          },
        ),
      );
      final failure = _left(await repository.getNoteOfDay(DateTime(2101)));
      expect((failure as ServerFailure).statusCode, 422);
      expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
      expect(failure.userMessage.contains('xyz'), isFalse);
    });

    test('500 → ServerFailure with the fixed message', () async {
      stubOfDayError(_bad('/notes/of-day', 500, body: {'detail': 'Internal boom'}));
      final failure = _left(await repository.getNoteOfDay(DateTime(2026, 11, 20)));
      expect(failure, isA<ServerFailure>());
      expect(failure.userMessage, 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.');
      expect(failure.userMessage.contains('boom'), isFalse);
    });

    test('timeout → NetworkFailure with the fixed message', () async {
      stubOfDayError(_timeout('/notes/of-day'));
      final failure = _left(await repository.getNoteOfDay(DateTime(2026, 11, 20)));
      expect(failure, isA<NetworkFailure>());
      expect(failure.userMessage, 'Bağlantı hatası');
    });
  });

  group('createNote', () {
    test('POST /notes with the full draft body; parses the 201 fixture', () async {
      when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer(
        (_) async => _ok('/notes', 201, _read('note_created.json') as Map<String, dynamic>),
      );

      final note = _right(
        await repository.createNote(
          const NoteDraft(
            title: ' İş toplantısı notları ',
            body: 'Pazartesi sunumu hazırla.\nBütçe tablosunu güncelle.',
            tags: ['iş', 'öğrenim'],
            isFavorite: true,
          ),
        ),
      );

      expect(note.id, 1);
      expect(note.tags, ['iş', 'öğrenim']);
      final captured = verify(
        () => api.post<Map<String, dynamic>>(captureAny(), data: captureAny(named: 'data')),
      ).captured;
      expect(captured[0], '/notes');
      final body = captured[1] as Map<String, dynamic>;
      expect(body, {
        'title': 'İş toplantısı notları',
        'body': 'Pazartesi sunumu hazırla.\nBütçe tablosunu güncelle.',
        'tags': ['iş', 'öğrenim'],
        'is_favorite': true,
      });
      expect(jsonDecode(jsonEncode(body)), body);
    });
  });

  group('updateNote', () {
    void stubPatch(Map<String, dynamic> response) {
      when(
        () => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer((_) async => _ok('/notes/5', 200, response));
    }

    test('PATCH /notes/{id} sends only the set field (unset → no key)', () async {
      stubPatch(_read('note_update_cleared.json') as Map<String, dynamic>);
      await repository.updateNote(5, const NoteChanges(isFavorite: PlanField.set(true)));
      final captured = verify(
        () => api.patch<Map<String, dynamic>>(captureAny(), data: any(named: 'data')),
      ).captured;
      expect(captured.single, '/notes/5');
      clearInteractions(api);
    });

    test('unset fields are absent', () async {
      stubPatch(_read('note_update_cleared.json') as Map<String, dynamic>);
      await repository.updateNote(5, const NoteChanges(title: PlanField.set('Yeni')));
      final body = sentPatchBody();
      expect(body, {'title': 'Yeni'});
      expect(body.containsKey('body'), isFalse);
      expect(body.containsKey('tags'), isFalse);
      expect(body.containsKey('is_favorite'), isFalse);
    });

    test(
      'body clear and tags [] → keys present (null, empty list); parses cleared fixture',
      () async {
        stubPatch(_read('note_update_cleared.json') as Map<String, dynamic>);
        final note = _right(
          await repository.updateNote(
            5,
            const NoteChanges(body: PlanField.clear(), tags: PlanField.set(<String>[])),
          ),
        );
        final body = sentPatchBody();
        expect(body.keys.toSet(), {'body', 'tags'});
        expect(body['body'], isNull);
        expect(body['tags'], isEmpty);
        expect(note.body, isNull);
        expect(note.tags, isEmpty);
      },
    );

    test('tags set sends the full list', () async {
      stubPatch(_read('note_update_cleared.json') as Map<String, dynamic>);
      await repository.updateNote(
        5,
        const NoteChanges(tags: PlanField.set(['iş', 'ev', 'öğrenim'])),
      );
      expect(sentPatchBody(), {
        'tags': ['iş', 'ev', 'öğrenim'],
      });
    });

    test('404 → ServerFailure(404) with the fixed message; detail never leaks', () async {
      final detail = _read('note_update_404.json');
      when(
        () => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(_bad('/notes/9999', 404, body: detail));
      final failure = _left(
        await repository.updateNote(9999, const NoteChanges(title: PlanField.set('Yok'))),
      );
      expect(failure, isA<ServerFailure>());
      expect((failure as ServerFailure).statusCode, 404);
      expect(failure.userMessage, 'Kaynak bulunamadı.');
      expect(failure.userMessage, userMessage(failure));
      expect(failure.userMessage.contains('9999'), isFalse);
      expect(failure.userMessage.contains('not found'), isFalse);
    });

    test('422 (title null) → fixed message; pydantic detail never leaks', () async {
      final detail = _read('note_update_title_null_422.json');
      when(
        () => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenThrow(_bad('/notes/5', 422, body: detail));
      final failure = _left(
        await repository.updateNote(5, const NoteChanges(title: PlanField.set('x'))),
      );
      expect((failure as ServerFailure).statusCode, 422);
      expect(failure.userMessage, 'Gönderilen veriler geçersiz.');
      expect(failure.userMessage.contains('cannot be null'), isFalse);
    });
  });

  group('deleteNote', () {
    test('DELETE /notes/{id} with a 204 empty body → Right', () async {
      when(
        () => api.delete<dynamic>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenAnswer((_) async => _ok<dynamic>('/notes/3', 204, null));
      final result = await repository.deleteNote(3);
      expect(result.isRight(), isTrue);
      verify(() => api.delete<dynamic>('/notes/3')).called(1);
    });

    test('404 → ServerFailure(404) fixed message', () async {
      when(
        () => api.delete<dynamic>(any(), queryParameters: any(named: 'queryParameters')),
      ).thenThrow(_bad('/notes/3', 404, body: {'detail': 'Note with id 3 not found'}));
      final failure = _left(await repository.deleteNote(3));
      expect((failure as ServerFailure).statusCode, 404);
      expect(failure.userMessage, 'Kaynak bulunamadı.');
    });
  });

  test('unexpected payload shape → UnknownFailure with the fixed message', () async {
    when(
      () => api.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) async => _ok<List<dynamic>>('/notes', 200, ['not a map']));
    final failure = _left(await repository.getNotes());
    expect(failure, isA<UnknownFailure>());
    expect(failure.userMessage, 'Beklenmeyen bir hata oluştu');
  });
}
