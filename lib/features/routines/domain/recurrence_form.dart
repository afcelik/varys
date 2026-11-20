import 'package:flutter/foundation.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/routines/domain/routine.dart';

/// Pure helpers for the routine form: recurrence state, validation, the
/// partial-update diff and Turkish summaries. No Flutter widgets, no I/O.

/// Backend wire value of a [RecurrenceType] (same as its `@JsonValue`).
extension RecurrenceTypeApi on RecurrenceType {
  String get apiValue => switch (this) {
        RecurrenceType.daily => 'daily',
        RecurrenceType.weekly => 'weekly',
        RecurrenceType.monthly => 'monthly',
        RecurrenceType.interval => 'interval',
      };
}

/// Monday=0 ... Sunday=6 (same as the backend).
const List<String> weekdayShortNames = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

const String monthEndNote = 'Ay kısaysa ayın son günü';
const String recurrenceChangeNote = 'Tekrar kuralını değiştirmek geçmiş serilerini yeniden hesaplar.';

const int titleMaxLength = 255;
const int descriptionMaxLength = 2000;

const String titleRequiredMessage = 'Başlık gerekli';
const String titleTooLongMessage = 'Başlık en fazla 255 karakter olabilir';
const String descriptionTooLongMessage = 'Açıklama en fazla 2000 karakter olabilir';
const String weekdaysRequiredMessage = 'En az bir gün seçin';
const String dayOfMonthInvalidMessage = 'Ayın günü 1 ile 31 arasında olmalı';
const String intervalInvalidMessage = 'Aralık en az 1 gün olmalı';

/// Recurrence part of the form. Values typed for other types are kept (so
/// switching back restores them) but only the fields of [type] are effective.
@immutable
class RecurrenceFormState {
  const RecurrenceFormState({
    required this.type,
    this.days = const <int>{},
    this.dayOfMonth,
    this.intervalDays,
  });

  factory RecurrenceFormState.fromRoutine(Routine routine) => RecurrenceFormState.fromFields(
        type: routine.recurrenceType,
        daysOfWeek: routine.daysOfWeek,
        dayOfMonth: routine.dayOfMonth,
        intervalDays: routine.intervalDays,
      );

  /// From stored recurrence fields (any model with the routine recurrence shape).
  factory RecurrenceFormState.fromFields({
    required RecurrenceType type,
    List<int>? daysOfWeek,
    int? dayOfMonth,
    int? intervalDays,
  }) =>
      RecurrenceFormState(
        type: type,
        days: {...?daysOfWeek},
        dayOfMonth: dayOfMonth,
        intervalDays: intervalDays,
      );

  final RecurrenceType type;
  final Set<int> days;
  final int? dayOfMonth;
  final int? intervalDays;

  /// Sorted weekdays when weekly, otherwise null.
  List<int>? get effectiveDays =>
      type == RecurrenceType.weekly ? (days.toList()..sort()) : null;
  int? get effectiveDayOfMonth => type == RecurrenceType.monthly ? dayOfMonth : null;
  int? get effectiveIntervalDays => type == RecurrenceType.interval ? intervalDays : null;

  RecurrenceFormState copyWith({
    RecurrenceType? type,
    Set<int>? days,
    PlanField<int> dayOfMonth = const PlanField.unset(),
    PlanField<int> intervalDays = const PlanField.unset(),
  }) {
    int? pick(PlanField<int> field, int? current) => switch (field) {
          PlanFieldUnset<int>() => current,
          PlanFieldSet<int>(:final value) => value,
          PlanFieldClear<int>() => null,
        };
    return RecurrenceFormState(
      type: type ?? this.type,
      days: days ?? this.days,
      dayOfMonth: pick(dayOfMonth, this.dayOfMonth),
      intervalDays: pick(intervalDays, this.intervalDays),
    );
  }

  /// Toggles [weekday] (0..6) in the selected days.
  RecurrenceFormState toggleDay(int weekday) {
    final next = {...days};
    if (!next.remove(weekday)) next.add(weekday);
    return copyWith(days: next);
  }
}

/// Length in Unicode code points, as the backend (Python) counts it.
int _length(String s) => s.runes.length;

String? validateTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) return titleRequiredMessage;
  if (_length(t) > titleMaxLength) return titleTooLongMessage;
  return null;
}

String? validateDescription(String description) =>
    _length(description.trim()) > descriptionMaxLength ? descriptionTooLongMessage : null;

String? validateRecurrence(RecurrenceFormState r) {
  switch (r.type) {
    case RecurrenceType.daily:
      return null;
    case RecurrenceType.weekly:
      return r.days.isEmpty ? weekdaysRequiredMessage : null;
    case RecurrenceType.monthly:
      final d = r.dayOfMonth;
      return d == null || d < 1 || d > 31 ? dayOfMonthInvalidMessage : null;
    case RecurrenceType.interval:
      final i = r.intervalDays;
      return i == null || i < 1 ? intervalInvalidMessage : null;
  }
}

/// True when title, description and recurrence are all valid.
bool isFormValid(String title, String description, RecurrenceFormState r) =>
    validateTitle(title) == null &&
    validateDescription(description) == null &&
    validateRecurrence(r) == null;

