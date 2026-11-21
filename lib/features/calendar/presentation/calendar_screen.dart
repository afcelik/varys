import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/calendar/presentation/calendar_providers.dart';
import 'package:varys/features/calendar/presentation/widgets/calendar_day_list.dart';
import 'package:varys/features/calendar/presentation/widgets/calendar_month_grid.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// /calendar: month grid and the selected day's records. Full-screen page
/// outside the shell (pushed from Home); not a menu destination.
///
/// Width >= [wideBreakpoint]: grid left, day list right (each scrolls).
/// Narrower: grid on top, list below, the whole page scrolls.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  static const String title = 'Takvim';
  static const String todayText = 'Bugün';
  static const double wideBreakpoint = 900;
  static const double gridMaxWidth = 560;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Refreshes the open month once after task / routine / schedule changes.
    ref.watch(calendarMonthSyncProvider);

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: const Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            key: const ValueKey('calendar-today'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => ref.read(calendarViewProvider.notifier).goToToday(),
            child: const Text(todayText),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= wideBreakpoint) {
              return Row(
                key: const ValueKey('calendar-wide'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey('calendar-grid-scroll'),
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: _Grid(),
                    ),
                  ),
                  VerticalDivider(width: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      key: ValueKey('calendar-list-scroll'),
                      padding: EdgeInsets.all(16),
                      child: CalendarDayList(),
                    ),
                  ),
                ],
              );
            }
            return const SingleChildScrollView(
              key: ValueKey('calendar-narrow'),
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Grid(),
                  Divider(height: 24),
                  Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: CalendarDayList()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The month grid, centered and at most [CalendarScreen.gridMaxWidth] wide.
class _Grid extends StatelessWidget {
  const _Grid();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: CalendarScreen.gridMaxWidth),
        child: const CalendarMonthGrid(),
      ),
    );
  }
}
