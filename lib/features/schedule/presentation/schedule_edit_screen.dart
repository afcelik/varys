import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/core/time/clock.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Opens a time picker for [initial]; null when dismissed.
typedef ScheduleTimePicker =
    Future<ScheduleTime?> Function(BuildContext context, ScheduleTime initial, String helpText);

/// Material time picker, always 24-hour.
Future<ScheduleTime?> showScheduleTimePicker(
  BuildContext context,
  ScheduleTime initial,
  String helpText,
) async {
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
    helpText: helpText,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  return picked == null ? null : ScheduleTime.hm(picked.hour, picked.minute);
}

/// The time picker used by the form; tests replace it with a fake.
final timePickerProvider = Provider<ScheduleTimePicker>((ref) => showScheduleTimePicker);

/// Full-screen create/edit form (outside the shell). [block] null = create
/// (route `/schedule/new`); otherwise edit (route `/schedule/edit`, the block
/// comes as `extra`). On create, [initialDay] (default today, clamped to the
/// allowed range) is the start date and [initialOnce] preselects the
/// one-time type; both are ignored when editing. The recurrence widgets are copied from the routine form
/// (`RoutineEditScreen`), which stays unchanged.
class ScheduleEditScreen extends ConsumerStatefulWidget {
  const ScheduleEditScreen({super.key, this.block, this.initialDay, this.initialOnce = false});

  final ScheduleBlock? block;
  final DateTime? initialDay;
  final bool initialOnce;

  static const String createTitle = 'Yeni blok';
  static const String editTitle = 'Bloğu düzenle';
  static const String titleLabel = 'Başlık';
  static const String descriptionLabel = 'Açıklama (isteğe bağlı)';
  static const String startTimeLabel = 'Başlangıç saati';
  static const String endTimeLabel = 'Bitiş saati';
  static const String typeLabel = 'Tekrar';
  static const String daysLabel = 'Günler';
  static const String dayOfMonthLabel = 'Ayın günü';
  static const String intervalLabel = 'Kaç günde bir';
  static const String startDateLabel = 'Başlangıç tarihi';

  /// Label of the start date field while the one-time type is selected: the
  /// block happens on that day only.
  static const String onceDayLabel = 'Gün';
  static const String startDateReadOnlyHelper = 'Başlangıç tarihi değiştirilemez';
  static const String saveText = 'Kaydet';

  static const Map<RecurrenceType, String> typeLabels = {
    RecurrenceType.daily: 'Günlük',
    RecurrenceType.weekly: 'Haftalık',
    RecurrenceType.monthly: 'Aylık',
    RecurrenceType.interval: 'Aralık',
    RecurrenceType.once: oneTimeLabel,
  };

  /// Edit only, shown while 'Tek sefer' is selected for a block that was not
  /// one-time: it will happen on its (unchangeable) start day.
  static String onceNote(DateTime startDate) =>
      'Tek sefer, bloğun başlangıç gününde olur (${dayMonthLabel(startDate)}).';

  /// Bounds of the start date (same as the backend).
  static final DateTime minStartDate = DateTime(2000, 1, 1);
  static final DateTime maxStartDate = DateTime(2100, 12, 31);

  /// Clamps [day] (date part only) into [minStartDate]..[maxStartDate].
  static DateTime clampStartDate(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(minStartDate)) return minStartDate;
    if (d.isAfter(maxStartDate)) return maxStartDate;
    return d;
  }

  static String formatStartDate(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  @override
  ConsumerState<ScheduleEditScreen> createState() => ScheduleEditScreenState();
}

