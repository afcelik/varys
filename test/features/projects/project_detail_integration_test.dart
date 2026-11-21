// End-to-end inside the app: real app router, real HomeScreen, real
// notifiers (projects list, active projects, task list, eisenhower tasks,
// daily plan). Only the repositories are fake, and the task and project
// servers are consistent: a project's total/done/progress are counted from
// the task server's (non-deleted) tasks with the backend formula
// (`round(done * 100 / total)`, round half to even; null with no tasks).
//
// Flow: Home card -> /projects -> project 1 -> Görev ekle -> Kaydet: the task
// is on the detail page, and "N/M görev", the percent, the /projects row and
// the Home "Aktif Projeler" card all show the new counts. Completing a task
// on the detail page moves it to "Tamamlananlar" and updates the progress
// everywhere. Other Home cards (routines, note, schedule) are not reloaded;
// the daily plan is reloaded once per task change (Home's task sync).

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/projects_card.dart';
import 'package:varys/features/home/presentation/widgets/routines_card.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_edit_screen.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/presentation/project_detail_screen.dart';
import 'package:varys/features/projects/presentation/projects_screen.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';

import '../../helpers/varys_app_harness.dart';
import '../calendar/fake_task_server.dart';
import '../notes/fake_note_repository.dart';
import '../schedule/fake_schedule_repository.dart';
import 'fake_project_repository.dart';

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

final _day = DateTime(2026, 11, 1);
final _now = DateTime(2026, 11, 1, 9);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _day;
}

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// Backend `progress_percent`: Python round() (half to even); null for 0.
int? _percent(int total, int done) {
  if (total == 0) return null;
  final n = done * 100;
  final q = n ~/ total;
  final r = n % total;
  if (r * 2 > total) return q + 1;
  if (r * 2 < total) return q;
  return q.isEven ? q : q + 1;
}

/// Projects whose counts always come from [tasks] (like the backend).
class _ConsistentProjectServer extends FakeProjectRepository {
  _ConsistentProjectServer(this.tasks);

  final FakeTaskServer tasks;

  Project _counted(Project p) {
    final mine = tasks.server.where((t) => t.projectId == p.id && t.deletedAt == null);
    final total = mine.length;
    final done = mine.where((t) => t.status == TaskStatus.done).length;
    return p.copyWith(totalTasks: total, doneTasks: done, progressPercent: _percent(total, done));
  }

  @override
  Future<Either<Failure, List<Project>>> getProjects({ProjectStatus? status}) async {
    final result = await super.getProjects(status: status);
    return result.map((list) => list.map(_counted).toList());
  }
}

Task _task(int id, String title, {int? projectId = 1, TaskStatus status = TaskStatus.todo}) {
  final at = DateTime(2026, 10, id);
  return Task(
    id: id,
    title: title,
    status: status,
    createdAt: at,
    updatedAt: at,
    projectId: projectId,
  );
}

