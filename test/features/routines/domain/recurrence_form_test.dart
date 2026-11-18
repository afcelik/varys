import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';

Routine _routine({
  String title = 'Spor',
  String? description,
  RecurrenceType type = RecurrenceType.weekly,
  List<int>? days = const [0, 2],
  int? dayOfMonth,
  int? intervalDays,
}) =>
    Routine(
      id: 7,
      title: title,
      description: description,
      recurrenceType: type,
      daysOfWeek: days,
      dayOfMonth: dayOfMonth,
      intervalDays: intervalDays,
      startDate: DateTime(2026, 11, 2),
      createdAt: DateTime(2026, 11, 2, 10),
      updatedAt: DateTime(2026, 11, 2, 10),
    );

Map<String, dynamic> _body(
  Routine original, {
  String? title,
  String? description,
  RecurrenceFormState? recurrence,
}) =>
    computeChanges(
      original,
      title: title ?? original.title,
      description: description ?? original.description ?? '',
      recurrence: recurrence ?? RecurrenceFormState.fromRoutine(original),
    ).toBody();

void main() {
  group('computeChanges: nothing changed', () {
    test('identical form gives empty changes and an empty body', () {
      final r = _routine(description: 'Akşam');
      final changes = computeChanges(r,
          title: 'Spor', description: 'Akşam', recurrence: RecurrenceFormState.fromRoutine(r));
      expect(changes.isEmpty, isTrue);
      expect(changes.toBody(), isEmpty);
    });

    test('surrounding whitespace only is not a change', () {
      final r = _routine(description: 'Akşam');
      expect(_body(r, title: '  Spor ', description: ' Akşam  '), isEmpty);
    });

    test('same weekdays in another order is not a change', () {
      final r = _routine(days: [0, 2]);
      final form = RecurrenceFormState(type: RecurrenceType.weekly, days: {2, 0});
      expect(_body(r, recurrence: form), isEmpty);
    });

    test('values typed for another type do not count while the type is unchanged', () {
      final r = _routine(type: RecurrenceType.daily, days: null);
      final form = RecurrenceFormState(
          type: RecurrenceType.daily, days: {1}, dayOfMonth: 5, intervalDays: 9);
      expect(_body(r, recurrence: form), isEmpty);
    });
  });

  group('computeChanges: title and description', () {
    test('changed title is set (trimmed), nothing else sent', () {
      expect(_body(_routine(), title: '  Koşu  '), {'title': 'Koşu'});
    });

    test('changed description is set (trimmed)', () {
      expect(_body(_routine(description: 'a'), description: ' b '), {'description': 'b'});
    });

    test('emptied description is cleared with an explicit null', () {
      final body = _body(_routine(description: 'Akşam'), description: '   ');
      expect(body, {'description': null});
      expect(body.containsKey('description'), isTrue);
    });

    test('null description left empty is not a change', () {
      expect(_body(_routine(description: null), description: ''), isEmpty);
    });
  });

  group('computeChanges: recurrence (all four fields, unrelated ones null)', () {
    test('weekly days changed: type + days set, other two explicit null', () {
      final r = _routine(days: [0, 2]);
      final body = _body(r,
          recurrence: RecurrenceFormState(type: RecurrenceType.weekly, days: {4, 0}));
      expect(body, {
        'recurrence_type': 'weekly',
        'days_of_week': [0, 4],
        'day_of_month': null,
        'interval_days': null,
      });
    });

    test('weekly -> daily: days_of_week explicitly null', () {
      final body = _body(_routine(days: [0, 2]),
          recurrence: const RecurrenceFormState(type: RecurrenceType.daily, days: {0, 2}));
      expect(body, {
        'recurrence_type': 'daily',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': null,
      });
    });

    test('weekly -> monthly: day_of_month set, days_of_week null', () {
      final body = _body(_routine(days: [1]),
          recurrence: const RecurrenceFormState(
              type: RecurrenceType.monthly, days: {1}, dayOfMonth: 15));
      expect(body, {
        'recurrence_type': 'monthly',
        'days_of_week': null,
        'day_of_month': 15,
        'interval_days': null,
      });
    });

    test('monthly -> interval: interval_days set, day_of_month null', () {
      final r = _routine(type: RecurrenceType.monthly, days: null, dayOfMonth: 15);
      final body = _body(r,
          recurrence: const RecurrenceFormState(
              type: RecurrenceType.interval, dayOfMonth: 15, intervalDays: 3));
      expect(body, {
        'recurrence_type': 'interval',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': 3,
      });
    });

    test('interval -> weekly: days set, interval_days null', () {
      final r = _routine(type: RecurrenceType.interval, days: null, intervalDays: 3);
      final body = _body(r,
          recurrence: const RecurrenceFormState(
              type: RecurrenceType.weekly, days: {6}, intervalDays: 3));
      expect(body, {
        'recurrence_type': 'weekly',
        'days_of_week': [6],
        'day_of_month': null,
        'interval_days': null,
      });
    });

    test('same type, value changed (monthly 15 -> 31)', () {
      final r = _routine(type: RecurrenceType.monthly, days: null, dayOfMonth: 15);
      final body = _body(r,
          recurrence: const RecurrenceFormState(type: RecurrenceType.monthly, dayOfMonth: 31));
      expect(body['day_of_month'], 31);
      expect(body['recurrence_type'], 'monthly');
      expect(body.keys, hasLength(4));
    });

    test('title and recurrence together; description untouched is absent', () {
      final body = _body(_routine(description: 'x'),
          title: 'Yeni',
          recurrence: const RecurrenceFormState(type: RecurrenceType.daily));
      expect(body.keys.toSet(),
          {'title', 'recurrence_type', 'days_of_week', 'day_of_month', 'interval_days'});
      expect(body.containsKey('description'), isFalse);
    });

    test('body is JSON-encodable (no Dart enum inside)', () {
      final body = _body(_routine(),
          recurrence: const RecurrenceFormState(type: RecurrenceType.interval, intervalDays: 2));
      expect(() => jsonEncode(body), returnsNormally);
      expect(body['recurrence_type'], isA<String>());
    });

    test('recurrenceDiffers follows the rule, not title/description', () {
      final r = _routine(days: [0]);
      expect(recurrenceDiffers(r, RecurrenceFormState.fromRoutine(r)), isFalse);
      expect(
          recurrenceDiffers(
              r, const RecurrenceFormState(type: RecurrenceType.weekly, days: {0, 1})),
          isTrue);
    });
  });

  group('RoutineChanges.toBody', () {
    test('unset fields are absent; clear writes null; enum as wire string', () {
      const changes = RoutineChanges(
        title: PlanField.set('A'),
        recurrenceType: PlanField.set(RecurrenceType.monthly),
        daysOfWeek: PlanField.clear(),
      );
      expect(changes.toBody(), {
        'title': 'A',
        'recurrence_type': 'monthly',
        'days_of_week': null,
      });
    });

    test('every type maps to its backend value', () {
      expect(RecurrenceType.values.map((t) => t.apiValue),
          ['daily', 'weekly', 'monthly', 'interval']);
    });
  });

  group('validation', () {
    test('title: trimmed, 1..255 code points', () {
      expect(validateTitle(''), titleRequiredMessage);
      expect(validateTitle('   '), titleRequiredMessage);
      expect(validateTitle('a'), isNull);
      expect(validateTitle('a' * 255), isNull);
      expect(validateTitle('a' * 256), titleTooLongMessage);
      expect(validateTitle('  ${'a' * 255}  '), isNull, reason: 'trimmed before counting');
      // 255 emoji = 510 UTF-16 units but 255 code points, as the backend counts.
      expect(validateTitle('😀' * 255), isNull);
      expect(validateTitle('😀' * 256), titleTooLongMessage);
    });

    test('description: optional, at most 2000', () {
      expect(validateDescription(''), isNull);
      expect(validateDescription('a' * 2000), isNull);
      expect(validateDescription('a' * 2001), descriptionTooLongMessage);
    });

    test('daily is always valid', () {
      expect(validateRecurrence(const RecurrenceFormState(type: RecurrenceType.daily)), isNull);
    });

    test('weekly needs at least one day', () {
      expect(validateRecurrence(const RecurrenceFormState(type: RecurrenceType.weekly)),
          weekdaysRequiredMessage);
      expect(
          validateRecurrence(const RecurrenceFormState(type: RecurrenceType.weekly, days: {6})),
          isNull);
    });

    test('monthly: 1..31, missing is invalid', () {
      RecurrenceFormState m(int? d) =>
          RecurrenceFormState(type: RecurrenceType.monthly, dayOfMonth: d);
      expect(validateRecurrence(m(null)), dayOfMonthInvalidMessage);
      expect(validateRecurrence(m(0)), dayOfMonthInvalidMessage);
      expect(validateRecurrence(m(1)), isNull);
      expect(validateRecurrence(m(31)), isNull);
      expect(validateRecurrence(m(32)), dayOfMonthInvalidMessage);
    });

    test('interval: at least 1, missing is invalid', () {
      RecurrenceFormState i(int? n) =>
          RecurrenceFormState(type: RecurrenceType.interval, intervalDays: n);
      expect(validateRecurrence(i(null)), intervalInvalidMessage);
      expect(validateRecurrence(i(0)), intervalInvalidMessage);
      expect(validateRecurrence(i(1)), isNull);
      expect(validateRecurrence(i(9999)), isNull);
    });

    test('isFormValid combines all three', () {
      const ok = RecurrenceFormState(type: RecurrenceType.daily);
      expect(isFormValid('Spor', '', ok), isTrue);
      expect(isFormValid(' ', '', ok), isFalse);
      expect(isFormValid('Spor', 'a' * 2001, ok), isFalse);
      expect(isFormValid('Spor', '', const RecurrenceFormState(type: RecurrenceType.weekly)),
          isFalse);
    });
  });

  group('RecurrenceFormState', () {
    test('toggleDay adds and removes; effectiveDays sorted only when weekly', () {
      var s = const RecurrenceFormState(type: RecurrenceType.weekly);
      s = s.toggleDay(4).toggleDay(1).toggleDay(6).toggleDay(4);
      expect(s.effectiveDays, [1, 6]);
      expect(s.copyWith(type: RecurrenceType.daily).effectiveDays, isNull);
    });

    test('copyWith clears and sets numeric fields explicitly', () {
      const s = RecurrenceFormState(type: RecurrenceType.monthly, dayOfMonth: 5);
      expect(s.copyWith(dayOfMonth: const PlanField.clear()).dayOfMonth, isNull);
      expect(s.copyWith(dayOfMonth: const PlanField.set(9)).dayOfMonth, 9);
      expect(s.copyWith().dayOfMonth, 5);
    });
  });

  group('summaries', () {
    test('weekday short names, Monday=0 ... Sunday=6', () {
      expect(weekdayShortNames, ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz']);
    });

    test('one summary per type', () {
      expect(recurrenceSummary(_routine(type: RecurrenceType.daily, days: null)), 'Her gün');
      expect(recurrenceSummary(_routine(days: [2, 0])), 'Pzt, Çar');
      expect(recurrenceSummary(_routine(days: [0, 1, 2, 3, 4, 5, 6])),
          'Pzt, Sal, Çar, Per, Cum, Cmt, Paz');
      expect(
          recurrenceSummary(
              _routine(type: RecurrenceType.monthly, days: null, dayOfMonth: 15)),
          "Ayın 15'i");
      expect(
          recurrenceSummary(
              _routine(type: RecurrenceType.interval, days: null, intervalDays: 3)),
          'Her 3 günde bir');
    });

    test('monthDayLabel for every day 1..31 (independent expected table)', () {
      const expected = {
        1: "1'i", 2: "2'si", 3: "3'ü", 4: "4'ü", 5: "5'i", 6: "6'sı", 7: "7'si",
        8: "8'i", 9: "9'u", 10: "10'u", 11: "11'i", 12: "12'si", 13: "13'ü",
        14: "14'ü", 15: "15'i", 16: "16'sı", 17: "17'si", 18: "18'i", 19: "19'u",
        20: "20'si", 21: "21'i", 22: "22'si", 23: "23'ü", 24: "24'ü", 25: "25'i",
        26: "26'sı", 27: "27'si", 28: "28'i", 29: "29'u", 30: "30'u", 31: "31'i",
      };
      expect(expected.keys, List.generate(31, (i) => i + 1));
      for (final entry in expected.entries) {
        expect(monthDayLabel(entry.key), 'Ayın ${entry.value}', reason: 'day ${entry.key}');
      }
    });

    test('month end note text', () {
      expect(monthEndNote, 'Ay kısaysa ayın son günü');
    });
  });
}
