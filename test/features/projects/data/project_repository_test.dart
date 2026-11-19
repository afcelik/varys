import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';

class _MockApiClient extends Mock implements ApiClient {}

Response<T> _ok<T>(String path, int status, T? data) =>
    Response<T>(requestOptions: RequestOptions(path: path), statusCode: status, data: data);

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

Failure _left<T>(Either<Failure, T> result) =>
    result.fold((f) => f, (_) => fail('expected Left'));

T _right<T>(Either<Failure, T> result) =>
    result.fold((f) => fail('expected Right, got $f'), (v) => v);

void main() {
  late _MockApiClient api;
  late ProjectRepositoryImpl repository;
  late List<dynamic> listFixture;
  late Map<String, dynamic> limitsFixture;

  setUpAll(() {
    listFixture = jsonDecode(File('test/fixtures/projects_list.json').readAsStringSync())
        as List<dynamic>;
    limitsFixture = jsonDecode(File('test/fixtures/projects_limits.json').readAsStringSync())
        as Map<String, dynamic>;
  });

  setUp(() {
    api = _MockApiClient();
    repository = ProjectRepositoryImpl(api);
  });

  void stubList(Future<Response<List<dynamic>>> Function() answer) {
    when(() => api.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters')))
        .thenAnswer((_) => answer());
  }

  group('getProjects', () {
    test('GETs /projects without a query and parses the real response', () async {
      stubList(() async => _ok('/projects', 200, listFixture));

      final projects = _right(await repository.getProjects());

      expect(projects.map((p) => p.id), [1, 2, 3, 4, 5]);
      expect(projects.first.progressPercent, 25);
      verify(() => api.get<List<dynamic>>('/projects', queryParameters: null)).called(1);
    });

    test('status: active sends ?status=active', () async {
      final active = listFixture.where((p) => (p as Map)['status'] == 'active').toList();
      stubList(() async => _ok('/projects', 200, active));

      final projects = _right(await repository.getProjects(status: ProjectStatus.active));

      expect(projects.map((p) => p.status).toSet(), {ProjectStatus.active});
      verify(() => api.get<List<dynamic>>('/projects', queryParameters: {'status': 'active'}))
          .called(1);
    });

    test('each status is sent with its backend value', () async {
      stubList(() async => _ok('/projects', 200, const <dynamic>[]));
      const expected = {
        ProjectStatus.active: 'active',
        ProjectStatus.onHold: 'on_hold',
        ProjectStatus.someday: 'someday',
        ProjectStatus.completed: 'completed',
      };
      for (final MapEntry(key: status, value: value) in expected.entries) {
        _right(await repository.getProjects(status: status));
        verify(() => api.get<List<dynamic>>('/projects', queryParameters: {'status': value}))
            .called(1);
      }
    });

    test('null body is an empty list', () async {
      stubList(() async => _ok<List<dynamic>>('/projects', 200, null));
      expect(_right(await repository.getProjects()), isEmpty);
    });

    test('500 -> ServerFailure with status code; backend detail does not leak', () async {
      const detail = 'sqlite3.OperationalError: database is locked';
      stubList(() async => throw _bad('/projects', 500, body: {'detail': detail}));

      final failure = _left(await repository.getProjects(status: ProjectStatus.active));

      expect(failure, isA<ServerFailure>());
      expect((failure as ServerFailure).statusCode, 500);
      expect(userMessage(failure), 'Sunucu hatası. Lütfen daha sonra tekrar deneyin.');
      expect(userMessage(failure), isNot(contains('sqlite')));
    });

    test('timeout -> NetworkFailure', () async {
      stubList(() async => throw _timeout('/projects'));

      final failure = _left(await repository.getProjects());

      expect(failure, isA<NetworkFailure>());
      expect(userMessage(failure), 'Bağlantı hatası');
    });

    test('unknown status in the response -> UnknownFailure, no throw', () async {
      final broken = [
        {...(listFixture.first as Map<String, dynamic>), 'status': 'archived'},
      ];
      stubList(() async => _ok('/projects', 200, broken));

      final failure = _left(await repository.getProjects());

      expect(failure, isA<UnknownFailure>());
      expect(userMessage(failure), 'Beklenmeyen bir hata oluştu');
      expect(userMessage(failure), isNot(contains('archived')));
    });
  });

  group('getLimits', () {
    test('GETs /projects/limits and parses the real response', () async {
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => _ok('/projects/limits', 200, limitsFixture));

      final limits = _right(await repository.getLimits());

      expect(limits, const ProjectLimits(maxActive: 3, activeCount: 2));
      verify(() => api.get<Map<String, dynamic>>('/projects/limits')).called(1);
    });

    test('404 -> ServerFailure(404) with the fixed text, not the detail', () async {
      when(() => api.get<Map<String, dynamic>>(any())).thenAnswer(
          (_) async => throw _bad('/projects/limits', 404, body: {'detail': 'Project 9 not found'}));

      final failure = _left(await repository.getLimits());

      expect((failure as ServerFailure).statusCode, 404);
      expect(userMessage(failure), 'Kaynak bulunamadı.');
      expect(userMessage(failure), isNot(contains('Project 9')));
    });

    test('timeout -> NetworkFailure', () async {
      when(() => api.get<Map<String, dynamic>>(any()))
          .thenAnswer((_) async => throw _timeout('/projects/limits'));

      expect(_left(await repository.getLimits()), isA<NetworkFailure>());
    });
  });
}
