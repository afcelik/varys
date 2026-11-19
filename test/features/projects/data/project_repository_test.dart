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
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';

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

void main() {
  late _MockApiClient api;
  late ProjectRepositoryImpl repository;
  late List<dynamic> listFixture;
  late Map<String, dynamic> limitsFixture;
  late Map<String, dynamic> createdFixture;
  late Map<String, dynamic> updatedFixture;
  late Map<String, dynamic> limit409Fixture;
  late Map<String, dynamic> createInvalid422Fixture;
  late Map<String, dynamic> update422Fixture;

  setUpAll(() {
    listFixture =
        jsonDecode(File('test/fixtures/projects_list.json').readAsStringSync()) as List<dynamic>;
    limitsFixture =
        jsonDecode(File('test/fixtures/projects_limits.json').readAsStringSync())
            as Map<String, dynamic>;
    Map<String, dynamic> read(String name) =>
        jsonDecode(File('test/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;
    createdFixture = read('project_created.json');
    updatedFixture = read('project_updated.json');
    limit409Fixture = read('project_limit_409.json');
    createInvalid422Fixture = read('project_invalid_dates_422.json');
    update422Fixture = read('project_update_422.json');
  });

  setUp(() {
    api = _MockApiClient();
    repository = ProjectRepositoryImpl(api);
  });

  void stubList(Future<Response<List<dynamic>>> Function() answer) {
    when(
      () => api.get<List<dynamic>>(any(), queryParameters: any(named: 'queryParameters')),
    ).thenAnswer((_) => answer());
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
      verify(
        () => api.get<List<dynamic>>('/projects', queryParameters: {'status': 'active'}),
      ).called(1);
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
        verify(
          () => api.get<List<dynamic>>('/projects', queryParameters: {'status': value}),
        ).called(1);
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
      when(
        () => api.get<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => _ok('/projects/limits', 200, limitsFixture));

      final limits = _right(await repository.getLimits());

      expect(limits, const ProjectLimits(maxActive: 3, activeCount: 2));
      verify(() => api.get<Map<String, dynamic>>('/projects/limits')).called(1);
    });

    test('404 -> ServerFailure(404) with the fixed text, not the detail', () async {
      when(() => api.get<Map<String, dynamic>>(any())).thenAnswer(
        (_) async => throw _bad('/projects/limits', 404, body: {'detail': 'Project 9 not found'}),
      );

      final failure = _left(await repository.getLimits());

      expect((failure as ServerFailure).statusCode, 404);
      expect(userMessage(failure), 'Kaynak bulunamadı.');
      expect(userMessage(failure), isNot(contains('Project 9')));
    });

    test('timeout -> NetworkFailure', () async {
      when(
        () => api.get<Map<String, dynamic>>(any()),
      ).thenAnswer((_) async => throw _timeout('/projects/limits'));

      expect(_left(await repository.getLimits()), isA<NetworkFailure>());
    });
  });

  group('createProject', () {
    void stubPost(Future<Response<Map<String, dynamic>>> Function() answer) {
      when(
        () => api.post<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer((_) => answer());
    }

    Map<String, dynamic> sentBody() =>
        verify(
              () => api.post<Map<String, dynamic>>('/projects', data: captureAny(named: 'data')),
            ).captured.single
            as Map<String, dynamic>;

    test('POSTs /projects with a JSON-encodable body; plain YYYY-MM-DD dates', () async {
      stubPost(() async => _ok('/projects', 201, createdFixture));

      final project = _right(
        await repository.createProject(
          ProjectDraft(
            title: '  Yeni proje ',
            description: ' Açıklama metni ',
            status: ProjectStatus.active,
            startDate: DateTime(2026, 11, 1, 15, 30),
            targetDate: DateTime(2026, 12, 15),
          ),
        ),
      );

      expect(project, Project.fromJson(createdFixture));
      final body = sentBody();
      expect(body, {
        'title': 'Yeni proje',
        'description': 'Açıklama metni',
        'status': 'active',
        'start_date': '2026-11-01',
        'target_date': '2026-12-15',
      });
      expect(jsonDecode(jsonEncode(body)), body);
    });

    test('empty description and no dates are sent as explicit null', () async {
      stubPost(() async => _ok('/projects', 201, createdFixture));

      _right(
        await repository.createProject(
          const ProjectDraft(title: 'P', description: '   ', status: ProjectStatus.someday),
        ),
      );

      expect(sentBody(), {
        'title': 'P',
        'description': null,
        'status': 'someday',
        'start_date': null,
        'target_date': null,
      });
    });

    test('409 with the limit code -> ActiveProjectLimitFailure; detail does not leak', () async {
      stubPost(() async => throw _bad('/projects', 409, body: limit409Fixture));

      final failure = _left(
        await repository.createProject(
          const ProjectDraft(title: 'Fazla', status: ProjectStatus.active),
        ),
      );

      expect(failure, isA<ActiveProjectLimitFailure>());
      expect(
        userMessage(failure),
        'Aktif proje sınırına ulaşıldı. Önce bir projeyi beklemeye ya da ileriye al.',
      );
      expect(userMessage(failure), isNot(contains('active_project_limit_reached')));
    });

    for (final body in <Object?>[
      {'detail': 'some_other_conflict'},
      {
        'detail': ['active_project_limit_reached'],
      },
      'active_project_limit_reached',
      null,
    ]) {
      test('other 409 body $body -> generic ServerFailure(409)', () async {
        stubPost(() async => throw _bad('/projects', 409, body: body));

        final failure = _left(
          await repository.createProject(
            const ProjectDraft(title: 'P', status: ProjectStatus.active),
          ),
        );

        expect(failure, isA<ServerFailure>());
        expect((failure as ServerFailure).statusCode, 409);
        expect(userMessage(failure), 'Bir hata oluştu. Lütfen tekrar deneyin.');
        expect(userMessage(failure), isNot(contains('conflict')));
      });
    }

    test('the limit code with another status (422) is not a limit failure', () async {
      stubPost(() async => throw _bad('/projects', 422, body: limit409Fixture));

      final failure = _left(
        await repository.createProject(
          const ProjectDraft(title: 'P', status: ProjectStatus.active),
        ),
      );

      expect(failure, isA<ServerFailure>());
      expect((failure as ServerFailure).statusCode, 422);
    });

    test('422 (real pydantic body) -> fixed text, no backend text', () async {
      stubPost(() async => throw _bad('/projects', 422, body: createInvalid422Fixture));

      final failure = _left(
        await repository.createProject(
          ProjectDraft(
            title: 'Tarih hatası',
            status: ProjectStatus.onHold,
            startDate: DateTime(2026, 12, 10),
            targetDate: DateTime(2026, 12, 1),
          ),
        ),
      );

      expect((failure as ServerFailure).statusCode, 422);
      expect(userMessage(failure), 'Gönderilen veriler geçersiz.');
      expect(userMessage(failure), isNot(contains('target_date')));
    });

    test('timeout -> NetworkFailure', () async {
      stubPost(() async => throw _timeout('/projects'));

      final failure = _left(
        await repository.createProject(
          const ProjectDraft(title: 'P', status: ProjectStatus.active),
        ),
      );

      expect(failure, isA<NetworkFailure>());
    });
  });

  group('updateProject', () {
    void stubPatch(Future<Response<Map<String, dynamic>>> Function() answer) {
      when(
        () => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data')),
      ).thenAnswer((_) => answer());
    }

    Map<String, dynamic> sentBody() =>
        verify(
              () => api.patch<Map<String, dynamic>>('/projects/1', data: captureAny(named: 'data')),
            ).captured.single
            as Map<String, dynamic>;

    test('PATCHes /projects/{id} with only the changed fields; clear -> explicit null', () async {
      stubPatch(() async => _ok('/projects/1', 200, updatedFixture));

      final project = _right(
        await repository.updateProject(
          1,
          const ProjectChanges(
            title: PlanField.set('Yeni proje (güncel)'),
            status: PlanField.set(ProjectStatus.onHold),
            description: PlanField.clear(),
            targetDate: PlanField.clear(),
          ),
        ),
      );

      expect(project, Project.fromJson(updatedFixture));
      final body = sentBody();
      expect(body, {
        'title': 'Yeni proje (güncel)',
        'status': 'on_hold',
        'description': null,
        'target_date': null,
      });
      expect(body.containsKey('start_date'), isFalse);
      expect(jsonDecode(jsonEncode(body)), body);
    });

    test('set dates are plain YYYY-MM-DD; unset fields are absent', () async {
      stubPatch(() async => _ok('/projects/1', 200, updatedFixture));

      _right(
        await repository.updateProject(
          1,
          ProjectChanges(startDate: PlanField.set(DateTime(2027, 1, 5, 23, 59))),
        ),
      );

      expect(sentBody(), {'start_date': '2027-01-05'});
    });

    test('409 limit -> ActiveProjectLimitFailure', () async {
      stubPatch(() async => throw _bad('/projects/1', 409, body: limit409Fixture));

      final failure = _left(
        await repository.updateProject(
          1,
          const ProjectChanges(status: PlanField.set(ProjectStatus.active)),
        ),
      );

      expect(failure, isA<ActiveProjectLimitFailure>());
    });

    test('422 (real PATCH body) -> fixed text, detail does not leak', () async {
      stubPatch(() async => throw _bad('/projects/1', 422, body: update422Fixture));

      final failure = _left(
        await repository.updateProject(
          1,
          ProjectChanges(targetDate: PlanField.set(DateTime(2026, 1, 1))),
        ),
      );

      expect((failure as ServerFailure).statusCode, 422);
      expect(userMessage(failure), 'Gönderilen veriler geçersiz.');
      expect(userMessage(failure), isNot(contains('target_date')));
    });

    test('404 -> ServerFailure(404) with the fixed text', () async {
      stubPatch(
        () async => throw _bad('/projects/1', 404, body: {'detail': 'Project with id 1 not found'}),
      );

      final failure = _left(
        await repository.updateProject(1, const ProjectChanges(title: PlanField.set('X'))),
      );

      expect((failure as ServerFailure).statusCode, 404);
      expect(userMessage(failure), 'Kaynak bulunamadı.');
    });

    test('timeout -> NetworkFailure', () async {
      stubPatch(() async => throw _timeout('/projects/1'));

      expect(
        _left(await repository.updateProject(1, const ProjectChanges(title: PlanField.set('X')))),
        isA<NetworkFailure>(),
      );
    });
  });

  group('deleteProject', () {
    test('DELETEs /projects/{id}; 204 -> Right', () async {
      when(
        () => api.delete<dynamic>(any()),
      ).thenAnswer((_) async => _ok<dynamic>('/projects/7', 204, null));

      _right(await repository.deleteProject(7));

      verify(() => api.delete<dynamic>('/projects/7')).called(1);
    });

    test('404 -> ServerFailure(404)', () async {
      when(() => api.delete<dynamic>(any())).thenAnswer(
        (_) async =>
            throw _bad('/projects/7', 404, body: {'detail': 'Project with id 7 not found'}),
      );

      final failure = _left(await repository.deleteProject(7));

      expect((failure as ServerFailure).statusCode, 404);
      expect(userMessage(failure), isNot(contains('Project with id')));
    });

    test('connection error -> NetworkFailure', () async {
      when(() => api.delete<dynamic>(any())).thenAnswer(
        (_) async => throw DioException(
          requestOptions: RequestOptions(path: '/projects/7'),
          type: DioExceptionType.connectionError,
        ),
      );

      expect(_left(await repository.deleteProject(7)), isA<NetworkFailure>());
    });
  });
}
