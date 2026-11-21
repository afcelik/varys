import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Task form. [task] null: create (`/tasks/new`): title, description,
/// project, due date. [task] given: edit (`/tasks/edit`), the same fields plus
/// the planned day; no status here (the Planning checkbox does that).
///
/// The project is optional: the choices come from [projectsListProvider].
/// While they load only "Projesiz" is offered; on a load error a note with
/// "Tekrar dene" is shown. Kaydet never waits for the projects. A 404 for
/// the chosen project (deleted elsewhere) keeps the form, resets the choice
/// to "Projesiz" and reloads the projects.
///
/// Edit mode: the task's own project is offered even when completed. While
/// the projects are not loaded (loading or failed) and the task has a
/// project, the field is disabled and shows "Mevcut proje" (never
/// "Projesiz") and the project is not sent. Once loaded, a project missing
/// from the list (deleted) falls back to "Projesiz" and counts as a change.
/// Kaydet is enabled only when something changed; only changed fields are
/// sent ([computeTaskChanges]).
///
/// Both modes have the Eisenhower switches "Önemli" and "Acil" (edit: the
/// task's current values; create: off, and only a switched-on flag is sent).
///
/// Create mode with [initialProjectId] (`/tasks/new` with TaskNewArgs): that
/// project starts chosen and is offered even when completed. A project
/// missing from the loaded list (deleted) falls back to "Projesiz", with no
/// message.
class TaskEditScreen extends ConsumerStatefulWidget {
  const TaskEditScreen({super.key, this.task, this.initialProjectId});

  final Task? task;

  /// Create mode only: the project chosen when the form opens.
  final int? initialProjectId;

  static const String createTitle = 'Yeni görev';
  static const String editTitle = 'Görevi düzenle';
  static const String plannedDateLabel = 'Planlanan gün';
  static const String plannedDateHelp = 'Boş bırakırsan görev günlük listeden çıkar';
  static const String clearPlannedDateTooltip = 'Planlanan günü temizle';
  static const String currentProjectLabel = 'Mevcut proje';
  static const String titleLabel = 'Başlık';
  static const String descriptionLabel = 'Açıklama (isteğe bağlı)';
  static const String projectLabel = 'Proje';
  static const String dueDateLabel = 'Hedef tarih';
  static const String noDateText = 'Seçilmedi';
  static const String clearDateTooltip = 'Tarihi temizle';
  static const String saveText = 'Kaydet';
  static const String projectsErrorText = 'Projeler yüklenemedi';
  static const String retryText = 'Tekrar dene';
  static const String importantLabel = 'Önemli';
  static const String importantHelp = 'Hedeflerine katkısı büyük';
  static const String urgentLabel = 'Acil';
  static const String urgentHelp = 'Zamanı dar';

  /// Bounds of the due date picker.
  static final DateTime minDate = DateTime(2000, 1, 1);
  static final DateTime maxDate = DateTime(2100, 12, 31);

  /// Clamps [day] (date part only) into [minDate]..[maxDate].
  static DateTime clampDate(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(minDate)) return minDate;
    if (d.isAfter(maxDate)) return maxDate;
    return d;
  }

  static String formatDate(DateTime d) => DateFormat('dd.MM.yyyy').format(d);

  @override
  ConsumerState<TaskEditScreen> createState() => _TaskEditScreenState();
}

