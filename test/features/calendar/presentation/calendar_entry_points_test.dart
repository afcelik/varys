// Entry points to /calendar on Home, widget level: the date header becomes
// one >= 48 high button labelled 'Takvimi aç' only when given onTap (plain
// text otherwise, as before), and the schedule card header gets a 48x48
// 'Takvim' button left of 'Blok ekle' without squeezing the title out.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:varys/core/theme/app_theme.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/widgets/date_header.dart';
import 'package:varys/features/home/presentation/widgets/schedule_card.dart';
import 'package:varys/features/schedule/data/schedule_repository_impl.dart';

import '../../schedule/fake_schedule_repository.dart';

class _FixedToday extends TodayNotifier {
  @override
  DateTime build() => scheduleFixtureDay;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR', null));

  Future<void> pumpHeader(WidgetTester tester, {VoidCallback? onTap, double scale = 1.0}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [DateHeader(date: DateTime(2026, 11, 21), onTap: onTap)],
            ),
          ),
        ),
      ),
    );
  }

  group('DateHeader', () {
    testWidgets('without onTap: plain text, no button, unchanged size', (tester) async {
      await pumpHeader(tester);
      expect(find.text('Cumartesi, 21 Kasım'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
      expect(find.bySemanticsLabel(DateHeader.openCalendarLabel), findsNothing);
      expect(tester.getSize(find.byType(DateHeader)).height, 40);
    });

    for (final scale in [1.0, 1.5]) {
      testWidgets('with onTap: one button >= 48 high labelled "Takvimi aç", scale $scale', (
        tester,
      ) async {
        var taps = 0;
        await pumpHeader(tester, onTap: () => taps++, scale: scale);
        final handle = tester.ensureSemantics();
        expect(
          tester.getSemantics(find.byKey(const ValueKey('date-header-tap'))),
          matchesSemantics(
            label: 'Takvimi aç',
            value: 'Cumartesi, 21 Kasım',
            isButton: true,
            hasTapAction: true,
            isFocusable: true,
            hasFocusAction: true,
          ),
        );
        handle.dispose();
        final size = tester.getSize(find.byKey(const ValueKey('date-header-tap')));
        expect(size.height, greaterThanOrEqualTo(48));
        // 1.0: 40 -> 48 (min height); 1.5: already 56, unchanged.
        expect(tester.getSize(find.byType(DateHeader)).height, scale == 1.0 ? 48 : 56);
        await tester.tap(find.text('Cumartesi, 21 Kasım'));
        expect(taps, 1);
      });
    }
  });

  group('ScheduleCard header', () {
    for (final (width, scale) in [(360.0, 1.0), (360.0, 1.5), (800.0, 1.0)]) {
      testWidgets('calendar button 48x48 left of "Blok ekle"; title still drawn, '
          '${width.toInt()}px x$scale', (tester) async {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              todayProvider.overrideWith(_FixedToday.new),
              nowProvider.overrideWithValue(() => DateTime(2026, 11, 2, 9, 10)),
              scheduleRepositoryProvider.overrideWith((ref) async => FakeScheduleRepository()),
            ],
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: const Scaffold(body: SingleChildScrollView(child: ScheduleCard())),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final calendar = find.byKey(const ValueKey('schedule-card-calendar'));
        final add = find.byKey(const ValueKey('schedule-card-add'));
        expect(tester.widget<IconButton>(calendar).tooltip, ScheduleCard.calendarTooltip);
        expect(ScheduleCard.calendarTooltip, 'Takvim');
        final size = tester.getSize(calendar);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(tester.getTopLeft(add).dx, greaterThanOrEqualTo(tester.getTopRight(calendar).dx));
        expect(tester.getCenter(add).dy, tester.getCenter(calendar).dy);
        final title = find.text(ScheduleCard.title);
        expect(title, findsOneWidget);
        expect(tester.getSize(title).width, greaterThan(48));
        expect(tester.getTopRight(title).dx, lessThanOrEqualTo(tester.getTopLeft(calendar).dx));
      });
    }
  });
}
