import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';

/// The one-time ('once') recurrence type in the pure routine helpers:
/// validation, the PATCH diff (explicit nulls on transitions) and summaries.

Routine _routine({
  RecurrenceType type = RecurrenceType.weekly,
  List<int>? days,
  int? dayOfMonth,
  int? intervalDays,
  DateTime? startDate,
}) => Routine(
  id: 7,
  title: 'Vergi',
  recurrenceType: type,
  daysOfWeek: days,
  dayOfMonth: dayOfMonth,
  intervalDays: intervalDays,
  startDate: startDate ?? DateTime(2026, 11, 25),
  createdAt: DateTime(2026, 11, 2, 10),
  updatedAt: DateTime(2026, 11, 2, 10),
);

Map<String, dynamic> _body(Routine original, RecurrenceFormState recurrence, {String? title}) {
  final body = computeChanges(
    original,
    title: title ?? original.title,
    description: original.description ?? '',
    recurrence: recurrence,
  ).toBody();
  // Must survive real JSON encoding exactly as dio would send it.
  return jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
}

const _onceForm = RecurrenceFormState(type: RecurrenceType.once);

void main() {
  group('wire value', () {
    test("once is sent as 'once'", () {
      expect(RecurrenceType.once.apiValue, 'once');
    });
  });

  group('validateRecurrence(once)', () {
    test('valid with no recurrence fields', () {
      expect(validateRecurrence(_onceForm), isNull);
      expect(isFormValid('Vergi', '', _onceForm), isTrue);
    });

    test('values typed earlier for other types are not required or checked', () {
      // Invalid leftovers for weekly/monthly/interval would fail those types.
      const leftovers = RecurrenceFormState(
        type: RecurrenceType.once,
        dayOfMonth: 99,
        intervalDays: 0,
      );
      expect(validateRecurrence(leftovers), isNull);
      expect(
        validateRecurrence(leftovers.copyWith(type: RecurrenceType.monthly)),
        dayOfMonthInvalidMessage,
      );
      expect(
        validateRecurrence(leftovers.copyWith(type: RecurrenceType.interval)),
        intervalInvalidMessage,
      );
    });

    test('no recurrence field is effective for once (all null)', () {
      final form = const RecurrenceFormState(
        type: RecurrenceType.once,
        days: {1, 3},
        dayOfMonth: 15,
        intervalDays: 3,
      );
      expect(form.effectiveDays, isNull);
      expect(form.effectiveDayOfMonth, isNull);
      expect(form.effectiveIntervalDays, isNull);
    });
  });

  group('computeChanges: transitions to and from once', () {
    const allNullToOnce = {
      'recurrence_type': 'once',
      'days_of_week': null,
      'day_of_month': null,
      'interval_days': null,
    };

    test('weekly -> once: type set, the three fields explicit null', () {
      final r = _routine(days: [0, 2]);
      final body = _body(r, RecurrenceFormState.fromRoutine(r).copyWith(type: RecurrenceType.once));
      expect(body, allNullToOnce);
      for (final key in ['days_of_week', 'day_of_month', 'interval_days']) {
        expect(body.containsKey(key), isTrue, reason: '$key must be an explicit null');
      }
    });

    test('monthly -> once and interval -> once: same explicit nulls', () {
      final monthly = _routine(type: RecurrenceType.monthly, dayOfMonth: 15);
      expect(
        _body(
          monthly,
          RecurrenceFormState.fromRoutine(monthly).copyWith(type: RecurrenceType.once),
        ),
        allNullToOnce,
      );
      final interval = _routine(type: RecurrenceType.interval, intervalDays: 3);
      expect(
        _body(
          interval,
          RecurrenceFormState.fromRoutine(interval).copyWith(type: RecurrenceType.once),
        ),
        allNullToOnce,
      );
    });

    test('daily -> once: type set, three explicit nulls', () {
      expect(_body(_routine(type: RecurrenceType.daily), _onceForm), allNullToOnce);
    });

    test('once -> weekly / monthly / interval / daily: own field set, the rest null', () {
      final once = _routine(type: RecurrenceType.once);
      expect(_body(once, const RecurrenceFormState(type: RecurrenceType.weekly, days: {4, 1})), {
        'recurrence_type': 'weekly',
        'days_of_week': [1, 4],
        'day_of_month': null,
        'interval_days': null,
      });
      expect(_body(once, const RecurrenceFormState(type: RecurrenceType.monthly, dayOfMonth: 31)), {
        'recurrence_type': 'monthly',
        'days_of_week': null,
        'day_of_month': 31,
        'interval_days': null,
      });
      expect(
        _body(once, const RecurrenceFormState(type: RecurrenceType.interval, intervalDays: 2)),
        {
          'recurrence_type': 'interval',
          'days_of_week': null,
          'day_of_month': null,
          'interval_days': 2,
        },
      );
      expect(_body(once, const RecurrenceFormState(type: RecurrenceType.daily)), {
        'recurrence_type': 'daily',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': null,
      });
    });

    test('once unchanged: no recurrence key is sent (title change only)', () {
      final once = _routine(type: RecurrenceType.once);
      expect(_body(once, _onceForm), isEmpty);
      final body = _body(once, _onceForm, title: 'Vergi beyannamesi');
      expect(body, {'title': 'Vergi beyannamesi'});
      for (final key in ['recurrence_type', 'days_of_week', 'day_of_month', 'interval_days']) {
        expect(body.containsKey(key), isFalse, reason: key);
      }
    });

    test('stale values left in the form do not make an unchanged once a change', () {
      final once = _routine(type: RecurrenceType.once);
      const stale = RecurrenceFormState(type: RecurrenceType.once, days: {2}, dayOfMonth: 5);
      expect(_body(once, stale), isEmpty);
      expect(recurrenceDiffers(once, stale), isFalse);
      expect(
        recurrenceDiffers(once, const RecurrenceFormState(type: RecurrenceType.daily)),
        isTrue,
      );
    });

    test('the typed diff marks the three fields as clear, not unset', () {
      final r = _routine(type: RecurrenceType.monthly, dayOfMonth: 15);
      final changes = computeChanges(r, title: r.title, description: '', recurrence: _onceForm);
      expect(changes.recurrenceType, const PlanField<RecurrenceType>.set(RecurrenceType.once));
      expect(changes.daysOfWeek, isA<PlanFieldClear<List<int>>>());
      expect(changes.dayOfMonth, isA<PlanFieldClear<int>>());
      expect(changes.intervalDays, isA<PlanFieldClear<int>>());
    });
  });

  group('summaries', () {
    test("once: 'Tek sefer, 25 Kasım' from the routine's start date", () {
      expect(recurrenceSummary(_routine(type: RecurrenceType.once)), 'Tek sefer, 25 Kasım');
      expect(
        recurrenceSummaryOf(RecurrenceType.once, startDate: DateTime(2026, 11, 25)),
        'Tek sefer, 25 Kasım',
      );
    });

    test("once without a start date: 'Tek sefer'", () {
      expect(recurrenceSummaryOf(RecurrenceType.once), 'Tek sefer');
      expect(oneTimeLabel, 'Tek sefer');
    });

    test('every month name (independent expected table), first and last day', () {
      const expected = [
        '1 Ocak',
        '1 Şubat',
        '1 Mart',
        '1 Nisan',
        '1 Mayıs',
        '1 Haziran',
        '1 Temmuz',
        '1 Ağustos',
        '1 Eylül',
        '1 Ekim',
        '1 Kasım',
        '1 Aralık',
      ];
      for (var m = 1; m <= 12; m++) {
        expect(dayMonthLabel(DateTime(2026, m)), expected[m - 1], reason: 'month $m');
      }
      expect(dayMonthLabel(DateTime(2026, 12, 31)), '31 Aralık');
      expect(dayMonthLabel(DateTime(2028, 2, 29)), '29 Şubat');
      expect(
        recurrenceSummaryOf(RecurrenceType.once, startDate: DateTime(2027, 1, 9)),
        'Tek sefer, 9 Ocak',
      );
    });

    test("trMonthNames equals intl's Turkish MMMM for all 12 months", () async {
      await initializeDateFormatting('tr', null);
      final intl = [
        for (var m = 1; m <= 12; m++) DateFormat('MMMM', 'tr').format(DateTime(2026, m)),
      ];
      expect(trMonthNames, intl);
      expect(trMonthNames, hasLength(12));
    });

    test('the start date changes nothing for the other types', () {
      final start = DateTime(2026, 11, 25);
      expect(recurrenceSummaryOf(RecurrenceType.daily, startDate: start), 'Her gün');
      expect(
        recurrenceSummaryOf(RecurrenceType.weekly, daysOfWeek: [2, 0], startDate: start),
        'Pzt, Çar',
      );
      expect(
        recurrenceSummaryOf(RecurrenceType.monthly, dayOfMonth: 15, startDate: start),
        "Ayın 15'i",
      );
      expect(
        recurrenceSummaryOf(RecurrenceType.interval, intervalDays: 3, startDate: start),
        'Her 3 günde bir',
      );
      expect(recurrenceSummary(_routine(days: [0, 2])), 'Pzt, Çar');
    });
  });
}
