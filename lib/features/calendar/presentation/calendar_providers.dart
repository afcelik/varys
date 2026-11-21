import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/features/calendar/data/calendar_repository_impl.dart';
import 'package:varys/features/calendar/domain/calendar_grid.dart';
import 'package:varys/features/calendar/domain/calendar_month.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/providers/eisenhower_tasks_provider.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/routines/presentation/routines_day_notifier.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';

/// Per-day counts of one month (the family argument), `GET /calendar/month`.
///
/// A different month is a different family member, so a month change makes
/// exactly one new request and an older month's answer can never be written
/// into the shown month. Invalidating a member keeps its previous value while
/// the new request runs (Riverpod's refresh); the answer of a superseded
/// build is ignored by Riverpod.
class CalendarMonthNotifier extends AutoDisposeFamilyAsyncNotifier<CalendarMonth, YearMonth> {
  @override
  Future<CalendarMonth> build(YearMonth arg) async {
    final repository = await ref.watch(calendarRepositoryProvider.future);
    final result = await repository.getMonth(arg.year, arg.month);
    return result.fold((failure) => throw failure, (month) => month);
  }
}

/// Month counts by (year, month).
final calendarMonthProvider = AsyncNotifierProvider.autoDispose
    .family<CalendarMonthNotifier, CalendarMonth, YearMonth>(CalendarMonthNotifier.new);

/// What the /calendar page shows: the visible month and the selected day.
@immutable
class CalendarView {
  const CalendarView({
    required this.month,
    required this.selectedDay,
    this.dayPicked = false,
    this.monthChanged = false,
  });

  /// The month drawn in the grid.
  final YearMonth month;

  /// The day whose details are listed (local midnight).
  final DateTime selectedDay;

  /// The user chose [selectedDay]; otherwise it follows today.
  final bool dayPicked;

  /// The user moved to another month; otherwise [month] follows today.
  final bool monthChanged;

  bool get canGoPrevious => addMonths(month.year, month.month, -1) != null;
  bool get canGoNext => addMonths(month.year, month.month, 1) != null;

  CalendarView copyWith({
    YearMonth? month,
    DateTime? selectedDay,
    bool? dayPicked,
    bool? monthChanged,
  }) => CalendarView(
    month: month ?? this.month,
    selectedDay: selectedDay ?? this.selectedDay,
    dayPicked: dayPicked ?? this.dayPicked,
    monthChanged: monthChanged ?? this.monthChanged,
  );

  @override
  bool operator ==(Object other) =>
      other is CalendarView &&
      other.month == month &&
      other.selectedDay == selectedDay &&
      other.dayPicked == dayPicked &&
      other.monthChanged == monthChanged;

  @override
  int get hashCode => Object.hash(month, selectedDay, dayPicked, monthChanged);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Page state of /calendar. Starts on today's month and day; reset when the
/// page closes (autoDispose). When today changes (midnight, resume), a day
/// the user never picked follows today, and so does a month the user never
/// changed.
class CalendarViewNotifier extends AutoDisposeNotifier<CalendarView> {
  @override
  CalendarView build() {
    ref.listen<DateTime>(todayProvider, (_, today) => _followToday(_dateOnly(today)));
    final today = _dateOnly(ref.read(todayProvider));
    return CalendarView(month: (year: today.year, month: today.month), selectedDay: today);
  }

  void _followToday(DateTime today) {
    var next = state;
    if (!next.dayPicked) next = next.copyWith(selectedDay: today);
    if (!next.monthChanged) next = next.copyWith(month: (year: today.year, month: today.month));
    state = next;
  }

  /// Selects [day]. A day of another month (a faded cell) also shows that
  /// month. Days outside 2000-01-01 .. 2100-12-31 are ignored.
  void selectDay(DateTime day) {
    if (!isDayInBounds(day)) return;
    final d = _dateOnly(day);
    final sameMonth = d.year == state.month.year && d.month == state.month.month;
    state = state.copyWith(
      selectedDay: d,
      dayPicked: true,
      month: sameMonth ? null : (year: d.year, month: d.month),
      monthChanged: sameMonth ? null : true,
    );
  }

