import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';

List<ScheduleBlock> _list() =>
    (jsonDecode(File('test/fixtures/schedule_list.json').readAsStringSync()) as List)
        .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
        .toList();

ScheduleTime _t(String s) => ScheduleTime.parse(s);

void main() {
  late List<ScheduleBlock> blocks;
  late ScheduleBlock daily; // id 1, 06:30-07:15, description set
  late ScheduleBlock weekly; // id 2, 08:30-09:00, Pzt/Çar/Cum, no description
  late ScheduleBlock monthly; // id 4, 12:00-12:30, day 15

  setUpAll(() {
    blocks = _list();
    daily = blocks.firstWhere((b) => b.id == 1);
    weekly = blocks.firstWhere((b) => b.id == 2);
    monthly = blocks.firstWhere((b) => b.id == 4);
  });

  RecurrenceFormState formOf(ScheduleBlock b) => RecurrenceFormState.fromFields(
    type: b.recurrenceType,
    daysOfWeek: b.daysOfWeek,
    dayOfMonth: b.dayOfMonth,
    intervalDays: b.intervalDays,
  );

  group('validation', () {
    test('time range: end must be strictly after start', () {
      expect(validateTimeRange(_t('08:00'), _t('08:01')), isNull);
      expect(validateTimeRange(_t('00:00'), _t('23:59')), isNull);
      expect(validateTimeRange(_t('08:00'), _t('08:00')), timeRangeInvalidMessage);
      expect(validateTimeRange(_t('09:00'), _t('08:00')), timeRangeInvalidMessage);
      expect(timeRangeInvalidMessage, 'Bitiş saati başlangıçtan sonra olmalı');
    });

    test('form validity reuses the routine title/description/recurrence rules', () {
      const r = RecurrenceFormState(type: RecurrenceType.daily);
      bool valid({
        String title = 'Kahvaltı',
        String description = '',
        String start = '08:00',
        String end = '09:00',
        RecurrenceFormState recurrence = r,
      }) => isScheduleFormValid(
        title: title,
        description: description,
        start: _t(start),
        end: _t(end),
        recurrence: recurrence,
      );

      expect(valid(), isTrue);
      expect(valid(title: '   '), isFalse);
      expect(valid(title: 'ş' * 255), isTrue); // 255 code points
      expect(valid(title: 'ş' * 256), isFalse);
      expect(valid(description: 'a' * 2000), isTrue);
      expect(valid(description: 'a' * 2001), isFalse);
      expect(valid(end: '08:00'), isFalse);
      expect(valid(recurrence: const RecurrenceFormState(type: RecurrenceType.weekly)), isFalse);
      expect(
        valid(
          recurrence: const RecurrenceFormState(type: RecurrenceType.weekly, days: {3}),
        ),
        isTrue,
      );
      expect(valid(recurrence: const RecurrenceFormState(type: RecurrenceType.monthly)), isFalse);
      expect(
        valid(
          recurrence: const RecurrenceFormState(type: RecurrenceType.interval, intervalDays: 0),
        ),
        isFalse,
      );
    });
  });

  group('computeScheduleChanges', () {
    ScheduleChanges diff(
      ScheduleBlock b, {
      String? title,
      String? description,
      String? start,
      String? end,
      RecurrenceFormState? recurrence,
    }) => computeScheduleChanges(
      b,
      title: title ?? b.title,
      description: description ?? b.description ?? '',
      startTime: start == null ? b.startTime : _t(start),
      endTime: end == null ? b.endTime : _t(end),
      recurrence: recurrence ?? formOf(b),
    );

    test('nothing changed: empty, no body', () {
      for (final b in blocks) {
        final c = diff(b);
        expect(c.isEmpty, isTrue, reason: 'block ${b.id}');
        expect(c.toBody(), isEmpty);
      }
    });

    test('whitespace-only edits of title/description are not changes', () {
      expect(
        diff(daily, title: '  ${daily.title}  ', description: ' ${daily.description} ').isEmpty,
        isTrue,
      );
    });

    test('title set (trimmed)', () {
      expect(diff(daily, title: '  Akşam koşusu ').toBody(), {'title': 'Akşam koşusu'});
    });

    test('description set, and empty clears (key present, value null)', () {
      expect(diff(weekly, description: 'Yulaf').toBody(), {'description': 'Yulaf'});
      final body = diff(daily, description: '   ').toBody();
      expect(body.containsKey('description'), isTrue);
      expect(body['description'], isNull);
      expect(body.length, 1);
    });

    test('times are sent only when changed, as HH:MM without seconds', () {
      expect(diff(daily, start: '06:00').toBody(), {'start_time': '06:00'});
      expect(diff(daily, end: '23:59').toBody(), {'end_time': '23:59'});
      expect(diff(daily, start: '00:00', end: '00:30').toBody(), {
        'start_time': '00:00',
        'end_time': '00:30',
      });
    });

    test('recurrence changed: type + all three fields, unrelated ones explicit null', () {
      final toWeekly = diff(
        daily,
        recurrence: formOf(daily).copyWith(type: RecurrenceType.weekly, days: {4, 1}),
      );
      expect(toWeekly.toBody(), {
        'recurrence_type': 'weekly',
        'days_of_week': [1, 4],
        'day_of_month': null,
        'interval_days': null,
      });

      final toDaily = diff(weekly, recurrence: formOf(weekly).copyWith(type: RecurrenceType.daily));
      final body = toDaily.toBody();
      expect(body, {
        'recurrence_type': 'daily',
        'days_of_week': null,
        'day_of_month': null,
        'interval_days': null,
      });
      expect(body.containsKey('days_of_week'), isTrue);

      final newDay = diff(
        monthly,
        recurrence: formOf(monthly).copyWith(dayOfMonth: const PlanField.set(31)),
      );
      expect(newDay.toBody(), {
        'recurrence_type': 'monthly',
        'days_of_week': null,
        'day_of_month': 31,
        'interval_days': null,
      });
    });

    test('values typed for another type do not count when the type is unchanged', () {
      final r = formOf(daily).copyWith(dayOfMonth: const PlanField.set(5), days: {2});
      expect(diff(daily, recurrence: r).isEmpty, isTrue);
      expect(scheduleRecurrenceDiffers(daily, r), isFalse);
      expect(scheduleRecurrenceDiffers(daily, r.copyWith(type: RecurrenceType.monthly)), isTrue);
    });

    test('weekday order is not a change', () {
      final r = formOf(weekly).copyWith(days: {4, 2, 0});
      expect(diff(weekly, recurrence: r).isEmpty, isTrue);
    });

    test('the body never has start_date and is JSON-encodable', () {
      final c = diff(
        weekly,
        title: 'Yeni',
        description: 'x',
        start: '07:00',
        end: '07:30',
        recurrence: formOf(
          weekly,
        ).copyWith(type: RecurrenceType.interval, intervalDays: const PlanField.set(2)),
      );
      final body = c.toBody();
      expect(body.containsKey('start_date'), isFalse);
      expect(jsonDecode(jsonEncode(body)), body);
      expect(body['recurrence_type'], isA<String>());
    });
  });

  group('blockStatusAt', () {
    ScheduleBlock block(String start, String end) =>
        daily.copyWith(startTime: _t(start), endTime: _t(end));

    test('start included, end excluded', () {
      final b = block('08:30', '09:00');
      expect(blockStatusAt(b, 8 * 60 + 29), BlockStatus.upcoming);
      expect(blockStatusAt(b, 8 * 60 + 30), BlockStatus.current);
      expect(blockStatusAt(b, 8 * 60 + 59), BlockStatus.current);
      expect(blockStatusAt(b, 9 * 60), BlockStatus.past);
    });

    test('00:00-23:59 block: current at 00:00 and 23:58, past at 23:59', () {
      final b = block('00:00', '23:59');
      expect(blockStatusAt(b, 0), BlockStatus.current);
      expect(blockStatusAt(b, 1438), BlockStatus.current);
      expect(blockStatusAt(b, 1439), BlockStatus.past);
    });

    test('a block starting at 23:58 is upcoming at 00:00', () {
      expect(blockStatusAt(block('23:58', '23:59'), 0), BlockStatus.upcoming);
    });

    test('minuteOfDay reads the wall clock', () {
      expect(minuteOfDay(DateTime(2026, 11, 20, 0, 0, 59)), 0);
      expect(minuteOfDay(DateTime(2026, 11, 20, 23, 59, 59)), 1439);
    });
  });

  group('sortBlocks', () {
    test('by start time, then id; returns a new list', () {
      final shuffled = [...blocks.reversed];
      final sorted = sortBlocks(shuffled);
      expect(sorted.map((b) => b.id), [6, 1, 2, 3, 7, 4, 5]);
      expect(shuffled.first.id, 5, reason: 'input untouched');
    });

    test('same start time: lower id first even if the server sent them reversed', () {
      final a = daily.copyWith(id: 9, startTime: _t('09:00'), endTime: _t('10:00'));
      final b = daily.copyWith(id: 3, startTime: _t('09:00'), endTime: _t('09:30'));
      expect(sortBlocks([a, b]).map((x) => x.id), [3, 9]);
    });
  });

  group('parseQuickAdd', () {
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

    test('all accepted forms give 08:30-09:00 kahvaltı', () {
      for (final input in [
        '08:30-09:00 kahvaltı',
        '8:30-9:00 kahvaltı',
        '08.30-09.00 kahvaltı',
        '08:30\u201309:00 kahvaltı', // en dash
        '08:30 - 09:00 kahvaltı',
        '08:30 \u2013 09:00 kahvaltı',
        '  08:30-09:00   kahvaltı  ',
      ]) {
        final r = ok(input);
        expect((r.start.hhmm, r.end.hhmm, r.title), ('08:30', '09:00', 'kahvaltı'), reason: input);
      }
    });

    test('bounds 00:00 and 23:59 are accepted', () {
      final r = ok('00:00-23:59 nöbet');
      expect((r.start.minutes, r.end.minutes), (0, 1439));
    });

    test('title keeps inner spaces and Unicode (Turkish, emoji)', () {
      expect(ok('07:00-07:30 Sabah   yürüyüşü İzmir').title, 'Sabah   yürüyüşü İzmir');
      expect(ok('07:00-07:30 Çay \u{1F375}').title, 'Çay \u{1F375}');
    });

    test('out-of-range times are rejected (24:00, 7:75)', () {
      expect(error('23:00-24:00 gece'), timeOutOfRangeMessage);
      expect(error('7:75-8:00 x'), timeOutOfRangeMessage);
      expect(error('25:00-26:00 x'), timeOutOfRangeMessage);
    });

    test('end not after start is rejected', () {
      expect(error('09:00-09:00 x'), timeRangeInvalidMessage);
      expect(error('10:00-09:00 x'), timeRangeInvalidMessage);
    });

    test('empty or blank title is rejected', () {
      expect(error('08:30-09:00'), titleRequiredMessage);
      expect(error('08:30-09:00    '), titleRequiredMessage);
    });

    test('title over 255 code points is rejected', () {
      expect(ok('08:30-09:00 ${'ğ' * 255}').title.runes.length, 255);
      expect(error('08:30-09:00 ${'ğ' * 256}'), titleTooLongMessage);
    });

    test('unrecognised formats give the format hint', () {
      for (final input in [
        '',
        'kahvaltı',
        '08:30 kahvaltı',
        '0830-0900 kahvaltı',
        '08:30-09:00kahvaltı',
        '08:3-09:00 x',
        '08:30/09:00 x',
        '08:30\u201409:00 x', // em dash is not accepted
        '\u0660\u0668:\u0663\u0660-09:00 x', // Arabic-Indic digits
        'x 08:30-09:00',
      ]) {
        expect(error(input), quickAddFormatMessage, reason: input);
      }
      expect(quickAddFormatMessage, 'Biçim: [bugün] 08:30-09:00 başlık');
    });
  });

  group('defaultTimesFor', () {
    String at(int h, int m) {
      final r = defaultTimesFor(DateTime(2026, 11, 20, h, m));
      return '${r.start.hhmm}-${r.end.hhmm}';
    }

    test('next full hour for one hour', () {
      expect(at(7, 10), '08:00-09:00');
      expect(at(0, 0), '01:00-02:00');
      expect(at(21, 0), '22:00-23:00');
      expect(at(21, 30), '22:00-23:00');
    });

    test('22:00 or later falls back to 22:00-23:00', () {
      expect(at(22, 0), '22:00-23:00');
      expect(at(23, 40), '22:00-23:00');
      expect(at(23, 59), '22:00-23:00');
    });
  });

  test('formatTimeRange uses an en dash', () {
    expect(formatTimeRange(_t('08:30'), _t('09:00')), '08:30\u201309:00');
    expect(timeRangeSeparator.codeUnits, [0x2013]);
  });

  test('recurrence summaries are the routine ones', () {
    expect(
      blocks.map(
        (b) => recurrenceSummaryOf(
          b.recurrenceType,
          daysOfWeek: b.daysOfWeek,
          dayOfMonth: b.dayOfMonth,
          intervalDays: b.intervalDays,
        ),
      ),
      ['Her gün', 'Her gün', 'Pzt, Çar, Cum', 'Her gün', 'Her gün', "Ayın 15'i", 'Her 3 günde bir'],
    );
  });
}
