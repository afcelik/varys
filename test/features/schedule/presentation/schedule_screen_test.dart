// /schedule page: list (time range, 2-line title, recurrence summary), its
// loading/empty/error states, delete with confirmation, and navigation to
// the forms. Real notifiers; the repository is the server-like fake with
// real backend JSON.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/presentation/schedule_edit_screen.dart';
import 'package:varys/features/schedule/presentation/schedule_screen.dart';

import '../../../helpers/varys_app_harness.dart';
import '../fake_schedule_repository.dart';

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => scheduleFixtureDay;
}

void main() {
  late FakeScheduleRepository repo;
  late GoRouter router;

  setUp(() => repo = FakeScheduleRepository());

  Future<void> pumpPage(WidgetTester tester, {Size size = const Size(600, 1400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    router = GoRouter(
      initialLocation: AppRouter.homePath,
      routes: [
        GoRoute(
          path: AppRouter.homePath,
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(path: AppRouter.schedulePath, builder: (_, _) => const ScheduleScreen()),
        GoRoute(path: AppRouter.scheduleNewPath, builder: (_, _) => const ScheduleEditScreen()),
        GoRoute(
          path: AppRouter.scheduleEditPath,
          builder: (_, state) => ScheduleEditScreen(block: state.extra! as ScheduleBlock),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpVarysApp(
      tester,
      router: router,
      overrides: [
        todayProvider.overrideWith(_FixedToday.new),
        nowProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9, 10)),
        scheduleRepositoryProvider.overrideWith((ref) async => repo),
      ],
    );
    await tester.pump();
    router.push(AppRouter.schedulePath);
  }

  /// Lets the fake repository answer and transitions/dialogs finish (fixed
  /// time steps; no pumpAndSettle while loading).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder rowOf(int id) => find.byKey(ValueKey('schedule-list-row-$id'));
  String textOf(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  group('list', () {
    testWidgets('every block in start time/id order with time range, title and summary', (
      tester,
    ) async {
      await pumpPage(tester);
      await settle(tester);
      expect(find.text(ScheduleScreen.title), findsOneWidget);
      final ids = [6, 1, 2, 3, 7, 4, 5];
      final tops = [for (final id in ids) tester.getTopLeft(rowOf(id)).dy];
      expect(tops, [...tops]..sort());

      expect(textOf(tester, 'schedule-list-time-2'), '08:30\u201309:00');
      expect(textOf(tester, 'schedule-list-time-6'), '00:00\u201323:59');
      expect(textOf(tester, 'schedule-list-title-2'), 'Kahvaltı');
      expect(textOf(tester, 'schedule-list-summary-6'), 'Her gün');
      expect(textOf(tester, 'schedule-list-summary-2'), 'Pzt, Çar, Cum');
      expect(textOf(tester, 'schedule-list-summary-4'), "Ayın 15'i");
      expect(textOf(tester, 'schedule-list-summary-5'), 'Her 3 günde bir');
      expect(repo.listCalls, 1);
      expect(repo.dayCalls, 0, reason: 'the page loads the full list only');
    });

    testWidgets('long title cut at 2 lines; tap targets at least 48', (tester) async {
      await pumpPage(tester, size: const Size(360, 1400));
      await settle(tester);
      final title = tester.widget<Text>(find.byKey(const ValueKey('schedule-list-title-3')));
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
      for (final id in [6, 1, 2, 3, 7, 4, 5]) {
        final del = tester.getSize(find.byKey(ValueKey('schedule-delete-$id')));
        expect(del.width, greaterThanOrEqualTo(48));
        expect(del.height, greaterThanOrEqualTo(48));
        expect(
          tester.getSize(find.byKey(ValueKey('schedule-list-tap-$id'))).height,
          greaterThanOrEqualTo(48),
        );
      }
      final add = tester.getSize(find.byKey(const ValueKey('schedule-add')));
      expect((add.width >= 48, add.height >= 48), (true, true));
    });

    testWidgets('row tap opens the edit form for that block', (tester) async {
      await pumpPage(tester);
      await settle(tester);
      await tester.tap(find.text('Kahvaltı'));
      await settle(tester);
      expect(find.text(ScheduleEditScreen.editTitle), findsOneWidget);
      final form = tester.widget<ScheduleEditScreen>(find.byType(ScheduleEditScreen));
      expect(form.block, repo.sorted.firstWhere((b) => b.id == 2));
    });

    testWidgets('"Blok ekle" opens the create form', (tester) async {
      await pumpPage(tester);
      await settle(tester);
      await tester.tap(find.byTooltip(ScheduleScreen.addText));
      await settle(tester);
      expect(find.text(ScheduleEditScreen.createTitle), findsOneWidget);
      expect(tester.widget<ScheduleEditScreen>(find.byType(ScheduleEditScreen)).block, isNull);
    });
  });

  group('states', () {
    testWidgets('loading: spinner (no pumpAndSettle)', (tester) async {
      repo.listGate = Completer<void>();
      await pumpPage(tester);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('schedule-loading')), findsOneWidget);
      repo.listGate!.complete();
      await settle(tester);
      expect(find.byKey(const ValueKey('schedule-loading')), findsNothing);
      expect(find.text('Kahvaltı'), findsOneWidget);
    });

    testWidgets('empty: text and "Blok ekle" that opens the create form', (tester) async {
      repo.server = [];
      await pumpPage(tester);
      await settle(tester);
      expect(find.text(ScheduleScreen.emptyText), findsOneWidget);
      expect(ScheduleScreen.emptyText, 'Henüz program bloğu yok');
      await tester.tap(find.byKey(const ValueKey('schedule-empty-add')));
      await settle(tester);
      expect(find.text(ScheduleEditScreen.createTitle), findsOneWidget);
    });

    testWidgets('error: userMessage + "Tekrar dene"; retry loads the list', (tester) async {
      const failure = ServerFailure(
        'Sunucu hatası. Lütfen daha sonra tekrar deneyin.',
        statusCode: 500,
      );
      repo.listFailure = failure;
      await pumpPage(tester);
      await settle(tester);
      expect(find.text(userMessage(failure)), findsOneWidget);
      repo.listFailure = null;
      await tester.tap(find.text(ScheduleScreen.retryText));
      await settle(tester);
      expect(find.text('Kahvaltı'), findsOneWidget);
      expect(repo.listCalls, 2);
    });

    testWidgets('reload keeps the current list (no spinner)', (tester) async {
      await pumpPage(tester);
      await settle(tester);
      repo.listGate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('schedule-delete-2')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-delete-confirm')));
      await settle(tester);
      // The delete applied at once; the silent refresh is parked.
      expect(find.byKey(const ValueKey('schedule-loading')), findsNothing);
      expect(find.text('Sabah koşusu'), findsOneWidget);
      expect(rowOf(2), findsNothing);
      repo.listGate!.complete();
      await settle(tester);
    });
  });

  group('delete', () {
    testWidgets('asks first; "Vazgeç" sends nothing', (tester) async {
      await pumpPage(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-delete-2')));
      await settle(tester);
      expect(find.text('Bu blok silinsin mi?'), findsOneWidget);
      expect(
        find.descendant(of: find.byType(AlertDialog), matching: find.text('Kahvaltı')),
        findsOneWidget,
      );
      await tester.tap(find.text(ScheduleScreen.deleteCancelText));
      await settle(tester);
      expect(repo.deleteIds, isEmpty);
      expect(rowOf(2), findsOneWidget);
      expect(find.byType(ScheduleEditScreen), findsNothing, reason: 'delete never opens edit');
    });

    testWidgets('confirm: one DELETE, row gone; a double tap on "Sil" still sends one', (
      tester,
    ) async {
      await pumpPage(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-delete-2')));
      await settle(tester);
      final confirm = find.byKey(const ValueKey('schedule-delete-confirm'));
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.deleteIds, [2]);
      expect(rowOf(2), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('404: snackbar "Kaynak bulunamadı."; the stale row disappears', (tester) async {
      await pumpPage(tester);
      await settle(tester);
      repo.server = repo.server.where((b) => b.id != 2).toList(); // deleted elsewhere
      await tester.tap(find.byKey(const ValueKey('schedule-delete-2')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('schedule-delete-confirm')));
      await settle(tester);
      expect(find.text('Kaynak bulunamadı.'), findsOneWidget);
      expect(rowOf(2), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
