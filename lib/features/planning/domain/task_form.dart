import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';

/// Pure helpers for the task form and the Planning row: validation (same
/// limits as the backend), project choices, the new-task value and the row's
/// meta line. No Flutter widgets, no I/O.

const int taskTitleMaxLength = 255;
const int taskDescriptionMaxLength = 2000;

const String taskTitleRequiredMessage = 'Başlık gerekli';
const String taskTitleTooLongMessage = 'Başlık en fazla 255 karakter olabilir';
const String taskDescriptionTooLongMessage = 'Açıklama en fazla 2000 karakter olabilir';

/// Label of the "no project" choice; always the first choice.
const String noProjectLabel = 'Projesiz';

/// Length in Unicode code points, as the backend (Python `len`) counts it.
int _length(String s) => s.runes.length;

String? validateTaskTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) return taskTitleRequiredMessage;
  if (_length(t) > taskTitleMaxLength) return taskTitleTooLongMessage;
  return null;
}

String? validateTaskDescription(String description) =>
    _length(description.trim()) > taskDescriptionMaxLength ? taskDescriptionTooLongMessage : null;

bool isTaskFormValid({required String title, required String description}) =>
    validateTaskTitle(title) == null && validateTaskDescription(description) == null;

/// One entry of the project dropdown. [id] null is "Projesiz".
@immutable
class ProjectChoice {
  const ProjectChoice({required this.id, required this.label, this.statusLabel});

  final int? id;
  final String label;

  /// Turkish status name ("Aktif", "Beklemede", "İleride"); null for Projesiz.
  final String? statusLabel;

  static const ProjectChoice none = ProjectChoice(id: null, label: noProjectLabel);

  @override
  bool operator ==(Object other) =>
      other is ProjectChoice &&
      other.id == id &&
      other.label == label &&
      other.statusLabel == statusLabel;

  @override
  int get hashCode => Object.hash(id, label, statusLabel);
}

/// "Projesiz" first, then active, on-hold and someday projects (in
/// [projectStatusLabels] order, list order inside a status). Completed
/// projects are not offered, except [keepProjectId] (the edited task's
/// current project), which is appended last with its "Tamamlanan" label.
List<ProjectChoice> projectChoices(List<Project> projects, {int? keepProjectId}) => [
  ProjectChoice.none,
  for (final MapEntry(key: status, value: label) in projectStatusLabels.entries)
    for (final p in projects)
      if (p.status == status && (status != ProjectStatus.completed || p.id == keepProjectId))
        ProjectChoice(id: p.id, label: p.title, statusLabel: label),
];

/// The task sent by the create form. Title and description are trimmed; an
/// empty description is null (not sent); [dueDate] keeps only its day.
/// `planned_date` is never set here (Home manages it).
Task buildNewTask({
  required String title,
  required String description,
  int? projectId,
  DateTime? dueDate,
  DateTime? now,
}) {
  final d = description.trim();
  final at = now ?? DateTime.now();
  return Task(
    id: 0,
    title: title.trim(),
    description: d.isEmpty ? null : d,
    status: TaskStatus.todo,
    createdAt: at,
    updatedAt: at,
    dueDate: dueDate == null ? null : DateTime(dueDate.year, dueDate.month, dueDate.day),
    projectId: projectId,
  );
}

/// Short Turkish day, e.g. "21 Kas".
String formatTaskDay(DateTime day) => DateFormat('d MMM', 'tr_TR').format(day);

/// id → title of every project, all statuses included (a task linked to a
/// completed project still shows its name).
Map<int, String> projectNamesById(List<Project> projects) => {
  for (final p in projects) p.id: p.title,
};

/// Meta line of a Planning row: project name (if known) and due day (if
/// any), joined by " · ". Null when neither is present, so the row looks as
/// before. An unknown project id (deleted, not loaded yet) shows nothing.
String? taskMetaLine(Task task, Map<int, String> projectNames) {
  final id = task.projectId;
  final name = id == null ? null : projectNames[id];
  final due = task.dueDate;
  final parts = [?name, if (due != null) formatTaskDay(due)];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Current values of the edit form.
///
/// [projectResolved] is false while the project list is not loaded (loading
/// or failed) and the task has a project: the form cannot tell yet whether
/// that project still exists, so the project is never sent.
@immutable
class TaskFormValues {
  const TaskFormValues({
    required this.title,
    required this.description,
    required this.projectId,
    this.projectResolved = true,
    this.dueDate,
    this.plannedDate,
  });

  final String title;
  final String description;
  final int? projectId;
  final bool projectResolved;
  final DateTime? dueDate;
  final DateTime? plannedDate;
}

/// The fields a PATCH sends: only what changed. [title] null is "not sent"
/// (the backend rejects a null title); every other field is explicit.
@immutable
class TaskChanges {
  const TaskChanges({
    this.title,
    this.description = const PlanField.unset(),
    this.projectId = const PlanField.unset(),
    this.dueDate = const PlanField.unset(),
    this.plannedDate = const PlanField.unset(),
  });

  final String? title;
  final PlanField<String> description;
  final PlanField<int> projectId;
  final PlanField<DateTime> dueDate;
  final PlanField<DateTime> plannedDate;

  bool get isEmpty =>
      title == null &&
      description.isUnset &&
      projectId.isUnset &&
      dueDate.isUnset &&
      plannedDate.isUnset;

  @override
  bool operator ==(Object other) =>
      other is TaskChanges &&
      other.title == title &&
      other.description == description &&
      other.projectId == projectId &&
      other.dueDate == dueDate &&
      other.plannedDate == plannedDate;

  @override
  int get hashCode => Object.hash(title, description, projectId, dueDate, plannedDate);

  @override
  String toString() =>
      'TaskChanges(title: $title, description: $description, projectId: $projectId, '
      'dueDate: $dueDate, plannedDate: $plannedDate)';
}

DateTime? _day(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day);

/// Day field change: compared by day only (the time part is ignored).
PlanField<DateTime> _dayChange(DateTime? original, DateTime? next) {
  final a = _day(original);
  final b = _day(next);
  if (a == b) return const PlanField.unset();
  return b == null ? const PlanField.clear() : PlanField.set(b);
}

/// What the edit form changed compared to [original]. Title and description
/// are trimmed; an empty description equals "none" (null) and clears it;
/// the project is unset while not resolved. Validity is checked separately
/// ([isTaskFormValid]).
TaskChanges computeTaskChanges(Task original, TaskFormValues form) {
  final title = form.title.trim();
  final description = form.description.trim();
  final oldDescription = original.description?.trim() ?? '';

  final PlanField<String> descriptionChange;
  if (description == oldDescription) {
    descriptionChange = const PlanField.unset();
  } else if (description.isEmpty) {
    descriptionChange = const PlanField.clear();
  } else {
    descriptionChange = PlanField.set(description);
  }

  final PlanField<int> projectChange;
  if (!form.projectResolved || form.projectId == original.projectId) {
    projectChange = const PlanField.unset();
  } else if (form.projectId == null) {
    projectChange = const PlanField.clear();
  } else {
    projectChange = PlanField.set(form.projectId!);
  }

  return TaskChanges(
    title: title == original.title ? null : title,
    description: descriptionChange,
    projectId: projectChange,
    dueDate: _dayChange(original.dueDate, form.dueDate),
    plannedDate: _dayChange(original.plannedDate, form.plannedDate),
  );
}
