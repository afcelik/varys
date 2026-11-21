import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/calendar/domain/calendar_grid.dart';
import 'package:varys/features/calendar/presentation/calendar_providers.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/presentation/providers/eisenhower_tasks_provider.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/presentation/routines_day_notifier.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';
import 'package:varys/features/schedule/presentation/schedule_new_args.dart';

/// Details of the selected day, in fixed order: Program (by start time),
/// Rutinler, Görevler (planned that day), Bitiş tarihi bu gün (due that day).
///
/// Each section has its own data source: its loading and error state (with
/// its own 'Tekrar dene') affect only that section. A loaded empty section is
/// hidden; when all four are loaded and empty, 'Bu gün için kayıt yok'.
/// Reuses the existing day providers and the unfiltered task list; no new
/// requests are defined here.
class CalendarDayList extends ConsumerWidget {
  const CalendarDayList({super.key});

  static const String scheduleTitle = 'Program';
  static const String routinesTitle = 'Rutinler';
  static const String tasksTitle = 'Görevler';
  static const String dueTitle = 'Bitiş tarihi bu gün';
  static const String emptyText = 'Bu gün için kayıt yok';
  static const String retryText = 'Tekrar dene';
  static const String addBlockTooltip = 'Bu güne blok ekle';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final day = ref.watch(calendarViewProvider.select((v) => v.selectedDay));
    final blocks = ref.watch(scheduleForDayProvider(day));
    final routines = ref.watch(routinesForDayProvider(day));
    final tasks = ref.watch(eisenhowerTasksProvider);
    final planned = tasks.whenData((all) => tasksForDay(all, day));
    final due = tasks.whenData((all) => dueTasksForDay(all, day));

    void retryTasks() {
      ref.invalidate(taskListNotifierProvider);
      ref.invalidate(eisenhowerTasksProvider);
    }

    final sections = <Widget?>[
      _section(
        id: 'schedule',
        title: scheduleTitle,
        value: blocks,
        onRetry: () => ref.invalidate(scheduleForDayProvider(day)),
        rows: (list) => [
          for (final b in list)
            _EntryRow(
              kind: 'schedule',
              id: b.id,
              icon: Icons.change_history,
              subtitle: formatTimeRange(b.startTime, b.endTime),
              title: b.title,
              onTap: () => context.push(AppRouter.scheduleEditPath, extra: b),
            ),
        ],
      ),
      _section(
        id: 'routines',
        title: routinesTitle,
        value: routines,
        onRetry: () => ref.invalidate(routinesForDayProvider(day)),
        rows: (list) => [
          for (final r in list)
            _EntryRow(
              kind: 'routine',
              id: r.id,
              icon: Icons.square_outlined,
              subtitle: recurrenceSummaryOf(
                r.recurrenceType,
                daysOfWeek: r.daysOfWeek,
                dayOfMonth: r.dayOfMonth,
                intervalDays: r.intervalDays,
                startDate: r.startDate,
              ),
              title: r.title,
              onTap: () => context.push(AppRouter.routinesEditPath, extra: _routineOf(r)),
            ),
        ],
      ),
      _section(
        id: 'tasks',
        title: tasksTitle,
        value: planned,
        onRetry: retryTasks,
        rows: (list) => [
          for (final t in list)
            _EntryRow(
              kind: 'task',
              id: t.id,
              icon: Icons.circle_outlined,
              title: t.title,
              onTap: () => context.push(AppRouter.tasksEditPath, extra: t),
            ),
        ],
      ),
      _section(
        id: 'due',
        title: dueTitle,
        value: due,
        onRetry: retryTasks,
        rows: (list) => [
          for (final t in list)
            _EntryRow(
              kind: 'due',
              id: t.id,
              icon: Icons.flag_outlined,
              title: t.title,
              onTap: () => context.push(AppRouter.tasksEditPath, extra: t),
            ),
        ],
      ),
    ];

    final allEmpty = [
      blocks,
      routines,
      planned,
      due,
    ].every((v) => v.hasValue && !v.hasError && (v.value! as List).isEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                formatDateForDisplay(day),
                key: const ValueKey('calendar-day-title'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            // A one-time block on the selected day; the form pops back here
            // and the day list and month counts refresh through the existing
            // schedule invalidation (calendarMonthSyncProvider).
            IconButton(
              key: const ValueKey('calendar-day-add-block'),
              tooltip: addBlockTooltip,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.add),
              onPressed: () => context.push(
                AppRouter.scheduleNewPath,
                extra: ScheduleNewArgs(day: day, once: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (allEmpty)
          Padding(
            key: const ValueKey('calendar-day-empty'),
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              emptyText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...sections.whereType<Widget>(),
      ],
    );
  }

  /// A section, or null when it has loaded and is empty.
  static Widget? _section<T>({
    required String id,
    required String title,
    required AsyncValue<List<T>> value,
    required VoidCallback onRetry,
    required List<Widget> Function(List<T> list) rows,
  }) {
    final Widget body;
    if (value.hasValue && !value.hasError) {
      final list = value.requireValue;
      if (list.isEmpty) return null;
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows(list));
    } else if (value.hasError) {
      body = _SectionError(id: id, message: userMessage(value.error!), onRetry: onRetry);
    } else {
      body = Padding(
        key: ValueKey('calendar-section-loading-$id'),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: const Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return _Section(id: id, title: title, child: body);
  }
}

/// The routine edit form takes a [Routine]; a day item carries all its fields.
Routine _routineOf(RoutineDayItem i) => Routine(
  id: i.id,
  title: i.title,
  description: i.description,
  recurrenceType: i.recurrenceType,
  daysOfWeek: i.daysOfWeek,
  dayOfMonth: i.dayOfMonth,
  intervalDays: i.intervalDays,
  startDate: i.startDate,
  createdAt: i.createdAt,
  updatedAt: i.updatedAt,
);

class _Section extends StatelessWidget {
  const _Section({required this.id, required this.title, required this.child});

  final String id;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: ValueKey('calendar-section-$id'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            key: ValueKey('calendar-section-title-$id'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// One record: optional muted line (time range / recurrence) and the title
/// (max 2 lines). The whole row, at least 48 high, opens the edit form.
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.kind,
    required this.id,
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final String kind;
  final int id;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final sub = subtitle;
    return InkWell(
      key: ValueKey('calendar-row-$kind-$id'),
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (sub != null)
                      Text(
                        sub,
                        key: ValueKey('calendar-row-subtitle-$kind-$id'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    Text(
                      title,
                      key: ValueKey('calendar-row-title-$kind-$id'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.id, required this.message, required this.onRetry});

  final String id;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: ValueKey('calendar-section-error-$id'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
        TextButton.icon(
          key: ValueKey('calendar-section-retry-$id'),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text(CalendarDayList.retryText),
        ),
      ],
    );
  }
}
