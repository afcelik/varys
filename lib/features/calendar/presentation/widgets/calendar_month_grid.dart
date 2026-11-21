import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/features/calendar/domain/calendar_grid.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';
import 'package:varys/features/calendar/presentation/calendar_providers.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/today_provider.dart';

/// Month header (previous / title / next), Monday-first weekday row and the
/// day cells with count marks.
///
/// The cells always come from [monthGrid] (no request needed); counts appear
/// when the month has loaded. First load: a progress bar and skeleton marks.
/// Refresh: the old counts stay. Error: `userMessage` and 'Tekrar dene' under
/// the grid; old counts (if any) stay.
class CalendarMonthGrid extends ConsumerWidget {
  const CalendarMonthGrid({super.key});

  static const String previousTooltip = 'Önceki ay';
  static const String nextTooltip = 'Sonraki ay';
  static const String retryText = 'Tekrar dene';
  static const String todaySuffix = ', bugün';

  /// Screen-reader text of a day's marks: 'N görev, M rutin, K program blok',
  /// plus ', D bitiş' when tasks are due that day.
  static String countsLabel(CalendarDay d) {
    final base = '${d.taskCount} görev, ${d.routineCount} rutin, ${d.scheduleCount} program blok';
    return d.dueCount > 0 ? '$base, ${d.dueCount} bitiş' : base;
  }

  /// Screen-reader text of a cell: '21 Kasım' (+ ', bugün').
  static String dayLabel(DateTime day, {required bool isToday}) =>
      '${day.day} ${turkishMonthNames[day.month - 1]}${isToday ? todaySuffix : ''}';

  static bool hasCounts(CalendarDay d) =>
      d.taskCount + d.dueCount + d.routineCount + d.scheduleCount > 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final view = ref.watch(calendarViewProvider);
    final today = dayOnly(ref.watch(todayProvider));
    final monthValue = ref.watch(calendarVisibleMonthProvider);
    final notifier = ref.read(calendarViewProvider.notifier);

    final counts = {
      for (final d in monthValue.valueOrNull?.days ?? const <CalendarDay>[]) d.day: d,
    };
    final firstLoad = !monthValue.hasValue && !monthValue.hasError;
    final cells = monthGrid(view.month.year, view.month.month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('calendar-prev'),
                icon: const Icon(Icons.chevron_left),
                tooltip: previousTooltip,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: view.canGoPrevious ? () => notifier.moveMonth(-1) : null,
              ),
              Expanded(
                child: Text(
                  monthTitle(view.month.year, view.month.month),
                  key: const ValueKey('calendar-month-title'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const ValueKey('calendar-next'),
                icon: const Icon(Icons.chevron_right),
                tooltip: nextTooltip,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: view.canGoNext ? () => notifier.moveMonth(1) : null,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 4,
          child: firstLoad
              ? const LinearProgressIndicator(key: ValueKey('calendar-month-loading'))
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              for (final name in weekdayShortNames)
                Expanded(
                  child: Text(
                    name,
                    key: ValueKey('calendar-weekday-$name'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            key: const ValueKey('calendar-grid'),
            children: [
              for (var row = 0; row < cells.length ~/ 7; row++)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final cell in cells.skip(row * 7).take(7))
                      Expanded(
                        child: _DayCell(
                          cell: cell,
                          isToday: cell.day == today,
                          isSelected: cell.day == view.selectedDay,
                          counts: cell.inMonth ? counts[cell.day] : null,
                          skeleton: firstLoad && cell.inMonth,
                          onTap: isDayInBounds(cell.day)
                              ? () => notifier.selectDay(cell.day)
                              : null,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        if (monthValue.hasError)
          _MonthError(
            message: userMessage(monthValue.error!),
            onRetry: () => ref.invalidate(calendarMonthProvider(view.month)),
          ),
      ],
    );
  }
}

/// One day: number, today frame (border + bold, not color alone), selected
/// fill, faded when outside the month, and up to 3 count marks of different
/// shapes. The whole cell (at least 48x56) is the tap target.
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.cell,
    required this.isToday,
    required this.isSelected,
    required this.counts,
    required this.skeleton,
    required this.onTap,
  });

  final GridCell cell;
  final bool isToday;
  final bool isSelected;
  final CalendarDay? counts;
  final bool skeleton;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final id = formatDateForApi(cell.day);
    final Color numberColor;
    if (!cell.inMonth) {
      numberColor = scheme.onSurface.withValues(alpha: 0.38);
    } else if (isSelected) {
      numberColor = scheme.onPrimaryContainer;
    } else {
      numberColor = scheme.onSurface;
    }
    final c = counts;

    final Widget marks;
    if (c != null && CalendarMonthGrid.hasCounts(c)) {
      marks = Semantics(
        container: true,
        label: CalendarMonthGrid.countsLabel(c),
        child: ExcludeSemantics(
          child: Row(
            key: ValueKey('calendar-marks-$id'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (c.taskCount + c.dueCount > 0)
                Icon(
                  Icons.circle,
                  key: ValueKey('calendar-mark-task-$id'),
                  size: 8,
                  color: numberColor,
                ),
              if (c.routineCount > 0)
                Icon(
                  Icons.square,
                  key: ValueKey('calendar-mark-routine-$id'),
                  size: 8,
                  color: numberColor,
                ),
              if (c.scheduleCount > 0)
                Icon(
                  Icons.change_history,
                  key: ValueKey('calendar-mark-schedule-$id'),
                  size: 10,
                  color: numberColor,
                ),
            ],
          ),
        ),
      );
    } else if (skeleton) {
      marks = Container(
        key: ValueKey('calendar-skeleton-$id'),
        width: 20,
        height: 8,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
      );
    } else {
      marks = const SizedBox(height: 10);
    }

    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      enabled: onTap != null,
      label: CalendarMonthGrid.dayLabel(cell.day, isToday: isToday),
      child: InkWell(
        key: ValueKey('calendar-day-$id'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primaryContainer : null,
            border: isToday ? Border.all(color: scheme.primary, width: 2) : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Text(
                  '${cell.day.day}',
                  key: ValueKey('calendar-day-number-$id'),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: numberColor,
                    fontWeight: isToday ? FontWeight.w800 : FontWeight.w400,
                    decoration: isToday ? TextDecoration.underline : null,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(height: 10, child: Center(child: marks)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthError extends StatelessWidget {
  const _MonthError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('calendar-month-error'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
          TextButton.icon(
            key: const ValueKey('calendar-month-retry'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text(CalendarMonthGrid.retryText),
          ),
        ],
      ),
    );
  }
}
