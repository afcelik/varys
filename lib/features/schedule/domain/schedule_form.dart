import 'package:flutter/foundation.dart';
import 'package:varys/core/text/turkish_text.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';

/// Pure helpers for schedule blocks: validation, the partial-update diff,
/// now/past/upcoming status, ordering, quick-add parsing and default times.
/// Recurrence validation and summaries are reused from the routine form
/// (`recurrence_form.dart`). No Flutter widgets, no I/O, no clock.

const String timeRangeInvalidMessage = 'Bitiş saati başlangıçtan sonra olmalı';
const String timeOutOfRangeMessage = 'Saat 00:00 ile 23:59 arasında olmalı';
const String quickAddFormatMessage = 'Biçim: [bugün] 08:30-09:00 başlık';

/// Optional quick-add prefix (compared Turkish-lowercased) for a one-time block.
const String quickAddTodayPrefix = 'bugün';
const String scheduleRecurrenceChangeNote =
    'Tekrar kuralını değiştirmek geçmiş günlerin programını da değiştirir.';

/// En dash used between the two times in "08:30–09:00".
const String timeRangeSeparator = '\u2013';

/// "08:30–09:00".
String formatTimeRange(ScheduleTime start, ScheduleTime end) =>
    '${start.hhmm}$timeRangeSeparator${end.hhmm}';

/// Minutes since midnight of [now] (its local wall clock, no conversion).
int minuteOfDay(DateTime now) => now.hour * 60 + now.minute;

/// Null when [end] is strictly after [start].
String? validateTimeRange(ScheduleTime start, ScheduleTime end) =>
    start < end ? null : timeRangeInvalidMessage;

/// True when title, description, time range and recurrence are all valid.
bool isScheduleFormValid({
  required String title,
  required String description,
  required ScheduleTime start,
  required ScheduleTime end,
  required RecurrenceFormState recurrence,
}) => isFormValid(title, description, recurrence) && validateTimeRange(start, end) == null;

/// Fields of a PATCH /schedule/{id} body. Unset fields are not sent, clear
/// sends an explicit null, set sends the value. There is deliberately no
/// start date: the backend rejects `start_date` in a PATCH.
@immutable
class ScheduleChanges {
  const ScheduleChanges({
    this.title = const PlanField.unset(),
    this.description = const PlanField.unset(),
    this.startTime = const PlanField.unset(),
    this.endTime = const PlanField.unset(),
    this.recurrenceType = const PlanField.unset(),
    this.daysOfWeek = const PlanField.unset(),
    this.dayOfMonth = const PlanField.unset(),
    this.intervalDays = const PlanField.unset(),
  });

  final PlanField<String> title;
  final PlanField<String> description;
  final PlanField<ScheduleTime> startTime;
  final PlanField<ScheduleTime> endTime;
  final PlanField<RecurrenceType> recurrenceType;
  final PlanField<List<int>> daysOfWeek;
  final PlanField<int> dayOfMonth;
  final PlanField<int> intervalDays;

  bool get isEmpty =>
      title.isUnset &&
      description.isUnset &&
      startTime.isUnset &&
      endTime.isUnset &&
      recurrenceType.isUnset &&
      daysOfWeek.isUnset &&
      dayOfMonth.isUnset &&
      intervalDays.isUnset;

  /// JSON-encodable body: times as 'HH:MM', the recurrence type as its wire
  /// string, weekdays sorted.
  Map<String, dynamic> toBody() {
    final body = <String, dynamic>{};
    title.writeTo(body, 'title');
    description.writeTo(body, 'description');
    _writeTime(body, 'start_time', startTime);
    _writeTime(body, 'end_time', endTime);
    switch (recurrenceType) {
      case PlanFieldUnset<RecurrenceType>():
        break;
      case PlanFieldSet<RecurrenceType>(:final value):
        body['recurrence_type'] = value.apiValue;
      case PlanFieldClear<RecurrenceType>():
        body['recurrence_type'] = null;
    }
    switch (daysOfWeek) {
      case PlanFieldSet<List<int>>(:final value):
        body['days_of_week'] = List<int>.of(value)..sort();
      default:
        daysOfWeek.writeTo(body, 'days_of_week');
    }
    dayOfMonth.writeTo(body, 'day_of_month');
    intervalDays.writeTo(body, 'interval_days');
    return body;
  }

  static void _writeTime(Map<String, dynamic> body, String key, PlanField<ScheduleTime> field) {
    switch (field) {
      case PlanFieldUnset<ScheduleTime>():
        break;
      case PlanFieldSet<ScheduleTime>(:final value):
        body[key] = value.hhmm;
      case PlanFieldClear<ScheduleTime>():
        body[key] = null;
    }
  }
}

PlanField<T> _setOrClear<T>(T? value) =>
    value == null ? PlanField<T>.clear() : PlanField<T>.set(value);

/// True when the form's recurrence rule differs from [original]'s.
bool scheduleRecurrenceDiffers(ScheduleBlock original, RecurrenceFormState recurrence) =>
    recurrenceRuleChanged(
      type: original.recurrenceType,
      daysOfWeek: original.daysOfWeek,
      dayOfMonth: original.dayOfMonth,
      intervalDays: original.intervalDays,
      form: recurrence,
    );

