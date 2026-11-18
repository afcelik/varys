import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/presentation/routines_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Full-screen create/edit form (outside the shell). [routine] null = create
/// (route `/routines/new`); otherwise edit (route `/routines/edit`, the
/// routine comes as `extra`).
class RoutineEditScreen extends ConsumerStatefulWidget {
  const RoutineEditScreen({super.key, this.routine});

  final Routine? routine;

  static const String createTitle = 'Yeni rutin';
  static const String editTitle = 'Rutini düzenle';
  static const String titleLabel = 'Başlık';
  static const String descriptionLabel = 'Açıklama (isteğe bağlı)';
  static const String typeLabel = 'Tekrar';
  static const String daysLabel = 'Günler';
  static const String dayOfMonthLabel = 'Ayın günü';
  static const String intervalLabel = 'Kaç günde bir';
  static const String startDateLabel = 'Başlangıç tarihi';
  static const String startDateReadOnlyHelper = 'Başlangıç tarihi değiştirilemez';
  static const String saveText = 'Kaydet';

  static const Map<RecurrenceType, String> typeLabels = {
    RecurrenceType.daily: 'Günlük',
    RecurrenceType.weekly: 'Haftalık',
    RecurrenceType.monthly: 'Aylık',
    RecurrenceType.interval: 'Aralık',
  };

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
  ConsumerState<RoutineEditScreen> createState() => RoutineEditScreenState();
}