class ScheduleEditScreenState extends ConsumerState<ScheduleEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _dayOfMonth;
  late final TextEditingController _interval;
  late RecurrenceFormState _recurrence;
  late ScheduleTime _start;
  late ScheduleTime _end;
  late DateTime _startDate;
  bool _titleTouched = false;
  bool _saving = false;

  ScheduleBlock? get _original => widget.block;
  bool get _isEdit => _original != null;

  /// Current values (for tests).
  ScheduleTime get startTime => _start;
  ScheduleTime get endTime => _end;
  DateTime get startDate => _startDate;

  @override
  void initState() {
    super.initState();
    final b = _original;
    _title = TextEditingController(text: b?.title ?? '');
    _description = TextEditingController(text: b?.description ?? '');
    _dayOfMonth = TextEditingController(text: b?.dayOfMonth?.toString() ?? '');
    _interval = TextEditingController(text: b?.intervalDays?.toString() ?? '');
    _recurrence = b == null
        ? RecurrenceFormState(
            type: widget.initialOnce ? RecurrenceType.once : RecurrenceType.daily,
          )
        : RecurrenceFormState.fromFields(
            type: b.recurrenceType,
            daysOfWeek: b.daysOfWeek,
            dayOfMonth: b.dayOfMonth,
            intervalDays: b.intervalDays,
          );
    if (b == null) {
      final defaults = defaultTimesFor(ref.read(nowProvider)());
      _start = defaults.start;
      _end = defaults.end;
    } else {
      _start = b.startTime;
      _end = b.endTime;
    }
    _startDate =
        b?.startDate ??
        ScheduleEditScreen.clampStartDate(widget.initialDay ?? ref.read(todayProvider));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _dayOfMonth.dispose();
    _interval.dispose();
    super.dispose();
  }

  /// Sets the start date (create only), clamped to the allowed range.
  void setStartDate(DateTime day) {
    if (_isEdit) return;
    setState(() => _startDate = ScheduleEditScreen.clampStartDate(day));
  }

  ScheduleChanges? get _changes => _isEdit
      ? computeScheduleChanges(
          _original!,
          title: _title.text,
          description: _description.text,
          startTime: _start,
          endTime: _end,
          recurrence: _recurrence,
        )
      : null;

  bool get _canSave {
    if (_saving) return false;
    final valid = isScheduleFormValid(
      title: _title.text,
      description: _description.text,
      start: _start,
      end: _end,
      recurrence: _recurrence,
    );
    if (!valid) return false;
    final changes = _changes;
    if (changes != null && changes.isEmpty) return false; // nothing changed: no request
    return true;
  }

  static PlanField<int> _parse(String text) {
    final v = int.tryParse(text);
    return v == null ? const PlanField.clear() : PlanField.set(v);
  }

  Future<void> _pickTime({required bool start}) async {
    final picker = ref.read(timePickerProvider);
    final picked = await picker(
      context,
      start ? _start : _end,
      start ? ScheduleEditScreen.startTimeLabel : ScheduleEditScreen.endTimeLabel,
    );
    if (!mounted || picked == null) return;
    setState(() => start ? _start = picked : _end = picked);
  }

  Future<void> _pickStartDate() async {
    if (_isEdit) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: ScheduleEditScreen.minStartDate,
      lastDate: ScheduleEditScreen.maxStartDate,
      helpText: ScheduleEditScreen.startDateLabel,
    );
    if (!mounted || picked == null) return;
    setStartDate(picked);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final notifier = ref.read(scheduleBlocksProvider.notifier);
    final description = _description.text.trim();

    final Either<Failure, Object?> result;
    if (_isEdit) {
      result = await notifier.updateBlock(_original!.id, _changes!);
    } else {
      result = await notifier.createBlock(
        title: _title.text.trim(),
        description: description.isEmpty ? null : description,
        startTime: _start,
        endTime: _end,
        recurrenceType: _recurrence.type,
        daysOfWeek: _recurrence.effectiveDays,
        dayOfMonth: _recurrence.effectiveDayOfMonth,
        intervalDays: _recurrence.effectiveIntervalDays,
        startDate: _startDate,
      );
    }
    if (!mounted) return; // page closed while the request ran

    result.fold(
      (failure) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
        );
      },
      (_) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRouter.schedulePath);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleError = _titleTouched ? validateTitle(_title.text) : null;
    final recurrenceError = validateRecurrence(_recurrence);
    final rangeError = validateTimeRange(_start, _end);
    final showRecurrenceNote = _isEdit && scheduleRecurrenceDiffers(_original!, _recurrence);
    final isOnce = _recurrence.type == RecurrenceType.once;
    final showOnceNote = _isEdit && isOnce && _original!.recurrenceType != RecurrenceType.once;

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(fallbackRoute: AppRouter.schedulePath),
        title: Text(
          _isEdit ? ScheduleEditScreen.editTitle : ScheduleEditScreen.createTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('schedule-title'),
                controller: _title,
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: ScheduleEditScreen.titleLabel,
                  errorText: titleError,
                  errorMaxLines: 2,
                ),
                onChanged: (_) => setState(() => _titleTouched = true),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('schedule-description'),
                controller: _description,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: ScheduleEditScreen.descriptionLabel,
                  errorText: validateDescription(_description.text),
                  errorMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              _TimeField(
                fieldKey: 'schedule-start-time',
                label: ScheduleEditScreen.startTimeLabel,
                value: _start,
                onTap: _saving ? null : () => _pickTime(start: true),
              ),
              const SizedBox(height: 16),
              _TimeField(
                fieldKey: 'schedule-end-time',
                label: ScheduleEditScreen.endTimeLabel,
                value: _end,
                errorText: rangeError,
                onTap: _saving ? null : () => _pickTime(start: false),
              ),
              const SizedBox(height: 24),
              Text(ScheduleEditScreen.typeLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              // Chips wrap onto a new line instead of squeezing five labels
              // into one row (360px at 1.5x text would truncate them).
              Wrap(
                key: const ValueKey('schedule-type'),
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final MapEntry(key: type, value: label)
                      in ScheduleEditScreen.typeLabels.entries)
                    ChoiceChip(
                      key: ValueKey('schedule-type-${type.name}'),
                      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      selected: _recurrence.type == type,
                      showCheckmark: false,
                      materialTapTargetSize: MaterialTapTargetSize.padded,
                      onSelected: _saving
                          ? null
                          : (selected) {
                              // Tapping the selected chip keeps it selected.
                              if (!selected) return;
                              setState(() => _recurrence = _recurrence.copyWith(type: type));
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ..._recurrenceFields(theme, recurrenceError),
              if (showRecurrenceNote) ...[
                const SizedBox(height: 12),
                Text(
                  scheduleRecurrenceChangeNote,
                  key: const ValueKey('schedule-recurrence-note'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary),
                ),
              ],
              if (showOnceNote) ...[
                const SizedBox(height: 8),
                Text(
                  ScheduleEditScreen.onceNote(_original!.startDate),
                  key: const ValueKey('schedule-once-note'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary),
                ),
              ],
              const SizedBox(height: 24),
              _StartDateField(
                label: isOnce ? ScheduleEditScreen.onceDayLabel : ScheduleEditScreen.startDateLabel,
                date: _startDate,
                readOnly: _isEdit,
                onTap: _saving ? null : _pickStartDate,
              ),
            ],
          ),
        ),
      ),
      // Kaydet stays outside the scroll view: always reachable, lifted above
      // the keyboard, and a floating snackbar is laid out above it instead
      // of covering it.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: FilledButton(
            key: const ValueKey('schedule-save'),
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text(ScheduleEditScreen.saveText),
          ),
        ),
      ),
    );
  }

  // Copied from RoutineEditScreen._recurrenceFields (keys renamed).
  List<Widget> _recurrenceFields(ThemeData theme, String? error) {
    switch (_recurrence.type) {
      case RecurrenceType.daily:
      case RecurrenceType.once:
        return const [];
      case RecurrenceType.weekly:
        return [
          Text(ScheduleEditScreen.daysLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var d = 0; d < 7; d++)
                FilterChip(
                  key: ValueKey('schedule-weekday-$d'),
                  label: Text(weekdayShortNames[d]),
                  selected: _recurrence.days.contains(d),
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _recurrence = _recurrence.toggleDay(d)),
                ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
        ];
      case RecurrenceType.monthly:
        return [
          TextField(
            key: const ValueKey('schedule-day-of-month'),
            controller: _dayOfMonth,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: ScheduleEditScreen.dayOfMonthLabel,
              errorText: error,
              errorMaxLines: 2,
            ),
            onChanged: (t) =>
                setState(() => _recurrence = _recurrence.copyWith(dayOfMonth: _parse(t))),
          ),
          const SizedBox(height: 4),
          Text(
            monthEndNote,
            key: const ValueKey('schedule-month-end-note'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ];
      case RecurrenceType.interval:
        return [
          TextField(
            key: const ValueKey('schedule-interval'),
            controller: _interval,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: ScheduleEditScreen.intervalLabel,
              suffixText: 'gün',
              errorText: error,
              errorMaxLines: 2,
            ),
            onChanged: (t) =>
                setState(() => _recurrence = _recurrence.copyWith(intervalDays: _parse(t))),
          ),
        ];
    }
  }
}

