// ScheduleCard: rows (time range + title), now/past/upcoming with a "Şimdi"
// text label, the 8-row limit, navigation targets, quick add, and the card's
// own loading/empty/error states. Data is real backend JSON through the
// server-like FakeScheduleRepository; the clock is a fake (nowProvider).
// The last group drives the real app (real HomeScreen and notifiers, fake
// repositories) across midnight. pumpAndSettle is never used.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/theme/app_theme.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/data/daily_plan_repository.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/home_screen.dart';
import 'package:varys/features/home/presentation/widgets/daily_plan_state_widgets.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/home/presentation/widgets/schedule_card.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/features/projects/data/project_repository_impl.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_repository.dart';
import 'package:varys/features/routines/data/routine_repository_impl.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/domain/routine_repository.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';

import '../../../helpers/varys_app_harness.dart';
import '../../notes/fake_note_repository.dart';
import '../../schedule/fake_schedule_repository.dart';

final _monday = scheduleFixtureDay; // 2026-11-02
final _tuesday = DateTime(2026, 11, 3);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _monday;
}

class _FakeClock {
  _FakeClock(this.value);
  DateTime value;
  DateTime call() => value;
}

void main() {
  late FakeScheduleRepository repo;
  late _FakeClock clock;
  late List<(String, Object?)> pushes;

  setUp(() {
    repo = FakeScheduleRepository();
    clock = _FakeClock(DateTime(2026, 11, 2, 9, 10));
    pushes = [];
  });

  /// The card alone on a page, under a test router that records pushes.
  Future<void> pumpCard(WidgetTester tester, {double width = 400}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    GoRoute target(String path) => GoRoute(
      path: path,
      builder: (_, state) {
        pushes.add((path, state.extra));
        return Scaffold(body: Text('page $path'));
      },
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: SingleChildScrollView(
              child: Column(children: [ScheduleCard(), Text('Diğer kart')]),
            ),
          ),
        ),
        target(AppRouter.schedulePath),
        target(AppRouter.scheduleNewPath),
        target(AppRouter.scheduleEditPath),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          nowProvider.overrideWithValue(clock.call),
          scheduleRepositoryProvider.overrideWith((ref) async => repo),
        ],
        child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
      ),
    );
  }

  /// Lets the fake repository answer (no pumpAndSettle).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  Finder inCard(Finder f) => find.descendant(of: find.byType(ScheduleCard), matching: f);
  Finder row(int id) => find.byKey(ValueKey('schedule-row-$id'));
  Finder nowLabel(int id) => find.byKey(ValueKey('schedule-now-$id'));
  Finder past(int id) => find.byKey(ValueKey('schedule-past-$id'));

  group('filled', () {
    testWidgets('rows in start time/id order: en-dash time range and title', (tester) async {
      await pumpCard(tester);
      await settle(tester);
      expect(find.text(ScheduleCard.title), findsOneWidget);
      final tops = [
        for (final id in [6, 1, 2, 3, 7, 5]) tester.getTopLeft(row(id)).dy,
      ];
      expect(tops, [...tops]..sort());
      expect(find.text('08:30\u201309:00'), findsOneWidget);
      expect(find.text('00:00\u201323:59'), findsOneWidget);
      expect(find.text('Kahvaltı'), findsOneWidget);
      expect(repo.dayRequests, [_monday]);
    });

    testWidgets('09:10: current blocks have the "Şimdi" text; past ones are dimmed but readable; '
        'upcoming ones are normal', (tester) async {
      await pumpCard(tester);
      await settle(tester);
      // 6 00:00-23:59, 3 09:00-10:30, 7 09:00-09:45 are current.
      for (final id in [6, 3, 7]) {
        expect(nowLabel(id), findsOneWidget, reason: 'block $id');
        expect(tester.widget<Text>(nowLabel(id)).data, 'Şimdi');
        expect(past(id), findsNothing);
      }
      // 1 06:30-07:15 and 2 08:30-09:00 are past.
      for (final id in [1, 2]) {
        expect(past(id), findsOneWidget, reason: 'block $id');
        expect(tester.widget<Opacity>(past(id)).opacity, inInclusiveRange(0.5, 0.7));
        expect(nowLabel(id), findsNothing);
      }
      // 5 18:00-18:15 is upcoming.
      expect(past(5), findsNothing);
      expect(nowLabel(5), findsNothing);
      expect(inCard(find.text(ScheduleCard.nowLabel)), findsNWidgets(3));
    });

    testWidgets('the "Şimdi" marker moves with the minute ticker', (tester) async {
      clock.value = DateTime(2026, 11, 2, 9, 44);
      await pumpCard(tester);
      await settle(tester);
      expect(nowLabel(7), findsOneWidget);
      clock.value = DateTime(2026, 11, 2, 9, 45);
      await tester.pump(const Duration(minutes: 1));
      expect(nowLabel(7), findsNothing, reason: 'end is excluded');
      expect(past(7), findsOneWidget);
      expect(nowLabel(3), findsOneWidget);
      expect(repo.dayCalls, 1, reason: 'the minute tick does not reload');
    });

    testWidgets('at most 8 rows; the rest behind "Tümünü gör (+N)" which opens /schedule', (
      tester,
    ) async {
      final base = scheduleListFixture().first;
      repo.server = [
        for (var i = 0; i < 11; i++)
          base.copyWith(
            id: 100 + i,
            title: 'Blok $i',
            startTime: ScheduleTime.hm(i, 0),
            endTime: ScheduleTime.hm(i, 30),
          ),
      ];
      await pumpCard(tester);
      await settle(tester);
      expect(inCard(find.textContaining('Blok ')), findsNWidgets(8));
      expect(find.text('Blok 8'), findsNothing);
      expect(find.text(ScheduleCard.seeAllText(3)), findsOneWidget);
      expect(ScheduleCard.seeAllText(3), 'Tümünü gör (+3)');
      await tester.tap(find.text(ScheduleCard.seeAllText(3)));
      await settle(tester);
      expect(pushes, [(AppRouter.schedulePath, null)]);
    });

    testWidgets('exactly 8 blocks: no "Tümünü gör"', (tester) async {
      final base = scheduleListFixture().first;
      repo.server = [
        for (var i = 0; i < 8; i++)
          base.copyWith(
            id: 100 + i,
            title: 'Blok $i',
            startTime: ScheduleTime.hm(i, 0),
            endTime: ScheduleTime.hm(i, 30),
          ),
      ];
      await pumpCard(tester);
      await settle(tester);
      expect(inCard(find.textContaining('Blok ')), findsNWidgets(8));
      expect(find.byKey(const ValueKey('schedule-card-see-all')), findsNothing);
    });
  });

  group('line counts (2-line titles)', () {
    /// Lines the text at [finder] really draws ('Ağ' line-height reference,
    /// same method as the other overflow tests).
    int drawnLines(WidgetTester tester, Finder finder) {
      final paragraph = tester.renderObject<RenderParagraph>(finder);
      final oneLine = TextPainter(
        text: TextSpan(text: 'Ağ', style: (paragraph.text as TextSpan).style),
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
      )..layout();
      final lines = (tester.getSize(finder).height / oneLine.height).round();
      oneLine.dispose();
      return lines;
    }

    for (final (width, scale) in [(360.0, 1.0), (360.0, 1.5), (1000.0, 1.5)]) {
      testWidgets('255-char unbroken title is cut at 2 lines; the time stays on 1 line '
          '(${width.toInt()}px x$scale)', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpCard(tester, width: width);
        await settle(tester);
        expect(tester.takeException(), isNull);

        final long = find.byKey(const ValueKey('schedule-title-3'));
        expect(tester.widget<Text>(long).data!.runes.length, 255);
        expect(drawnLines(tester, long), 2, reason: 'long title lines');
        final paragraph = tester.renderObject<RenderParagraph>(long);
        expect(paragraph.didExceedMaxLines, isTrue);
        expect(paragraph.overflow, TextOverflow.ellipsis);
        for (final id in [6, 1, 2, 7, 5]) {
          final title = find.byKey(ValueKey('schedule-title-$id'));
          expect(drawnLines(tester, title), inInclusiveRange(1, 2), reason: 'title $id');
        }

        for (final id in [6, 1, 2, 3, 7, 5]) {
          final time = find.byKey(ValueKey('schedule-time-$id'));
          expect(drawnLines(tester, time), 1, reason: 'time $id');
          expect(
            tester.renderObject<RenderParagraph>(time).didExceedMaxLines,
            isFalse,
            reason: 'time $id fits its fixed column',
          );
        }
        final cardRect = tester.getRect(find.byType(ScheduleCard));
        expect(tester.getRect(long).right, lessThanOrEqualTo(cardRect.right));
      });
    }
  });

  group('navigation', () {
    testWidgets('row tap opens /schedule/edit with that block as extra', (tester) async {
      await pumpCard(tester);
      await settle(tester);
      final block = scheduleDayFixture().firstWhere((b) => b.id == 2);
      await tester.tap(find.text('Kahvaltı'));
      await settle(tester);
      expect(pushes, [(AppRouter.scheduleEditPath, block)]);
    });

    testWidgets('"Daha fazla" opens /schedule and never the edit form', (tester) async {
      await pumpCard(tester);
      await settle(tester);
      await tester.tap(find.text(ScheduleCard.moreText));
      await settle(tester);
      expect(pushes, [(AppRouter.schedulePath, null)]);
    });

    testWidgets('"Blok ekle" opens /schedule/new and never the edit form', (tester) async {
      await pumpCard(tester);
      await settle(tester);
      await tester.tap(find.byTooltip(ScheduleCard.addTooltip));
      await settle(tester);
      expect(pushes, [(AppRouter.scheduleNewPath, null)]);
    });

    testWidgets('"Daha fazla" and "Blok ekle" are outside every row InkWell', (tester) async {
      await pumpCard(tester);
      await settle(tester);
      for (final target in [
        find.byKey(const ValueKey('schedule-card-more')),
        find.byKey(const ValueKey('schedule-card-add')),
      ]) {
        expect(
          find.ancestor(
            of: target,
            matching: find.byWidgetPredicate(
              (w) => w is InkWell && '${w.key}'.contains('schedule-row-tap'),
            ),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('tap targets are at least 48x48; rows at least 48 high', (tester) async {
      await pumpCard(tester);
      await settle(tester);
      for (final key in ['schedule-card-add', 'schedule-card-more']) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
      for (final id in [6, 1, 2, 3, 7, 5]) {
        expect(
          tester.getSize(find.byKey(ValueKey('schedule-row-tap-$id'))).height,
          greaterThanOrEqualTo(48),
        );
      }
      expect(
        tester.getSize(find.byKey(const ValueKey('schedule-quick-add'))).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('states', () {
    testWidgets('loading: skeleton inside the card, quick add still there', (tester) async {
      repo.dayGate = Completer<void>();
      await pumpCard(tester);
      await tester.pump();
      expect(find.byKey(const ValueKey('schedule-skeleton')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-quick-add')), findsOneWidget);
      expect(find.text('Diğer kart'), findsOneWidget);
      repo.dayGate!.complete();
      await settle(tester);
      expect(find.byKey(const ValueKey('schedule-skeleton')), findsNothing);
    });

    testWidgets('empty: "Bugün için program yok" and the quick-add field', (tester) async {
      repo.server = [];
      await pumpCard(tester);
      await settle(tester);
      expect(find.text(ScheduleCard.emptyText), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-quick-add')), findsOneWidget);
      expect(find.byKey(const ValueKey('schedule-card-see-all')), findsNothing);
    });

    testWidgets('error: userMessage + "Tekrar dene" only in this card; retry reloads the card', (
      tester,
    ) async {
      const failure = NetworkFailure('Bağlantı hatası');
      repo.dayFailure = failure;
      await pumpCard(tester);
      await settle(tester);
      expect(inCard(find.text(userMessage(failure))), findsOneWidget);
      expect(find.text('Diğer kart'), findsOneWidget);
      final retry = find.byKey(const ValueKey('schedule-card-retry'));
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

      repo.dayFailure = null;
      await tester.tap(find.text(ScheduleCard.retryText));
      await settle(tester);
      expect(repo.dayCalls, 2);
      expect(find.text('Kahvaltı'), findsOneWidget);
      expect(find.text(userMessage(failure)), findsNothing);
    });

    testWidgets('reload keeps the old rows (no skeleton flash)', (tester) async {
      await pumpCard(tester);
      await settle(tester);
      repo.dayGate = Completer<void>();
      final container = ProviderScope.containerOf(tester.element(find.byType(ScheduleCard)));
      container.invalidate(scheduleForDayProvider(_monday));
      await tester.pump();
      expect(find.byKey(const ValueKey('schedule-skeleton')), findsNothing);
      expect(find.text('Kahvaltı'), findsOneWidget);
      repo.dayGate!.complete();
      await settle(tester);
    });
  });

  group('quick add', () {
    Finder field() => find.byKey(const ValueKey('schedule-quick-add'));
    String fieldText(WidgetTester tester) => tester.widget<TextField>(field()).controller!.text;

    Future<void> submit(WidgetTester tester, String text) async {
      await tester.enterText(field(), text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }

    testWidgets('valid: one request (daily from today), field cleared, row shown in order', (
      tester,
    ) async {
      await pumpCard(tester);
      await settle(tester);
      await submit(tester, '07:30-08:00 kahvaltı hazırlığı');
      await settle(tester);
      expect(repo.createBodies, hasLength(1));
      final body = repo.createBodies.single;
      expect(
        (body['title'], body['start_time'], body['end_time']),
        ('kahvaltı hazırlığı', '07:30', '08:00'),
      );
      expect((body['recurrence_type'], body['start_date']), ('daily', _monday));
      expect(fieldText(tester), isEmpty);
      final newRow = find.text('kahvaltı hazırlığı');
      expect(newRow, findsOneWidget);
      expect(
        tester.getTopLeft(newRow).dy,
        greaterThan(tester.getTopLeft(find.text('Sabah koşusu')).dy),
      );
      expect(tester.getTopLeft(newRow).dy, lessThan(tester.getTopLeft(find.text('Kahvaltı')).dy));
    });

    testWidgets('invalid: Turkish message under the field and no request; typing clears it', (
      tester,
    ) async {
      await pumpCard(tester);
      await settle(tester);
      for (final (input, message) in [
        ('kahvaltı', quickAddFormatMessage),
        ('23:00-24:00 gece', timeOutOfRangeMessage),
        ('09:00-08:00 ters', timeRangeInvalidMessage),
        ('08:30-09:00', 'Başlık gerekli'),
      ]) {
        await submit(tester, input);
        expect(find.text(message), findsOneWidget, reason: input);
        expect(fieldText(tester), input, reason: 'text kept');
      }
      expect(repo.createBodies, isEmpty);
      await tester.enterText(field(), '08:30-09:00 k');
      await tester.pump();
      expect(find.text('Başlık gerekli'), findsNothing);
    });

    testWidgets('double Enter while the request runs sends one request', (tester) async {
      await pumpCard(tester);
      await settle(tester);
      repo.mutationGate = Completer<void>();
      await tester.enterText(field(), '08:30-09:00 kahvaltı');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(tester.widget<TextField>(field()).enabled, isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      repo.mutationGate!.complete();
      await settle(tester);
      expect(repo.createBodies, hasLength(1));
      expect(tester.widget<TextField>(field()).enabled, isTrue);
    });

    testWidgets('server error: text kept, field enabled again, snackbar with userMessage', (
      tester,
    ) async {
      const failure = ServerFailure('Gönderilen veriler geçersiz.', statusCode: 422);
      repo.createFailure = failure;
      await pumpCard(tester);
      await settle(tester);
      await submit(tester, '08:30-09:00 kahvaltı');
      await settle(tester);
      expect(repo.createBodies, hasLength(1));
      expect(fieldText(tester), '08:30-09:00 kahvaltı');
      expect(tester.widget<TextField>(field()).enabled, isTrue);
      expect(find.text(userMessage(failure)), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // let the snackbar go
    });
  });

  group('Home across midnight (real app, real notifiers, fake repositories)', () {
    testWidgets('23:59 -> 00:00: no error on Home; the new day fills in; plan, routines, '
        'note of the day and schedule each +1, projects 0; "Şimdi" for 00:00', (tester) async {
      await initializeDateFormatting('tr_TR', null);
      registerFallbackValue(DateTime(2000));
      registerFallbackValue(TaskFilter.all);
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'a.b.c'});

      final planJson =
          jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
              as Map<String, dynamic>;
      final tasks = (planJson['tasks'] as List)
          .map((t) => Task.fromJson(t as Map<String, dynamic>))
          .toList();
      final routines =
          (jsonDecode(File('test/fixtures/routines_day.json').readAsStringSync()) as List)
              .map((e) => RoutineDayItem.fromJson(e as Map<String, dynamic>))
              .toList();
      final projects =
          (jsonDecode(File('test/fixtures/projects_list.json').readAsStringSync()) as List)
              .map((e) => Project.fromJson(e as Map<String, dynamic>))
              .toList();
      final limits = ProjectLimits.fromJson(
        jsonDecode(File('test/fixtures/projects_limits.json').readAsStringSync())
            as Map<String, dynamic>,
      );

      final planRepo = _MockDailyPlanRepository();
      final taskRepo = _MockTaskRepository();
      final routineRepo = _MockRoutineRepository();
      final projectRepo = _MockProjectRepository();
      final noteRepo = FakeNoteRepository();
      when(() => planRepo.getPlan(any())).thenAnswer(
        (inv) async => Right(
          DailyPlan(
            planDate: inv.positionalArguments.first as DateTime,
            mainFocus: tasks.first,
            tasks: tasks,
          ),
        ),
      );
      when(() => taskRepo.getTasksByFilter(any())).thenAnswer((_) async => Right(tasks));
      when(() => routineRepo.getRoutinesForDay(any())).thenAnswer((_) async => Right(routines));
      when(
        () => projectRepo.getProjects(status: any(named: 'status')),
      ).thenAnswer((_) async => Right(projects));
      when(() => projectRepo.getLimits()).thenAnswer((_) async => Right(limits));

      clock.value = DateTime(2026, 11, 2, 23, 59);
      tester.view.physicalSize = const Size(790, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpVarysApp(
        tester,
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          nowProvider.overrideWithValue(clock.call),
          dailyPlanRepositoryProvider.overrideWith((ref) async => planRepo),
          taskRepositoryProvider.overrideWith((ref) async => taskRepo),
          routineRepositoryProvider.overrideWith((ref) async => routineRepo),
          projectRepositoryProvider.overrideWith((ref) async => projectRepo),
          noteRepositoryProvider.overrideWith((ref) async => noteRepo),
          scheduleRepositoryProvider.overrideWith((ref) async => repo),
        ],
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(ScheduleCard), findsOneWidget);
      // At 23:59 nothing on Monday is current: even 00:00-23:59 ends (exclusive) at 23:59.
      expect(find.text(ScheduleCard.nowLabel), findsNothing);
      expect(past(6), findsOneWidget);

      int projectCalls() =>
          verify(() => projectRepo.getProjects(status: any(named: 'status'))).callCount;
      final projectsBefore = projectCalls();
      final limitsBefore = verify(() => projectRepo.getLimits()).callCount;
      expect(projectsBefore, greaterThan(0));
      expect(verify(() => planRepo.getPlan(_monday)).callCount, 1);
      expect(verify(() => routineRepo.getRoutinesForDay(_monday)).callCount, 1);
      expect(noteRepo.ofDayDays, [_monday]);
      expect(repo.dayRequests, [_monday]);
      expect(verify(() => taskRepo.getTasksByFilter(any())).callCount, greaterThan(0));

      clock.value = DateTime(2026, 11, 3, 0, 0);
      await tester.pump(const Duration(minutes: 1));
      // Every frame of the switch: Home keeps its content, never the
      // full-page loading or error view.
      for (var i = 0; i < 20; i++) {
        expect(find.byType(DailyPlanLoading), findsNothing, reason: 'frame $i');
        expect(find.byType(DailyPlanError), findsNothing, reason: 'frame $i');
        expect(find.byType(ScheduleCard), findsOneWidget, reason: 'frame $i');
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.byType(DailyPlanError), findsNothing, reason: 'no error on Home');
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(MainFocusCard), findsOneWidget, reason: 'Home filled again');
      expect(find.byType(ScheduleCard), findsOneWidget);

      verify(() => planRepo.getPlan(_tuesday)).called(1);
      verifyNever(() => planRepo.getPlan(_monday));
      verify(() => routineRepo.getRoutinesForDay(_tuesday)).called(1);
      // The task list does not follow the day: no new request.
      verifyNever(() => taskRepo.getTasksByFilter(any()));
      verifyNever(() => routineRepo.getRoutinesForDay(_monday));
      expect(noteRepo.ofDayDays, [_monday, _tuesday]);
      expect(repo.dayRequests, [_monday, _tuesday]);
      // Projects: no new requests (calls before midnight were verified above).
      expect(limitsBefore, greaterThan(0));
      verifyNever(() => projectRepo.getProjects(status: any(named: 'status')));
      verifyNever(() => projectRepo.getLimits());

      // Tuesday at 00:00: only the 00:00-23:59 block is current; 2 (Mon/Wed/Fri) is gone.
      expect(find.text('Kahvaltı'), findsNothing);
      expect(nowLabel(6), findsOneWidget);
      expect(find.text(ScheduleCard.nowLabel), findsOneWidget);
    });
  });
}

class _MockDailyPlanRepository extends Mock implements DailyPlanRepository {}

class _MockTaskRepository extends Mock implements TaskRepository {}

class _MockRoutineRepository extends Mock implements RoutineRepository {}

class _MockProjectRepository extends Mock implements ProjectRepository {}
