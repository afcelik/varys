import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Task create form (`/tasks/new`): title, description, project, due date.
///
/// Only creating is supported in this step; [task] is reserved for editing
/// and must be null.
///
/// The project is optional: the choices come from [projectsListProvider].
/// While they load only "Projesiz" is offered; on a load error a note with
/// "Tekrar dene" is shown. Kaydet never waits for the projects. A 404 for
/// the chosen project (deleted elsewhere) keeps the form, resets the choice
/// to "Projesiz" and reloads the projects.
class TaskEditScreen extends ConsumerStatefulWidget {
  const TaskEditScreen({super.key, this.task})
    : assert(task == null, 'Editing a task is not supported yet');

  final Task? task;

  static const String createTitle = 'Yeni görev';
  static const String titleLabel = 'Başlık';
  static const String descriptionLabel = 'Açıklama (isteğe bağlı)';
  static const String projectLabel = 'Proje';
  static const String dueDateLabel = 'Hedef tarih';
  static const String noDateText = 'Seçilmedi';
  static const String clearDateTooltip = 'Tarihi temizle';
  static const String saveText = 'Kaydet';
  static const String projectsErrorText = 'Projeler yüklenemedi';
  static const String retryText = 'Tekrar dene';

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
  bool _titleTouched = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving && isTaskFormValid(title: _title.text, description: _description.text);

  /// The chosen project if it is still offered, otherwise "Projesiz".
  ProjectChoice _selected(List<ProjectChoice> choices) => choices.firstWhere(
    (c) => c.id != null && c.id == _projectId,
    orElse: () => ProjectChoice.none,
  );

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? TaskEditScreen.clampDate(ref.read(todayProvider)),
      firstDate: TaskEditScreen.minDate,
      lastDate: TaskEditScreen.maxDate,
    );
    if (!mounted || picked == null) return;
    setState(() => _dueDate = TaskEditScreen.clampDate(picked));
  }

  Future<void> _save(ProjectChoice project) async {
    if (!_canSave) return;
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
          ),
        );
    if (!mounted) return; // page closed while the request ran

    result.fold(
      (failure) {
        final projectGone =
            projectId != null && failure is ServerFailure && failure.statusCode == 404;
        setState(() {
          _saving = false;
          if (projectGone) _projectId = null;
        });
        if (projectGone) ref.invalidate(projectsListProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
        );
      },
      (_) {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRouter.planningPath);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsListProvider);
    final choices = projectChoices(projects.valueOrNull?.projects ?? const []);
    final selected = _selected(choices);
    final titleError = _titleTouched ? validateTaskTitle(_title.text) : null;

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(fallbackRoute: AppRouter.planningPath),
        title: const Text(TaskEditScreen.createTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
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
              _projectField(Theme.of(context), projects, choices, selected),
              const SizedBox(height: 24),
              _DueDateField(
                date: _dueDate,
                enabled: !_saving,
                onPick: _pickDate,
                onClear: () => setState(() => _dueDate = null),
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
            onPressed: _canSave ? () => _save(selected) : null,
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
  ) {
    final children = <Widget>[
      DropdownMenu<ProjectChoice>(
        // Rebuilt when the choices or the selection change so the field
        // shows the current selection.
        key: ValueKey('task-project-${selected.id}-${choices.length}'),
        initialSelection: selected,
        enabled: !_saving,
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

/// Optional due date: tap to pick (48 high), × to clear (48x48).
class _DueDateField extends StatelessWidget {
  const _DueDateField({
    required this.date,
    required this.enabled,
    required this.onPick,
    required this.onClear,
  });

  final DateTime? date;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final d = date;
    return InkWell(
      key: const ValueKey('task-due-date-button'),
      onTap: enabled ? onPick : null,
      borderRadius: BorderRadius.circular(4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InputDecorator(
          key: const ValueKey('task-due-date'),
          isEmpty: false,
          decoration: InputDecoration(
            labelText: TaskEditScreen.dueDateLabel,
            enabled: enabled,
            suffixIcon: d == null
                ? const Icon(Icons.calendar_today)
                : IconButton(
                    key: const ValueKey('task-due-date-clear'),
                    icon: const Icon(Icons.close),
                    tooltip: TaskEditScreen.clearDateTooltip,
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    onPressed: enabled ? onClear : null,
                  ),
          ),
          child: Text(
            d == null ? TaskEditScreen.noDateText : TaskEditScreen.formatDate(d),
            key: const ValueKey('task-due-date-text'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