/// A tappable 'HH:MM' field (at least 48 high) that opens the time picker.
class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onTap,
    this.errorText,
  });

  final String fieldKey;
  final String label;
  final ScheduleTime value;
  final VoidCallback? onTap;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: ValueKey(fieldKey),
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            labelText: label,
            errorText: errorText,
            errorMaxLines: 2,
            suffixIcon: const Icon(Icons.access_time),
            enabled: onTap != null,
          ),
          child: Text(
            value.hhmm,
            key: ValueKey('$fieldKey-text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ),
    );
  }
}

// Copied from RoutineEditScreen's _StartDateField (keys renamed).
class _StartDateField extends StatelessWidget {
  const _StartDateField({
    required this.label,
    required this.date,
    required this.readOnly,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final field = InputDecorator(
      key: const ValueKey('schedule-start-date'),
      isEmpty: false,
      decoration: InputDecoration(
        labelText: label,
        helperText: readOnly ? ScheduleEditScreen.startDateReadOnlyHelper : null,
        helperMaxLines: 2,
        suffixIcon: readOnly ? const Icon(Icons.lock_outline) : const Icon(Icons.calendar_today),
        enabled: !readOnly,
      ),
      child: Text(
        ScheduleEditScreen.formatStartDate(date),
        key: const ValueKey('schedule-start-date-text'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (readOnly) return field;
    return InkWell(
      key: const ValueKey('schedule-start-date-button'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: field),
    );
  }
}

/// Shown when `/schedule/edit` is opened without a [ScheduleBlock] as
/// `extra` (deep link, notification, wrong type), and when `/schedule/new`
/// gets an `extra` that is not a [ScheduleNewArgs]. No silent fallback to
/// create.
class ScheduleEditUnavailablePage extends StatelessWidget {
  const ScheduleEditUnavailablePage({super.key});

  static const String message = 'Bu sayfa doğrudan açılamaz.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: const BackArrow()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