  /// Shows the month [delta] months away; the selected day stays. Does
  /// nothing past the bounds.
  void moveMonth(int delta) {
    final target = addMonths(state.month.year, state.month.month, delta);
    if (target == null) return;
    state = state.copyWith(month: target, monthChanged: true);
  }

  /// Back to today's month and day; both follow today again.
  void goToToday() {
    final today = _dateOnly(ref.read(todayProvider));
    state = CalendarView(month: (year: today.year, month: today.month), selectedDay: today);
  }
}

final calendarViewProvider = NotifierProvider.autoDispose<CalendarViewNotifier, CalendarView>(
  CalendarViewNotifier.new,
);

/// The visible month's counts (follows [calendarViewProvider]).
final calendarVisibleMonthProvider = Provider.autoDispose<AsyncValue<CalendarMonth>>((ref) {
  return ref.watch(calendarMonthProvider(ref.watch(calendarViewProvider.select((v) => v.month))));
});

/// The part of the task list that the month counts depend on: for each open
/// (not done, not deleted) task, its planned and due day (date part only).
/// Titles, flags, projects and list order do not matter.
@immutable
class CalendarTaskFingerprint {
  CalendarTaskFingerprint.of(Iterable<Task> tasks)
    : _days = {
        for (final t in tasks)
          if (t.status != TaskStatus.done && t.deletedAt == null)
            t.id: (_dayOf(t.plannedDate), _dayOf(t.dueDate)),
      };

  final Map<int, (DateTime?, DateTime?)> _days;

  static DateTime? _dayOf(DateTime? d) => d == null ? null : _dateOnly(d);

  @override
  bool operator ==(Object other) =>
      other is CalendarTaskFingerprint && mapEquals(other._days, _days);

  @override
  int get hashCode =>
      Object.hashAllUnordered(_days.entries.map((e) => Object.hash(e.key, e.value)));
}

/// Fingerprint of the unfiltered task list ([eisenhowerTasksProvider]);
/// null until the list has loaded once.
final calendarTaskFingerprintProvider = Provider.autoDispose<CalendarTaskFingerprint?>((ref) {
  final tasks = ref.watch(eisenhowerTasksProvider).valueOrNull;
  return tasks == null ? null : CalendarTaskFingerprint.of(tasks);
});

/// Watched by the /calendar page: refreshes the visible month once after a
/// change elsewhere, without touching the existing mutation code.
///
/// - Tasks: the counts-relevant [CalendarTaskFingerprint] changed (create,
///   date change, done/undone, delete). A silent re-fetch with the same data,
///   a title edit or a Planning filter change keeps the fingerprint: nothing.
/// - Routines / schedule blocks: their list notifiers invalidate the whole
///   day family after create/update/delete. The selected day's member going
///   from a settled value to loading is that signal. Completion toggles and
///   silent refreshes write data directly (no loading): nothing.
/// - Projects: no count depends on them (a deleted project only unlinks its
///   tasks): nothing.
///
/// No loop: the month provider never invalidates any of these sources.
final calendarMonthSyncProvider = Provider.autoDispose<void>((ref) {
  final view = ref.watch(calendarViewProvider.select((v) => (month: v.month, day: v.selectedDay)));
  void refreshMonth() => ref.invalidate(calendarMonthProvider(view.month));

  ref.listen<CalendarTaskFingerprint?>(calendarTaskFingerprintProvider, (previous, next) {
    if (previous != null && next != null && previous != next) refreshMonth();
  });

  void onDayList(AsyncValue<Object?>? previous, AsyncValue<Object?> next) {
    final wasSettled =
        previous != null && previous.hasValue && !previous.hasError && !previous.isLoading;
    if (wasSettled && next.isLoading) refreshMonth();
  }

  ref.listen(routinesForDayProvider(view.day), onDayList);
  ref.listen(scheduleForDayProvider(view.day), onDayList);
});