void main() {
  late _MockDailyPlanRepository planRepo;
  late _MockRoutineRepository routineRepo;
  late FakeTaskServer taskServer;
  late _ConsistentProjectServer projectServer;
  late FakeNoteRepository noteRepo;
  late FakeScheduleRepository scheduleRepo;
  var routineCalls = 0;

  setUpAll(() async {
    await initializeDateFormatting('tr_TR', null);
    registerFallbackValue(DateTime(2000));
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});
    planRepo = _MockDailyPlanRepository();
    routineRepo = _MockRoutineRepository();
    // Project 1 "Ev taşıma": 4 tasks, 1 done -> 25% (as the real fixture);
    // project 2 "Kitap okuma listesi": none -> null.
    taskServer = FakeTaskServer([
      _task(1, 'Kira sözleşmesi', status: TaskStatus.done),
      _task(2, 'Kutuları al'),
      _task(3, 'Nakliyeci ara'),
      _task(4, 'Adres değişikliği'),
      _task(5, 'Projesiz iş', projectId: null),
    ]);
    projectServer = _ConsistentProjectServer(taskServer);
    noteRepo = FakeNoteRepository();
    scheduleRepo = FakeScheduleRepository();

    final routines = (_read('routines_day.json') as List)
        .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
        .toList();
    when(
      () => planRepo.getPlan(any()),
    ).thenAnswer((_) async => Right(DailyPlan(planDate: _day, tasks: const [])));
    routineCalls = 0;
    when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async {
      routineCalls++;
      return Right(routines);
    });
  });

  Finder inCard(Finder f) => find.descendant(of: find.byType(ProjectsCard), matching: f);
  Finder key(String k) => find.byKey(ValueKey(k));
  String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!;

  /// Calls of the other Home cards' repositories, to compare before/after.
  ({int routines, int notesOfDay, int notesList, int scheduleDay, int scheduleList}) otherCalls() =>
      (
        routines: routineCalls,
        notesOfDay: noteRepo.ofDayCalls,
        notesList: noteRepo.listCalls,
        scheduleDay: scheduleRepo.dayCalls,
        scheduleList: scheduleRepo.listCalls,
      );

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(790, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpVarysApp(
      tester,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        nowProvider.overrideWithValue(() => _now),
        dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
        taskRepositoryProvider.overrideWith((ref) async => taskServer),
        routineRepositoryProvider.overrideWith((ref) async => routineRepo),
        projectRepositoryProvider.overrideWith((ref) async => projectServer),
        noteRepositoryProvider.overrideWith((ref) async => noteRepo),
        scheduleRepositoryProvider.overrideWith((ref) async => scheduleRepo),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(inCard(find.text('Ev taşıma')), findsOneWidget);
    expect(inCard(find.text('%25')), findsOneWidget);
    expect(
      find.descendant(of: find.byType(RoutinesCard), matching: find.text('Su iç')),
      findsOneWidget,
    );
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.arrow_back).last);
    await tester.pumpAndSettle();
  }

  /// Home card "Daha fazla" -> /projects -> row of project 1 -> detail.
  Future<void> openDetailFromProjects(WidgetTester tester) async {
    await tapVisible(tester, inCard(find.text(ProjectsCard.moreText)));
    expect(find.byType(ProjectsScreen), findsOneWidget);
    await tapVisible(tester, key('project-title-1'));
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
  }

  Finder projectsRowText(int id, String t) =>
      find.descendant(of: key('project-row-$id'), matching: find.text(t));

  testWidgets('Görev ekle on the detail page: task listed, "N/M görev" and percent updated on '
      'the detail page, the /projects row and the Home card; other cards not reloaded', (
    tester,
  ) async {
    await pumpApp(tester);
    final before = otherCalls();
    expect(before.routines, greaterThan(0), reason: 'the routines card loaded');
    expect(before.scheduleDay, greaterThan(0), reason: 'the schedule card loaded');
    expect(before.notesOfDay + before.notesList, greaterThan(0), reason: 'the note card loaded');
    clearInteractions(planRepo);

    await openDetailFromProjects(tester);
    expect(text(tester, 'project-detail-count'), '1/4 görev');
    expect(text(tester, 'project-detail-percent'), '%25');
    expect(find.text('Kutuları al'), findsOneWidget);
    expect(find.text('Projesiz iş'), findsNothing);
    expect(text(tester, 'project-detail-done-title'), 'Tamamlananlar (1)');

    await tapVisible(tester, key('project-detail-add-task'));
    expect(find.byType(TaskEditScreen), findsOneWidget);
    final menu = tester.widget<DropdownMenu<ProjectChoice>>(
      find.byType(DropdownMenu<ProjectChoice>),
    );
    expect(menu.initialSelection?.id, 1, reason: 'project chosen in advance');
    await tester.enterText(key('task-title'), 'Perdeleri as');
    await tester.pump();
    await tapVisible(tester, key('task-save'));

    // Back on the detail page with the new task and the server's new counts.
    expect(find.byType(TaskEditScreen), findsNothing);
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    final created = taskServer.server.firstWhere((t) => t.title == 'Perdeleri as');
    expect(created.projectId, 1);
    expect(find.byKey(ValueKey('project-task-${created.id}')), findsOneWidget);
    expect(text(tester, 'project-detail-count'), '1/5 görev');
    expect(text(tester, 'project-detail-percent'), '%20');
    expect(
      tester.widget<LinearProgressIndicator>(key('project-detail-progress')).value,
      closeTo(0.20, 1e-9),
    );

    await back(tester);
    expect(find.byType(ProjectsScreen), findsOneWidget);
    expect(projectsRowText(1, '%20'), findsOneWidget, reason: '/projects row updated');
    expect(projectsRowText(1, '%25'), findsNothing);

    await back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(inCard(find.text('%20')), findsOneWidget, reason: 'Home card updated');
    expect(inCard(find.text('%25')), findsNothing);

    expect(otherCalls(), before, reason: 'routines, note and schedule not reloaded');
    verify(() => planRepo.getPlan(any())).called(1);
  });

  testWidgets('completing a task on the detail page: it moves to "Tamamlananlar" and the '
      'progress updates on the detail page, the /projects row and the Home card', (tester) async {
    await pumpApp(tester);
    final before = otherCalls();
    expect(before.routines, greaterThan(0), reason: 'the routines card loaded');
    expect(before.scheduleDay, greaterThan(0), reason: 'the schedule card loaded');
    expect(before.notesOfDay + before.notesList, greaterThan(0), reason: 'the note card loaded');
    clearInteractions(planRepo);

    // Open from the Home card row this time.
    await tapVisible(tester, inCard(find.text('Ev taşıma')));
    expect(find.byType(ProjectDetailScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('project-task-2')), findsOneWidget);

    await tapVisible(tester, key('project-task-check-2'));
    expect(taskServer.server.firstWhere((t) => t.id == 2).status, TaskStatus.done);
    expect(find.byKey(const ValueKey('project-task-2')), findsNothing, reason: 'left pending');
    expect(text(tester, 'project-detail-done-title'), 'Tamamlananlar (2)');
    expect(text(tester, 'project-detail-count'), '2/4 görev');
    expect(text(tester, 'project-detail-percent'), '%50');

    await tapVisible(tester, key('project-detail-done-toggle'));
    expect(find.byKey(const ValueKey('project-task-2')), findsOneWidget);
    expect(tester.widget<Checkbox>(key('project-task-check-2')).value, isTrue);

    await back(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(inCard(find.text('%50')), findsOneWidget, reason: 'Home card updated');

    await tapVisible(tester, inCard(find.text(ProjectsCard.moreText)));
    expect(projectsRowText(1, '%50'), findsOneWidget, reason: '/projects row updated');

    expect(otherCalls(), before, reason: 'routines, note and schedule not reloaded');
    verify(() => planRepo.getPlan(any())).called(1);
  });

  testWidgets('first task of an empty project: "Henüz görev yok" becomes "%0" and "0/1 görev"; '
      'completing it gives "%100"', (tester) async {
    await pumpApp(tester);
    await tapVisible(tester, inCard(find.text('Kitap okuma listesi')));
    expect(text(tester, 'project-detail-no-tasks'), 'Henüz görev yok');
    expect(key('project-detail-tasks-empty'), findsOneWidget);

    await tapVisible(tester, key('project-detail-add-task'));
    await tester.enterText(key('task-title'), 'İlk kitap');
    await tester.pump();
    await tapVisible(tester, key('task-save'));

    expect(key('project-detail-no-tasks'), findsNothing);
    expect(text(tester, 'project-detail-percent'), '%0');
    expect(text(tester, 'project-detail-count'), '0/1 görev');
    final created = taskServer.server.firstWhere((t) => t.title == 'İlk kitap');
    expect(created.projectId, 2);

    await tapVisible(tester, key('project-task-check-${created.id}'));
    expect(text(tester, 'project-detail-percent'), '%100');
    expect(text(tester, 'project-detail-count'), '1/1 görev');
    expect(key('project-detail-tasks-empty'), findsOneWidget);

    await back(tester);
    expect(inCard(find.text('%100')), findsOneWidget);
  });

  test('backend rounding (half to even) in the fake server: 1/3, 2/3, 1/8, 3/8, 0/n, none', () {
    expect(_percent(3, 1), 33);
    expect(_percent(3, 2), 67);
    expect(_percent(8, 1), 12);
    expect(_percent(8, 3), 38);
    expect(_percent(5, 0), 0);
    expect(_percent(0, 0), isNull);
  });
}
