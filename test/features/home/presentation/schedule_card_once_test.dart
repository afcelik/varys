// ScheduleCard quick add with the 'bugün' prefix: the hint shows it (one
// line, no overflow, the field keeps its one-line height), a prefixed line makes a
// one-time block shown in the card and due only on that day, and the format
// error names the optional prefix. Data is real backend JSON through the
// server-like FakeScheduleRepository. pumpAndSettle is never used.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/theme/app_theme.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/widgets/schedule_card.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';

import '../../schedule/fake_schedule_repository.dart';

final _monday = scheduleFixtureDay; // 2026-11-02
final _tuesday = DateTime(2026, 11, 3);

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => _monday;
}

const _hint = 'Örn: bugün 14:00-15:00 doktor';

void main() {
  late FakeScheduleRepository repo;

  setUp(() => repo = FakeScheduleRepository());

  Future<void> pumpCard(WidgetTester tester, {double width = 400, double scale = 1.0}) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
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
        for (final path in [
          AppRouter.schedulePath,
          AppRouter.scheduleNewPath,
          AppRouter.scheduleEditPath,
        ])
          GoRoute(
            path: path,
            builder: (_, _) => Scaffold(body: Text('page $path')),
          ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayProvider.overrideWith(_FixedToday.new),
          nowProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9, 10)),
          scheduleRepositoryProvider.overrideWith((ref) async => repo),
        ],
        child: MaterialApp.router(theme: AppTheme.darkTheme, routerConfig: router),
      ),
    );
  }

  /// Lets the fake repository answer (no pumpAndSettle).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  final field = find.byKey(const ValueKey('schedule-quick-add'));
  Finder hintText() => find.descendant(of: field, matching: find.text(_hint));

  test('hint text mentions the optional prefix', () {
    expect(ScheduleCard.quickAddHint, _hint);
  });

  // One line, never wrapping or overflowing. The test font draws every glyph
  // 1em wide, so the narrower cases end in an ellipsis here; the line count
  // and the height are what is checked.
  for (final (width, scale, whole) in [
    (600.0, 1.0, true),
    (400.0, 1.0, false),
    (360.0, 1.0, false),
    (360.0, 1.5, false),
    (320.0, 1.5, false),
  ]) {
    testWidgets('${width.toInt()}px x$scale: hint on one line, no overflow, the empty field '
        'is as high as a filled one${whole ? ', hint shown whole' : ''}', (tester) async {
      await pumpCard(tester, width: width, scale: scale);
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(hintText(), findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(hintText());
      expect(paragraph.maxLines, 1);
      final lines = paragraph
          .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: _hint.length))
          .map((b) => b.top.round())
          .toSet();
      expect(lines, hasLength(1));
      expect(paragraph.size.height, lessThan(2 * paragraph.preferredLineHeight));
      if (whole) expect(paragraph.didExceedMaxLines, isFalse, reason: 'whole hint');
      final emptyHeight = tester.getSize(field).height;
      expect(emptyHeight, greaterThanOrEqualTo(48));
      expect(tester.getRect(field).right, lessThanOrEqualTo(width));

      await tester.enterText(field, '08:30-09:00 kahvaltı');
      await tester.pump();
      expect(tester.getSize(field).height, emptyHeight, reason: 'the hint adds no height');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets("'bugün 14:00-15:00 doktor': a one-time block today, shown in the card, not due "
      'tomorrow; the field clears', (tester) async {
    await pumpCard(tester);
    await settle(tester);
    await tester.enterText(field, 'bugün 14:00-15:00 doktor');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    final body = repo.createBodies.single;
    expect(body['recurrence_type'], 'once');
    expect(body['start_date'], _monday);
    expect(body['title'], 'doktor');
    expect(body['days_of_week'], isNull);
    expect(body['day_of_month'], isNull);
    expect(body['interval_days'], isNull);

    expect(find.text('doktor'), findsOneWidget);
    expect(find.text('14:00\u201315:00'), findsOneWidget);
    expect(
      tester
          .widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
          .controller
          .text,
      isEmpty,
    );
    final created = repo.server.last;
    expect(FakeScheduleRepository.isDue(created, _monday), isTrue);
    expect(FakeScheduleRepository.isDue(created, _tuesday), isFalse);
    final tomorrow = (await repo.getBlocksForDay(_tuesday)).fold((f) => fail('$f'), (l) => l);
    expect(tomorrow.map((b) => b.id), isNot(contains(created.id)));
  });

  testWidgets("'yarın 10:00-11:00 x' and 'bugün' alone: the prefixed format error, nothing sent", (
    tester,
  ) async {
    await pumpCard(tester);
    await settle(tester);
    for (final input in ['yarın 10:00-11:00 x', 'bugün']) {
      await tester.enterText(field, input);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);
      expect(find.text(quickAddFormatMessage), findsOneWidget, reason: input);
      expect(find.text('Biçim: [bugün] 08:30-09:00 başlık'), findsOneWidget);
    }
    expect(repo.createBodies, isEmpty);
  });
}
