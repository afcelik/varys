import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';

import '../../calendar/fake_calendar_repository.dart';
import '../fake_schedule_repository.dart';

/// The one-time ('once') type in the pure schedule helpers: the PATCH diff
/// (explicit nulls on transitions, never a start_date) and the quick-add
/// 'bugün' prefix. Blocks come from real backend JSON.

dynamic _read(String name) => jsonDecode(File('test/fixtures/$name').readAsStringSync());

ScheduleTime _t(String s) => ScheduleTime.parse(s);

void main() {
  late ScheduleBlock monthly; // schedule_list_with_once.json id 3, day 15
  late ScheduleBlock once; // schedule_list_with_once.json id 2, 2026-11-25
  late ScheduleBlock weekly; // schedule_list.json id 2, Pzt/Çar/Cum
  late ScheduleBlock interval; // schedule_list.json, the interval block

  setUpAll(() {
    final withOnce = (_read('schedule_list_with_once.json') as List)
        .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
        .toList();
    monthly = withOnce.firstWhere((b) => b.id == 3);
    once = withOnce.firstWhere((b) => b.id == 2);
    final old = (_read('schedule_list.json') as List)
        .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
        .toList();
    weekly = old.firstWhere((b) => b.id == 2);
    interval = old.firstWhere((b) => b.recurrenceType == RecurrenceType.interval);
  });

  RecurrenceFormState formOf(ScheduleBlock b) => RecurrenceFormState.fromFields(
    type: b.recurrenceType,
    daysOfWeek: b.daysOfWeek,
    dayOfMonth: b.dayOfMonth,
    intervalDays: b.intervalDays,
  );

  Map<String, dynamic> body(
    ScheduleBlock original,
    RecurrenceFormState recurrence, {
    String? title,
    ScheduleTime? start,
    ScheduleTime? end,
  }) {
    final raw = computeScheduleChanges(
      original,
      title: title ?? original.title,
      description: original.description ?? '',
      startTime: start ?? original.startTime,
      endTime: end ?? original.endTime,
      recurrence: recurrence,
    ).toBody();
    return jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;
  }

  group('computeScheduleChanges: once transitions', () {
    const toOnce = {
      'recurrence_type': 'once',
      'days_of_week': null,
      'day_of_month': null,
      'interval_days': null,
    };

    test('fixtures are what the tests assume', () {
      expect(monthly.recurrenceType, RecurrenceType.monthly);
      expect(monthly.dayOfMonth, 15);
      expect(once.recurrenceType, RecurrenceType.once);
      expect(weekly.recurrenceType, RecurrenceType.weekly);
      expect(interval.intervalDays, isNotNull);
    });

    test('monthly -> once: type + the three fields as explicit null', () {
      final b = body(monthly, formOf(monthly).copyWith(type: RecurrenceType.once));
      expect(b, toOnce);
      for (final key in ['days_of_week', 'day_of_month', 'interval_days']) {
        expect(b.containsKey(key), isTrue, reason: '$key must be an explicit null');
      }
    });

    test('weekly -> once and interval -> once: same explicit nulls', () {
      expect(body(weekly, formOf(weekly).copyWith(type: RecurrenceType.once)), toOnce);
      expect(body(interval, formOf(interval).copyWith(type: RecurrenceType.once)), toOnce);
    });

    test('once -> monthly: day set, the others explicit null', () {
      expect(body(once, const RecurrenceFormState(type: RecurrenceType.monthly, dayOfMonth: 1)), {
        'recurrence_type': 'monthly',
        'days_of_week': null,
        'day_of_month': 1,
        'interval_days': null,
      });
    });

    test('once -> weekly: days set (sorted), the others explicit null', () {
      expect(body(once, const RecurrenceFormState(type: RecurrenceType.weekly, days: {6, 0})), {
        'recurrence_type': 'weekly',
        'days_of_week': [0, 6],
        'day_of_month': null,
        'interval_days': null,
      });
    });

    test('once unchanged: only the edited fields, no recurrence key', () {
      final b = body(once, formOf(once), title: 'Diş hekimi', end: _t('15:30'));
      expect(b, {'title': 'Diş hekimi', 'end_time': '15:30'});
      expect(body(once, formOf(once)), isEmpty);
    });
  });

  group('start_date is never in a schedule PATCH', () {
    test('not for any transition, time or title change', () {
      final cases = <(ScheduleBlock, RecurrenceFormState)>[
        (monthly, const RecurrenceFormState(type: RecurrenceType.once)),
        (weekly, const RecurrenceFormState(type: RecurrenceType.once)),
        (interval, const RecurrenceFormState(type: RecurrenceType.once)),
        (once, const RecurrenceFormState(type: RecurrenceType.daily)),
        (once, const RecurrenceFormState(type: RecurrenceType.interval, intervalDays: 2)),
        (once, const RecurrenceFormState(type: RecurrenceType.once)),
      ];
      for (final (original, form) in cases) {
        final b = body(original, form, title: 'X', start: _t('01:00'), end: _t('02:00'));
        expect(b.containsKey('start_date'), isFalse, reason: '${original.id} -> ${form.type}');
        expect(b['title'], 'X');
      }
    });
  });

  group("test fakes follow the server's is_due for once", () {
    test('due only on start_date (not before, not after)', () {
      for (final (day, due) in [
        (DateTime(2026, 11, 24), false),
        (DateTime(2026, 11, 25), true),
        (DateTime(2026, 11, 25, 23, 59), true),
        (DateTime(2026, 11, 26), false),
        (DateTime(2026, 12, 25), false),
      ]) {
        expect(FakeScheduleRepository.isDue(once, day), due, reason: '$day');
        expect(
          recurrenceIsDue(type: RecurrenceType.once, startDate: once.startDate, day: day),
          due,
          reason: 'calendar fake $day',
        );
      }
    });
  });

  group('parseQuickAdd: optional bugün prefix', () {
    QuickAddOk ok(String input) {
      final r = parseQuickAdd(input);
      expect(r, isA<QuickAddOk>(), reason: input);
      return r as QuickAddOk;
    }

    String error(String input) {
      final r = parseQuickAdd(input);
      expect(r, isA<QuickAddError>(), reason: input);
      return (r as QuickAddError).message;
    }

    test("'bugün 14:00-15:00 doktor' is a one-time block", () {
      final r = ok('bugün 14:00-15:00 doktor');
      expect(r.oneTime, isTrue);
      expect(r.start, ScheduleTime.hm(14, 0));
      expect(r.end, ScheduleTime.hm(15, 0));
      expect(r.title, 'doktor');
    });

    test('any case, Turkish-aware: Bugün, BUGÜN, bUgÜn', () {
      for (final prefix in ['Bugün', 'BUGÜN', 'bUgÜn']) {
        final r = ok('$prefix 08:30-09:00 kahvaltı');
        expect(r.oneTime, isTrue, reason: prefix);
        expect(r.title, 'kahvaltı', reason: prefix);
      }
    });

    test('whitespace variants around the prefix', () {
      for (final input in [
        '  bugün 14:00-15:00 doktor',
        'bugün    14:00-15:00 doktor',
        'bugün\t14:00-15:00 doktor',
        ' Bugün  14:00 - 15:00   doktor  ',
      ]) {
        final r = ok(input);
        expect(r.oneTime, isTrue, reason: input);
        expect(r.title, 'doktor', reason: input);
        expect((r.start.hhmm, r.end.hhmm), ('14:00', '15:00'), reason: input);
      }
    });

    test('all existing time formats work after the prefix', () {
      for (final input in [
        'bugün 8:30-9:00 x',
        'bugün 08.30-09.00 x',
        'bugün 08:30\u201309:00 x',
        'bugün 08:30 - 09:00 x',
      ]) {
        final r = ok(input);
        expect(r.oneTime, isTrue, reason: input);
        expect((r.start.hhmm, r.end.hhmm), ('08:30', '09:00'), reason: input);
      }
    });

    test('the prefix alone or followed by an invalid format is the format error', () {
      for (final input in [
        'bugün',
        'bugün ',
        'BUGÜN   ',
        'bugün kahvaltı',
        'bugün 08:30 kahvaltı',
        'bugün08:30-09:00 x',
        'bugün bugün 08:30-09:00 x',
      ]) {
        expect(error(input), quickAddFormatMessage, reason: input);
      }
    });

    test('other errors after the prefix keep their own messages', () {
      expect(error('bugün 25:00-26:00 x'), timeOutOfRangeMessage);
      expect(error('bugün 10:00-09:00 x'), timeRangeInvalidMessage);
      expect(error('bugün 08:30-09:00'), titleRequiredMessage);
    });

    test("other prefix words ('yarın' etc.) are not recognised", () {
      for (final input in ['yarın 10:00-11:00 x', 'dün 10:00-11:00 x', 'bugun 10:00-11:00 x']) {
        expect(error(input), quickAddFormatMessage, reason: input);
      }
    });

    test('without the prefix: the old behaviour, not one-time', () {
      final r = ok('08:30-09:00 kahvaltı');
      expect(r.oneTime, isFalse);
      expect(r.title, 'kahvaltı');
      // 'bugün' inside the title is just text.
      final t = ok('08:30-09:00 bugün kahvaltı');
      expect(t.oneTime, isFalse);
      expect(t.title, 'bugün kahvaltı');
      expect(
        const QuickAddOk(
          start: ScheduleTime.hm(1, 0),
          end: ScheduleTime.hm(2, 0),
          title: 'x',
        ).oneTime,
        isFalse,
      );
    });

    test('the format message mentions the optional prefix', () {
      expect(quickAddFormatMessage, 'Biçim: [bugün] 08:30-09:00 başlık');
    });
  });
}
