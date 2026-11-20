import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';
import 'package:varys/features/notes/domain/note_repository.dart';

/// API implementation of [NoteRepository].
///
/// Error text comes only from `core/errors` (`userMessage`), mapped by
/// exception type and status code (404/422 → fixed Turkish messages). The
/// backend `detail` is never read or shown.
class NoteRepositoryImpl implements NoteRepository {
  NoteRepositoryImpl(this._apiClient);

  final ApiClient _apiClient;

  static const String _basePath = '/notes';
  static const String _tagsPath = '/tags';

  @override
  Future<Either<Failure, List<Note>>> getNotes() {
    return _guard('getNotes', () async {
      final response = await _apiClient.get<List<dynamic>>(_basePath);
      final data = response.data ?? const <dynamic>[];
      return data.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  @override
  Future<Either<Failure, List<TagCount>>> getTags() {
    return _guard('getTags', () async {
      final response = await _apiClient.get<List<dynamic>>(_tagsPath);
      final data = response.data ?? const <dynamic>[];
      return data.map((e) => TagCount.fromJson(e as Map<String, dynamic>)).toList();
    });
  }

  @override
  Future<Either<Failure, Note?>> getNoteOfDay(DateTime day) {
    return _guard<Note?>('getNoteOfDay', () async {
      // The day goes in the query; the request has no body.
      final response = await _apiClient.post<dynamic>(
        '$_basePath/of-day',
        queryParameters: {'day': formatDateForApi(day)},
      );
      final data = response.data;
      // 200 with a JSON null body: there are no notes (a valid answer).
      if (data == null) return null;
      return Note.fromJson(data as Map<String, dynamic>);
    });
  }

  @override
  Future<Either<Failure, Note>> createNote(NoteDraft draft) {
    return _guard('createNote', () async {
      final response = await _apiClient.post<Map<String, dynamic>>(_basePath, data: draft.toBody());
      return Note.fromJson(response.data!);
    });
  }

  @override
  Future<Either<Failure, Note>> updateNote(int id, NoteChanges changes) {
    return _guard('updateNote', () async {
      final response = await _apiClient.patch<Map<String, dynamic>>(
        '$_basePath/$id',
        data: changes.toBody(),
      );
      return Note.fromJson(response.data!);
    });
  }

  @override
  Future<Either<Failure, void>> deleteNote(int id) {
    return _guard('deleteNote', () async {
      await _apiClient.delete<dynamic>('$_basePath/$id');
    });
  }

  Future<Either<Failure, T>> _guard<T>(String op, Future<T> Function() body) async {
    try {
      return Right(await body());
    } on DioException catch (e) {
      return Left(_mapDioError(e));
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('NoteRepository.$op error: ${e.runtimeType} - $e\n$stackTrace');
      }
      return Left(UnknownFailure(e.runtimeType.toString()));
    }
  }

  static Failure _mapDioError(DioException e) {
    if (e.type == DioExceptionType.badResponse) {
      return ServerFailure(userMessage(e), statusCode: e.response?.statusCode);
    }
    return NetworkFailure(userMessage(e));
  }
}

/// Riverpod provider for [NoteRepository].
final noteRepositoryProvider = FutureProvider<NoteRepository>((ref) async {
  final apiClient = await ref.watch(apiClientProvider.future);
  return NoteRepositoryImpl(apiClient);
});