/// What changed between [original] and the form. Title/description are
/// compared trimmed; an empty description clears it. Times are sent only when
/// they differ. If the recurrence rule changed, the type and all three
/// recurrence fields are sent (unrelated ones as explicit null) because the
/// backend validates the merged state.
ScheduleChanges computeScheduleChanges(
  ScheduleBlock original, {
  required String title,
  required String description,
  required ScheduleTime startTime,
  required ScheduleTime endTime,
  required RecurrenceFormState recurrence,
}) {
  final t = title.trim();
  final d = description.trim();

  final titleField = t == original.title ? const PlanField<String>.unset() : PlanField.set(t);
  final descriptionField = d == (original.description ?? '').trim()
      ? const PlanField<String>.unset()
      : (d.isEmpty ? const PlanField<String>.clear() : PlanField.set(d));
  final startField = startTime == original.startTime
      ? const PlanField<ScheduleTime>.unset()
      : PlanField.set(startTime);
  final endField = endTime == original.endTime
      ? const PlanField<ScheduleTime>.unset()
      : PlanField.set(endTime);

  if (!scheduleRecurrenceDiffers(original, recurrence)) {
    return ScheduleChanges(
      title: titleField,
      description: descriptionField,
      startTime: startField,
      endTime: endField,
    );
  }
  return ScheduleChanges(
    title: titleField,
    description: descriptionField,
    startTime: startField,
    endTime: endField,
    recurrenceType: PlanField.set(recurrence.type),
    daysOfWeek: _setOrClear(recurrence.effectiveDays),
    dayOfMonth: _setOrClear(recurrence.effectiveDayOfMonth),
    intervalDays: _setOrClear(recurrence.effectiveIntervalDays),
  );
}

enum BlockStatus { past, current, upcoming }

/// Status of [block] at [minute] (minutes since midnight): current when
/// start <= minute < end (start included, end excluded).
BlockStatus blockStatusAt(ScheduleBlock block, int minute) {
  if (minute < block.startTime.minutes) return BlockStatus.upcoming;
  if (minute < block.endTime.minutes) return BlockStatus.current;
  return BlockStatus.past;
}

/// A new list ordered by start time, then id (the server's order).
List<ScheduleBlock> sortBlocks(Iterable<ScheduleBlock> blocks) => blocks.toList()
  ..sort((a, b) {
    final byStart = a.startTime.compareTo(b.startTime);
    return byStart != 0 ? byStart : a.id.compareTo(b.id);
  });

/// Result of [parseQuickAdd].
sealed class QuickAddResult {
  const QuickAddResult();
}

final class QuickAddOk extends QuickAddResult {
  const QuickAddOk({
    required this.start,
    required this.end,
    required this.title,
    this.oneTime = false,
  });

  final ScheduleTime start;
  final ScheduleTime end;
  final String title;

  /// True when the line started with 'bugün': a one-time block on that day
  /// instead of a daily one.
  final bool oneTime;
}

final class QuickAddError extends QuickAddResult {
  const QuickAddError(this.message);

  final String message;
}

// H:MM or HH:MM with ':' or '.', a hyphen or en dash with optional spaces,
// then the title. [0-9], not \d: only ASCII digits are times.
final RegExp _quickAdd = RegExp(
  r'^\s*([0-9]{1,2})[:.]([0-9]{2})\s*[-'
  '\u2013'
  r']\s*([0-9]{1,2})[:.]([0-9]{2})(?:\s+([\s\S]*))?$',
);

// The first word and the rest of the line.
final RegExp _firstWord = RegExp(r'^\s*(\S+)([\s\S]*)$');

/// Parses "08:30-09:00 kahvaltı" (also "8:30-9:00", "08.30-09.00",
/// "08:30–09:00" with an en dash, "08:30 - 09:00"). An optional leading
/// 'bugün' (any case, Turkish-aware) makes it a one-time block
/// ([QuickAddOk.oneTime]); no other prefix word is recognised. Errors are
/// Turkish messages; nothing is sent for them.
QuickAddResult parseQuickAdd(String input) {
  var line = input;
  var oneTime = false;
  final w = _firstWord.firstMatch(input);
  if (w != null && turkishLower(w.group(1)!) == quickAddTodayPrefix) {
    // 'bugün' alone leaves an empty rest, which the format check rejects.
    line = w.group(2)!;
    oneTime = true;
  }
  final m = _quickAdd.firstMatch(line);
  if (m == null) return const QuickAddError(quickAddFormatMessage);

  ScheduleTime? time(String h, String mm) {
    final hour = int.parse(h);
    final minute = int.parse(mm);
    if (hour > 23 || minute > 59) return null;
    return ScheduleTime.hm(hour, minute);
  }

  final start = time(m.group(1)!, m.group(2)!);
  final end = time(m.group(3)!, m.group(4)!);
  if (start == null || end == null) return const QuickAddError(timeOutOfRangeMessage);
  final rangeError = validateTimeRange(start, end);
  if (rangeError != null) return QuickAddError(rangeError);

  final title = (m.group(5) ?? '').trim();
  final titleError = validateTitle(title);
  if (titleError != null) return QuickAddError(titleError);
  return QuickAddOk(start: start, end: end, title: title, oneTime: oneTime);
}

/// Default times for a new block: the next full hour for one hour, at most
/// 22:00-23:00 (so the end never passes 23:59).
({ScheduleTime start, ScheduleTime end}) defaultTimesFor(DateTime now) {
  final hour = now.hour + 1 > 22 ? 22 : now.hour + 1;
  return (start: ScheduleTime.hm(hour, 0), end: ScheduleTime.hm(hour + 1, 0));
}