class _TaskEditScreenState extends ConsumerState<TaskEditScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  /// Chosen project id; null is "Projesiz".
  int? _projectId;
  DateTime? _dueDate;
  DateTime? _plannedDate;
  bool _important = false;
  bool _urgent = false;
  bool _titleTouched = false;
  bool _saving = false;

  Task? get _original => widget.task;

  @override
  void initState() {
    super.initState();
    final task = _original;
    if (task != null) {
      _title.text = task.title;
      _description.text = task.description ?? '';
      _projectId = task.projectId;
      _dueDate = _dayOf(task.dueDate);
      _plannedDate = _dayOf(task.plannedDate);
      _important = task.isImportant;
      _urgent = task.isUrgent;
    } else {
      _projectId = widget.initialProjectId;
    }
  }

  static DateTime? _dayOf(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _formValid => isTaskFormValid(title: _title.text, description: _description.text);

  /// Edit mode, task linked to a project, projects not loaded: the project
  /// cannot be shown or verified yet.
  bool _projectPending(AsyncValue<Object?> projects) =>
      _original?.projectId != null && !projects.hasValue;

  /// What the edit form changed; [selected] is the effective choice.
  TaskChanges _changes(Task original, ProjectChoice selected, bool projectPending) =>
      computeTaskChanges(
        original,
        TaskFormValues(
          title: _title.text,
          description: _description.text,
          projectId: selected.id,
          projectResolved: !projectPending,
          dueDate: _dueDate,
          plannedDate: _plannedDate,
          isImportant: _important,
          isUrgent: _urgent,
        ),
      );

  /// The chosen project if it is still offered, otherwise "Projesiz".
  ProjectChoice _selected(List<ProjectChoice> choices) => choices.firstWhere(
    (c) => c.id != null && c.id == _projectId,
    orElse: () => ProjectChoice.none,
  );

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? TaskEditScreen.clampDate(ref.read(todayProvider)),
      firstDate: TaskEditScreen.minDate,
      lastDate: TaskEditScreen.maxDate,
    );
    if (!mounted || picked == null) return;
    setState(() => onPicked(TaskEditScreen.clampDate(picked)));
  }

  void _showFailure(Failure failure) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
    );
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRouter.planningPath);
    }
  }

  Future<void> _saveEdit(Task original, TaskChanges changes) async {
    if (_saving || !_formValid || changes.isEmpty) return;
    setState(() => _saving = true);
    final result = await ref.read(taskListNotifierProvider.notifier).updateTask(original, changes);
    if (!mounted) return; // page closed while the request ran

    result.fold((failure) {
      final projectGone =
          changes.projectId is PlanFieldSet<int> &&
          failure is ServerFailure &&
          failure.statusCode == 404;
      setState(() {
        _saving = false;
        if (projectGone) _projectId = null;
      });
      if (projectGone) ref.invalidate(projectsListProvider);
      _showFailure(failure);
    }, (_) => _close());
  }

  Future<void> _save(ProjectChoice project) async {
    if (_saving || !_formValid) return;
    setState(() => _saving = true);
    final projectId = project.id;
    final result = await ref
        .read(taskListNotifierProvider.notifier)
        .addTask(
          buildNewTask(
            title: _title.text,
            description: _description.text,
            projectId: projectId,
            dueDate: _dueDate,
            isImportant: _important,
            isUrgent: _urgent,
          ),
        );
    if (!mounted) return; // page closed while the request ran

    result.fold((failure) {
      final projectGone =
          projectId != null && failure is ServerFailure && failure.statusCode == 404;
      setState(() {
        _saving = false;
        if (projectGone) _projectId = null;
      });
      if (projectGone) ref.invalidate(projectsListProvider);
      _showFailure(failure);
    }, (_) => _close());
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsListProvider);
    final original = _original;
    final projectPending = _projectPending(projects);
    final List<ProjectChoice> choices;
    final ProjectChoice selected;
    if (projectPending) {
      // Not "Projesiz": the task keeps its project until the list is known.
      selected = ProjectChoice(id: original!.projectId, label: TaskEditScreen.currentProjectLabel);
      choices = [selected];
    } else {
      choices = projectChoices(
        projects.valueOrNull?.projects ?? const [],
        keepProjectId: original == null ? widget.initialProjectId : original.projectId,
      );
      selected = _selected(choices);
    }
    final titleError = _titleTouched ? validateTaskTitle(_title.text) : null;
    final changes = original == null ? null : _changes(original, selected, projectPending);
    final canSave = !_saving && _formValid && (changes == null || !changes.isEmpty);

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(fallbackRoute: AppRouter.planningPath),
        title: Text(
          original == null ? TaskEditScreen.createTitle : TaskEditScreen.editTitle,
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
                key: const ValueKey('task-title'),
                controller: _title,
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: TaskEditScreen.titleLabel,
                  errorText: titleError,
                  errorMaxLines: 2,
                ),
                onChanged: (_) => setState(() => _titleTouched = true),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('task-description'),
                controller: _description,
                enabled: !_saving,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: TaskEditScreen.descriptionLabel,
                  errorText: validateTaskDescription(_description.text),
                  errorMaxLines: 2,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 24),
              _projectField(Theme.of(context), projects, choices, selected, projectPending),
              const SizedBox(height: 24),
              _DateField(
                keyPrefix: 'task-due-date',
                label: TaskEditScreen.dueDateLabel,
                clearTooltip: TaskEditScreen.clearDateTooltip,
                date: _dueDate,
                enabled: !_saving,
                onPick: () => _pickDate(_dueDate, (d) => _dueDate = d),
                onClear: () => setState(() => _dueDate = null),
              ),
              if (original != null) ...[
                const SizedBox(height: 24),
                _DateField(
                  keyPrefix: 'task-planned-date',
                  label: TaskEditScreen.plannedDateLabel,
                  clearTooltip: TaskEditScreen.clearPlannedDateTooltip,
                  helperText: TaskEditScreen.plannedDateHelp,
                  date: _plannedDate,
                  enabled: !_saving,
                  onPick: () => _pickDate(_plannedDate, (d) => _plannedDate = d),
                  onClear: () => setState(() => _plannedDate = null),
                ),
              ],
              const SizedBox(height: 16),
              _FlagSwitch(
                key: const ValueKey('task-important'),
                label: TaskEditScreen.importantLabel,
                help: TaskEditScreen.importantHelp,
                value: _important,
                onChanged: _saving ? null : (v) => setState(() => _important = v),
              ),
              _FlagSwitch(
                key: const ValueKey('task-urgent'),
                label: TaskEditScreen.urgentLabel,
                help: TaskEditScreen.urgentHelp,
                value: _urgent,
                onChanged: _saving ? null : (v) => setState(() => _urgent = v),
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
            key: const ValueKey('task-save'),
            onPressed: !canSave
                ? null
                : original == null
                ? () => _save(selected)
                : () => _saveEdit(original, changes!),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text(TaskEditScreen.saveText),
          ),
        ),
      ),
    );
  }

  Widget _projectField(
    ThemeData theme,
    AsyncValue<Object?> projects,
    List<ProjectChoice> choices,
    ProjectChoice selected,
    bool projectPending,
  ) {
    final children = <Widget>[
      DropdownMenu<ProjectChoice>(
        // Rebuilt when the choices or the selection change so the field
        // shows the current selection.
        key: ValueKey('task-project-${selected.id}-${choices.length}'),
        initialSelection: selected,
        enabled: !_saving && !projectPending,
        requestFocusOnTap: false,
        expandedInsets: EdgeInsets.zero,
        label: const Text(TaskEditScreen.projectLabel),
        dropdownMenuEntries: [
          for (final c in choices)
            DropdownMenuEntry(
              value: c,
              label: c.label,
              labelWidget: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailingIcon: c.statusLabel == null
                  ? null
                  : Text(
                      c.statusLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
            ),
        ],
        onSelected: (c) => setState(() => _projectId = c?.id),
      ),
    ];

    if (!projects.hasValue && projects.hasError) {
      children.addAll([
        const SizedBox(height: 8),
        Text(
          TaskEditScreen.projectsErrorText,
          key: const ValueKey('task-projects-error'),
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton(
            key: const ValueKey('task-projects-retry'),
            onPressed: () => ref.invalidate(projectsListProvider),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text(TaskEditScreen.retryText),
          ),
        ),
      ]);
    } else if (!projects.hasValue) {
      children.addAll(const [
        SizedBox(height: 8),
        LinearProgressIndicator(key: ValueKey('task-projects-loading')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

/// One Eisenhower switch: the whole row (at least 48 high) toggles it;
/// [onChanged] null disables it (while saving). The help text wraps to at
/// most 2 lines.
class _FlagSwitch extends StatelessWidget {
  const _FlagSwitch({
    super.key,
    required this.label,
    required this.help,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String help;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        contentPadding: EdgeInsets.zero,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(help, maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Optional day: tap to pick (48 high), × to clear (48x48). Keys:
/// `<keyPrefix>-button`, `<keyPrefix>`, `<keyPrefix>-clear`, `<keyPrefix>-text`.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.keyPrefix,
    required this.label,
    required this.clearTooltip,
    required this.date,
    required this.enabled,
    required this.onPick,
    required this.onClear,
    this.helperText,
  });

  final String keyPrefix;
  final String label;
  final String clearTooltip;
  final String? helperText;
  final DateTime? date;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final d = date;
    return InkWell(
      key: ValueKey('$keyPrefix-button'),
      onTap: enabled ? onPick : null,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InputDecorator(
          key: ValueKey(keyPrefix),
          isEmpty: false,
          decoration: InputDecoration(
            labelText: label,
            helperText: helperText,
            helperMaxLines: 3,
            enabled: enabled,
            suffixIcon: d == null
                ? const Icon(Icons.calendar_today)
                : IconButton(
                    key: ValueKey('$keyPrefix-clear'),
                    icon: const Icon(Icons.close),
                    tooltip: clearTooltip,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: enabled ? onClear : null,
                  ),
          ),
          child: Text(
            d == null ? TaskEditScreen.noDateText : TaskEditScreen.formatDate(d),
            key: ValueKey('$keyPrefix-text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

/// Shown when `/tasks/edit` is opened without a Task (deep link,
/// notification, wrong extra). Leaves with BackArrow (pop, or /home).
class TaskEditUnavailablePage extends StatelessWidget {
  const TaskEditUnavailablePage({super.key});

  static const String message = 'Bu sayfa doğrudan açılamaz.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: const BackArrow()),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            key: const ValueKey('task-edit-unavailable'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