class RoutineEditScreenState extends ConsumerState<RoutineEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _dayOfMonth;
  late final TextEditingController _interval;
  late RecurrenceFormState _recurrence;
  late DateTime _startDate;
  bool _titleTouched = false;
  bool _saving = false;

  Routine? get _original => widget.routine;
  bool get _isEdit => _original != null;

  /// Current start date (create: editable, default today; edit: read-only).
  DateTime get startDate => _startDate;

  @override
  void initState() {
    super.initState();
    final r = _original;
    _title = TextEditingController(text: r?.title ?? '');
    _description = TextEditingController(text: r?.description ?? '');
    _dayOfMonth = TextEditingController(text: r?.dayOfMonth?.toString() ?? '');
    _interval = TextEditingController(text: r?.intervalDays?.toString() ?? '');
    _recurrence = r == null
        ? const RecurrenceFormState(type: RecurrenceType.daily)
        : RecurrenceFormState.fromRoutine(r);
    _startDate = r?.startDate ?? RoutineEditScreen.clampStartDate(ref.read(todayProvider));
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
    setState(() => _startDate = RoutineEditScreen.clampStartDate(day));
  }

  RoutineChanges? get _changes => _isEdit
      ? computeChanges(
          _original!,
          title: _title.text,
          description: _description.text,
          recurrence: _recurrence,
        )
      : null;

  bool get _canSave {
    if (_saving) return false;
    if (!isFormValid(_title.text, _description.text, _recurrence)) return false;
    final changes = _changes;
    if (changes != null && changes.isEmpty) return false; // nothing changed: no request
    return true;
  }

  static PlanField<int> _parse(String text) {
    final v = int.tryParse(text);
    return v == null ? const PlanField.clear() : PlanField.set(v);
  }

  Future<void> _pickStartDate() async {
    if (_isEdit) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: RoutineEditScreen.minStartDate,
      lastDate: RoutineEditScreen.maxStartDate,
      helpText: RoutineEditScreen.startDateLabel,
    );
    if (!mounted || picked == null) return;
    setStartDate(picked);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final notifier = ref.read(routinesListProvider.notifier);
    final description = _description.text.trim();

    final Either<Failure, Object?> result;
    if (_isEdit) {
      result = await notifier.updateRoutine(_original!.id, _changes!);
    } else {
      result = await notifier.createRoutine(
        title: _title.text.trim(),
        description: description.isEmpty ? null : description,
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
          context.go(AppRouter.routinesPath);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleError = _titleTouched ? validateTitle(_title.text) : null;
    final recurrenceError = validateRecurrence(_recurrence);
    final showRecurrenceNote = _isEdit && recurrenceDiffers(_original!, _recurrence);

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(fallbackRoute: AppRouter.routinesPath),
        title: Text(
          _isEdit ? RoutineEditScreen.editTitle : RoutineEditScreen.createTitle,
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
                key: const ValueKey('routine-title'),
                controller: _title,
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: RoutineEditScreen.titleLabel,
                  errorText: titleError,
                  errorMaxLines: 2,
                ),
                onChanged: (_) => setState(() => _titleTouched = true),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('routine-description'),
                controller: _description,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: RoutineEditScreen.descriptionLabel,
                  errorText: validateDescription(_description.text),
                  errorMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              Text(RoutineEditScreen.typeLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<RecurrenceType>(
                key: const ValueKey('routine-type'),
                showSelectedIcon: false,
                segments: [
                  for (final type in RecurrenceType.values)
                    ButtonSegment(
                      value: type,
                      label: Text(
                        RoutineEditScreen.typeLabels[type]!,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                selected: {_recurrence.type},
                onSelectionChanged: _saving
                    ? null
                    : (s) => setState(() => _recurrence = _recurrence.copyWith(type: s.first)),
              ),
              const SizedBox(height: 16),
              ..._recurrenceFields(theme, recurrenceError),
              if (showRecurrenceNote) ...[
                const SizedBox(height: 12),
                Text(
                  recurrenceChangeNote,
                  key: const ValueKey('routine-recurrence-note'),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary),
                ),
              ],
              const SizedBox(height: 24),
              _StartDateField(
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
            key: const ValueKey('routine-save'),
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text(RoutineEditScreen.saveText),
          ),
        ),
      ),
    );
  }

  List<Widget> _recurrenceFields(ThemeData theme, String? error) {
    switch (_recurrence.type) {
      case RecurrenceType.daily:
        return const [];
      case RecurrenceType.weekly:
        return [
          Text(RoutineEditScreen.daysLabel, style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var d = 0; d < 7; d++)
                FilterChip(
                  key: ValueKey('weekday-$d'),
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
            key: const ValueKey('routine-day-of-month'),
            controller: _dayOfMonth,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: RoutineEditScreen.dayOfMonthLabel,
              errorText: error,
              errorMaxLines: 2,
            ),
            onChanged: (t) =>
                setState(() => _recurrence = _recurrence.copyWith(dayOfMonth: _parse(t))),
          ),
          const SizedBox(height: 4),
          Text(
            monthEndNote,
            key: const ValueKey('routine-month-end-note'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ];
      case RecurrenceType.interval:
        return [
          TextField(
            key: const ValueKey('routine-interval'),
            controller: _interval,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            decoration: InputDecoration(
              labelText: RoutineEditScreen.intervalLabel,
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

class _StartDateField extends StatelessWidget {
  const _StartDateField({required this.date, required this.readOnly, required this.onTap});

  final DateTime date;
  final bool readOnly;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final field = InputDecorator(
      key: const ValueKey('routine-start-date'),
      isEmpty: false,
      decoration: InputDecoration(
        labelText: RoutineEditScreen.startDateLabel,
        helperText: readOnly ? RoutineEditScreen.startDateReadOnlyHelper : null,
        helperMaxLines: 2,
        suffixIcon: readOnly ? const Icon(Icons.lock_outline) : const Icon(Icons.calendar_today),
        enabled: !readOnly,
      ),
      child: Text(
        RoutineEditScreen.formatStartDate(date),
        key: const ValueKey('routine-start-date-text'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (readOnly) return field;
    return InkWell(
      key: const ValueKey('routine-start-date-button'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: field),
    );
  }
}

/// Shown when `/routines/edit` is opened without a [Routine] as `extra`
/// (deep link, notification, wrong type). No silent fallback to create.
class RoutineEditUnavailablePage extends StatelessWidget {
  const RoutineEditUnavailablePage({super.key});

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
