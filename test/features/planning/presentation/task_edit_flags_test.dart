// Eisenhower switches ("Önemli", "Acil") of the task form, create and edit,
// through the REAL TaskRepositoryImpl: ApiClient is a small fake server
// (GET /tasks answers its state, PATCH applies the body, POST creates), so
// every body checked here is the exact JSON the app would send.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/network/api_client.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/planning/presentation/task_list_page.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../projects/fake_project_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

final _day = DateTime(2026, 11, 19);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

Object? _fixture(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

DioException _serverError(String path) {
  final options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    response: Response<Map<String, dynamic>>(requestOptions: options, statusCode: 500),
    type: DioExceptionType.badResponse,
  );
}

void main() {
  late _MockApiClient api;
  late _MockDailyPlanRepository planRepo;
  late GoRouter router;

  /// Fake server state: task JSON by id (real GET /tasks, Eisenhower fixture).
  late Map<int, Map<String, dynamic>> server;
  late List<Map<String, dynamic>> patches;
  late List<Map<String, dynamic>> posts;

  /// When set, PATCH/POST wait on it before answering.
  Completer<void>? gate;

  /// When true, PATCH/POST answer 500.
  late bool failWrites;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
  });

  setUp(() {
    api = _MockApiClient();
    planRepo = _MockDailyPlanRepository();
    patches = [];
    posts = [];
    gate = null;
    failWrites = false;
    // 1: important + urgent, 2: important (project 1), 3: urgent, 4: neither,
    // 5: done (important + urgent).
    server = {
      for (final t in (_fixture('tasks_eisenhower.json') as List).cast<Map<String, dynamic>>())
        t['id'] as int: t,
    };

    when(() => api.get<List<dynamic>>(any())).thenAnswer(
      (inv) async => Response(
        requestOptions: RequestOptions(path: inv.positionalArguments.first as String),
        statusCode: 200,
        data: server.values.map((t) => Map<String, dynamic>.from(t)).toList(),
      ),
    );
    when(() => api.patch<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer((
      inv,
    ) async {
      final path = inv.positionalArguments.first as String;
      final body = Map<String, dynamic>.from(inv.namedArguments[#data] as Map);
      patches.add(body);
      if (gate != null) await gate!.future;
      if (failWrites) throw _serverError(path);
      final id = int.parse(path.split('/').last);
      server[id] = {...server[id]!, ...body};
      return Response(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: Map.of(server[id]!),
      );
    });
    when(() => api.post<Map<String, dynamic>>(any(), data: any(named: 'data'))).thenAnswer((
      inv,
    ) async {
      final body = Map<String, dynamic>.from(inv.namedArguments[#data] as Map);
      posts.add(body);
      if (gate != null) await gate!.future;
      if (failWrites) throw _serverError('/tasks');
      // Real POST 201 shape, with the sent values applied (defaults false).
      final created = {
        ...(_fixture('task_created_flags.json') as Map<String, dynamic>),
        'is_important': false,
        'is_urgent': false,
        ...body,
        'id': 99,
      };
      server[99] = created;
      return Response(
        requestOptions: RequestOptions(path: '/tasks'),
        statusCode: 201,
        data: Map.of(created),
      );
    });
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
  });

  Task serverTask(int id) => Task.fromJson(Map.of(server[id]!));

  /// Planning (real list page) with the form pushed on top: edit for [editId],
  /// otherwise create.
  Future<void> openForm(WidgetTester tester, {int? editId}) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.planningPath,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.planningPath, builder: (_, _) => const TaskListPage()),
        GoRoute(path: AppRouter.tasksNewPath, builder: (_, _) => const TaskEditScreen()),
        GoRoute(
          path: AppRouter.tasksEditPath,
          builder: (_, state) => state.extra is Task
              ? TaskEditScreen(task: state.extra as Task)
              : const TaskEditUnavailablePage(),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        taskRepositoryProvider.overrideWith((ref) async => TaskRepositoryImpl(api)),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        projectRepositoryProvider.overrideWith((ref) async => FakeProjectRepository()),
      ],
    );
    await tester.pumpAndSettle();
    if (editId == null) {
      unawaited(router.push(AppRouter.tasksNewPath));
    } else {
      unawaited(router.push(AppRouter.tasksEditPath, extra: serverTask(editId)));
    }
    await tester.pumpAndSettle();
  }

  final important = find.byKey(const ValueKey('task-important'));
  final urgent = find.byKey(const ValueKey('task-urgent'));
  final saveButton = find.byKey(const ValueKey('task-save'));
  final titleField = find.byKey(const ValueKey('task-title'));

  SwitchListTile tile(WidgetTester tester, Finder f) =>
      tester.widget<SwitchListTile>(find.descendant(of: f, matching: find.byType(SwitchListTile)));
  bool switchValue(WidgetTester tester, Finder f) => tile(tester, f).value;
  bool switchEnabled(WidgetTester tester, Finder f) => tile(tester, f).onChanged != null;
  bool saveEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(saveButton).onPressed != null;

  Future<void> toggle(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
  }

  group('edit mode', () {
    testWidgets('switches show the task values (4 flag pairs); labels and help texts', (
      tester,
    ) async {
      for (final (id, imp, urg) in [(1, true, true), (2, true, false), (3, false, true)]) {
        await openForm(tester, editId: id);
        expect((switchValue(tester, important), switchValue(tester, urgent)), (imp, urg));
        expect(saveEnabled(tester), isFalse, reason: 'task $id: nothing changed');
        router.pop();
        await tester.pumpAndSettle();
      }
      await openForm(tester, editId: 4);
      expect((switchValue(tester, important), switchValue(tester, urgent)), (false, false));
      expect(find.descendant(of: important, matching: find.text('Önemli')), findsOneWidget);
      expect(
        find.descendant(of: important, matching: find.text('Hedeflerine katkısı büyük')),
        findsOneWidget,
      );
      expect(find.descendant(of: urgent, matching: find.text('Acil')), findsOneWidget);
      expect(find.descendant(of: urgent, matching: find.text('Zamanı dar')), findsOneWidget);
    });

    testWidgets('turning "Acil" on enables Kaydet; body is only {is_urgent: true}', (tester) async {
      await openForm(tester, editId: 2);
      await toggle(tester, urgent);
      expect(switchValue(tester, urgent), isTrue);
      expect(saveEnabled(tester), isTrue);

      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(patches, hasLength(1));
      expect(jsonEncode(patches.single), '{"is_urgent":true}');
      expect(find.text(TaskEditScreen.editTitle), findsNothing, reason: 'form closed');
      expect(serverTask(2).isUrgent, isTrue);
      expect(serverTask(2).isImportant, isTrue, reason: 'untouched flag kept');
    });

    testWidgets('turning "Önemli" off sends {is_important: false} only', (tester) async {
      await openForm(tester, editId: 1);
      await toggle(tester, important);
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(jsonEncode(patches.single), '{"is_important":false}');
    });

    testWidgets('switching on and back off: Kaydet disabled again, no request', (tester) async {
      await openForm(tester, editId: 4);
      await toggle(tester, important);
      expect(saveEnabled(tester), isTrue);
      await toggle(tester, important);
      expect(saveEnabled(tester), isFalse);
      await toggle(tester, urgent);
      await toggle(tester, urgent);
      expect(saveEnabled(tester), isFalse);

      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(patches, isEmpty);
    });

    testWidgets('important + urgent task, only the title changed: no flag key in the body', (
      tester,
    ) async {
      await openForm(tester, editId: 1);
      await tester.enterText(titleField, 'Vergi beyannamesini bugün gönder');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(jsonEncode(patches.single), '{"title":"Vergi beyannamesini bugün gönder"}');
      expect((serverTask(1).isImportant, serverTask(1).isUrgent), (true, true));
    });

    testWidgets('while saving the switches are disabled; double tap sends one request', (
      tester,
    ) async {
      gate = Completer<void>();
      await openForm(tester, editId: 4);
      await toggle(tester, urgent);
      expect(switchEnabled(tester, important), isTrue);

      await tapSave(tester);
      await tester.pump();
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();

      expect(switchEnabled(tester, important), isFalse);
      expect(switchEnabled(tester, urgent), isFalse);
      await tester.tap(important, warnIfMissed: false);
      await tester.pump();
      expect(switchValue(tester, important), isFalse, reason: 'disabled switch ignores taps');

      gate!.complete();
      await tester.pumpAndSettle();
      expect(patches, hasLength(1));
      expect(jsonEncode(patches.single), '{"is_urgent":true}');
    });

    testWidgets('a failed save keeps the form and the switch values, then retries', (tester) async {
      failWrites = true;
      await openForm(tester, editId: 3);
      await toggle(tester, important);
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(find.text('Sunucu hatası. Lütfen daha sonra tekrar deneyin.'), findsOneWidget);
      expect(find.text(TaskEditScreen.editTitle), findsOneWidget);
      expect((switchValue(tester, important), switchValue(tester, urgent)), (true, true));
      expect(switchEnabled(tester, important), isTrue);
      expect(saveEnabled(tester), isTrue);

      failWrites = false;
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(patches.map(jsonEncode), ['{"is_important":true}', '{"is_important":true}']);
    });
  });

  group('create mode', () {
    testWidgets('switches start off; untouched → no flag key in the POST body', (tester) async {
      await openForm(tester);
      expect(find.text(TaskEditScreen.createTitle), findsOneWidget);
      expect((switchValue(tester, important), switchValue(tester, urgent)), (false, false));

      await tester.enterText(titleField, 'Sunumu bitir');
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(jsonEncode(posts.single), '{"title":"Sunumu bitir"}');
    });

    testWidgets('only "Önemli" on → only is_important: true in the POST body', (tester) async {
      await openForm(tester);
      await tester.enterText(titleField, 'Haftalık hedefleri yaz');
      await toggle(tester, important);
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(jsonEncode(posts.single), '{"title":"Haftalık hedefleri yaz","is_important":true}');
      expect(serverTask(99).isImportant, isTrue);
      expect(serverTask(99).isUrgent, isFalse);
    });

    testWidgets('both on → both true; double tap sends one POST', (tester) async {
      gate = Completer<void>();
      await openForm(tester);
      await tester.enterText(titleField, 'Sunumu bitir');
      await toggle(tester, important);
      await toggle(tester, urgent);

      await tapSave(tester);
      await tester.pump();
      await tester.tap(saveButton, warnIfMissed: false);
      await tester.pump();
      expect(switchEnabled(tester, urgent), isFalse);
      gate!.complete();
      await tester.pumpAndSettle();

      expect(posts, hasLength(1));
      expect(
        jsonEncode(posts.single),
        '{"title":"Sunumu bitir","is_important":true,"is_urgent":true}',
      );
    });
  });

  testWidgets('each switch row is at least 48 high and fully tappable', (tester) async {
    await openForm(tester, editId: 4);
    for (final f in [important, urgent]) {
      await tester.ensureVisible(f);
      await tester.pumpAndSettle();
      final size = tester.getSize(f);
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.width, greaterThanOrEqualTo(48));
    }
    // A tap on the label (not the knob) toggles: the whole row is the target.
    await tester.tap(find.text('Zamanı dar'));
    await tester.pumpAndSettle();
    expect(switchValue(tester, urgent), isTrue);
  });
}