/// Fields of a PATCH /routines/{id} body. Unset fields are not sent, clear
/// sends an explicit null (the backend clears it), set sends the value.
@immutable
class RoutineChanges {
  const RoutineChanges({
    this.title = const PlanField.unset(),
    this.description = const PlanField.unset(),
    this.recurrenceType = const PlanField.unset(),
    this.daysOfWeek = const PlanField.unset(),
    this.dayOfMonth = const PlanField.unset(),
    this.intervalDays = const PlanField.unset(),
  });

  final PlanField<String> title;
  final PlanField<String> description;
  final PlanField<RecurrenceType> recurrenceType;
  final PlanField<List<int>> daysOfWeek;
  final PlanField<int> dayOfMonth;
  final PlanField<int> intervalDays;

  bool get isEmpty =>
      title.isUnset &&
      description.isUnset &&
      recurrenceType.isUnset &&
      daysOfWeek.isUnset &&
      dayOfMonth.isUnset &&
      intervalDays.isUnset;

  /// JSON-encodable body: the recurrence type is sent as its wire string,
  /// never as the Dart enum.
  Map<String, dynamic> toBody() {
    final body = <String, dynamic>{};
    title.writeTo(body, 'title');
    description.writeTo(body, 'description');
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
}

PlanField<T> _setOrClear<T>(T? value) =>
    value == null ? PlanField<T>.clear() : PlanField<T>.set(value);

/// True when the effective rule of [form] differs from the stored fields.
bool recurrenceRuleChanged({
  required RecurrenceType type,
  List<int>? daysOfWeek,
  int? dayOfMonth,
  int? intervalDays,
  required RecurrenceFormState form,
}) {
  final storedDays = daysOfWeek == null ? null : (List<int>.of(daysOfWeek)..sort());
  return form.type != type ||
      !listEquals(form.effectiveDays, storedDays) ||
      form.effectiveDayOfMonth != dayOfMonth ||
      form.effectiveIntervalDays != intervalDays;
}

/// What changed between [original] and the form. Title/description are
/// compared trimmed; an empty description clears it. If the recurrence rule
/// changed, the type and all three recurrence fields are sent (unrelated
/// ones as explicit null) because the backend validates the merged state.
RoutineChanges computeChanges(
  Routine original, {
  required String title,
  required String description,
  required RecurrenceFormState recurrence,
}) {
  final t = title.trim();
  final d = description.trim();

  final titleField = t == original.title ? const PlanField<String>.unset() : PlanField.set(t);
  final descriptionField = d == (original.description ?? '').trim()
      ? const PlanField<String>.unset()
      : (d.isEmpty ? const PlanField<String>.clear() : PlanField.set(d));

  final recurrenceChanged = recurrenceRuleChanged(
    type: original.recurrenceType,
    daysOfWeek: original.daysOfWeek,
    dayOfMonth: original.dayOfMonth,
    intervalDays: original.intervalDays,
    form: recurrence,
  );

  if (!recurrenceChanged) {
    return RoutineChanges(title: titleField, description: descriptionField);
  }
  return RoutineChanges(
    title: titleField,
    description: descriptionField,
    recurrenceType: PlanField.set(recurrence.type),
    daysOfWeek: _setOrClear(recurrence.effectiveDays),
    dayOfMonth: _setOrClear(recurrence.effectiveDayOfMonth),
    intervalDays: _setOrClear(recurrence.effectiveIntervalDays),
  );
}

/// True when the form's recurrence rule differs from [original]'s.
bool recurrenceDiffers(Routine original, RecurrenceFormState recurrence) =>
    !computeChanges(original,
            title: original.title,
            description: original.description ?? '',
            recurrence: recurrence)
        .recurrenceType
        .isUnset;

/// Turkish possessive suffix for a day of month (1..31): 1 → "i", 6 → "sı",
/// 20 → "si". Follows the last spoken word (on, yirmi, otuz, bir, iki ...).
String monthDaySuffix(int day) {
  final ones = day % 10;
  if (ones == 0) return day == 20 ? 'si' : 'u'; // yirmi / on, otuz
  return const ['', 'i', 'si', 'ü', 'ü', 'i', 'sı', 'si', 'i', 'u'][ones];
}

/// "Ayın 15'i".
String monthDayLabel(int day) => "Ayın $day'${monthDaySuffix(day)}";

/// Short Turkish summary of a routine's recurrence for the list.
String recurrenceSummary(Routine routine) => recurrenceSummaryOf(
      routine.recurrenceType,
      daysOfWeek: routine.daysOfWeek,
      dayOfMonth: routine.dayOfMonth,
      intervalDays: routine.intervalDays,
    );

/// Short Turkish summary of stored recurrence fields ("Her gün", "Pzt, Çar",
/// "Ayın 15'i", "Her 3 günde bir").
String recurrenceSummaryOf(
  RecurrenceType type, {
  List<int>? daysOfWeek,
  int? dayOfMonth,
  int? intervalDays,
}) {
  switch (type) {
    case RecurrenceType.daily:
      return 'Her gün';
    case RecurrenceType.weekly:
      final days = [...?daysOfWeek]..sort();
      final names = [
        for (final d in days)
          if (d >= 0 && d < 7) weekdayShortNames[d],
      ];
      return names.isEmpty ? 'Haftalık' : names.join(', ');
    case RecurrenceType.monthly:
      final d = dayOfMonth;
      return d == null ? 'Aylık' : monthDayLabel(d);
    case RecurrenceType.interval:
      final i = intervalDays;
      return i == null ? 'Aralıklı' : 'Her $i günde bir';
  }
}
