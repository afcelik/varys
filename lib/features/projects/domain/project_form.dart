import 'package:flutter/foundation.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/projects/domain/project.dart';

/// Pure helpers for the project form: validation (same limits as the
/// backend), the create body, the partial-update diff, Turkish status names
/// and the active-limit rule. No Flutter widgets, no I/O.

const int projectTitleMaxLength = 255;
const int projectDescriptionMaxLength = 2000;

const String projectTitleRequiredMessage = 'Başlık gerekli';
const String projectTitleTooLongMessage = 'Başlık en fazla 255 karakter olabilir';
const String projectDescriptionTooLongMessage = 'Açıklama en fazla 2000 karakter olabilir';
const String projectDatesOrderMessage = 'Hedef tarih başlangıç tarihinden önce olamaz';

/// Turkish names of the statuses, in list-section order.
const Map<ProjectStatus, String> projectStatusLabels = {
  ProjectStatus.active: 'Aktif',
  ProjectStatus.onHold: 'Beklemede',
  ProjectStatus.someday: 'İleride',
  ProjectStatus.completed: 'Tamamlanan',
};

/// Length in Unicode code points, as the backend (Python `len`) counts it:
/// an emoji such as 🚀 counts as one.
int _length(String s) => s.runes.length;

DateTime? _day(DateTime? d) => d == null ? null : DateTime(d.year, d.month, d.day);

String? validateProjectTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) return projectTitleRequiredMessage;
  if (_length(t) > projectTitleMaxLength) return projectTitleTooLongMessage;
  return null;
}

String? validateProjectDescription(String description) =>
    _length(description.trim()) > projectDescriptionMaxLength
    ? projectDescriptionTooLongMessage
    : null;

/// Error when [target] is before [start] (same day is allowed; either may be
/// absent), as the backend checks it.
String? validateProjectDates(DateTime? start, DateTime? target) {
  final s = _day(start);
  final t = _day(target);
  if (s != null && t != null && t.isBefore(s)) return projectDatesOrderMessage;
  return null;
}

bool isProjectFormValid({
  required String title,
  required String description,
  DateTime? startDate,
  DateTime? targetDate,
}) =>
    validateProjectTitle(title) == null &&
    validateProjectDescription(description) == null &&
    validateProjectDates(startDate, targetDate) == null;

/// Whether "Aktif" may be chosen. A project that is already active keeps it
/// (re-saving it does not count against the limit); otherwise there must be
/// a free active slot.
bool canChooseActive(ProjectLimits limits, {Project? editing}) {
  if (editing != null && editing.status == ProjectStatus.active) return true;
  return limits.activeCount < limits.maxActive;
}

/// Default status of a new project: active, or on hold when the limit is full.
ProjectStatus defaultNewProjectStatus(ProjectLimits limits) =>
    canChooseActive(limits) ? ProjectStatus.active : ProjectStatus.onHold;

/// Body of `POST /projects`. Title and description are trimmed; an empty
/// description and missing dates are sent as null.
@immutable
class ProjectDraft {
  const ProjectDraft({
    required this.title,
    this.description,
    required this.status,
    this.startDate,
    this.targetDate,
  });

  final String title;
  final String? description;
  final ProjectStatus status;
  final DateTime? startDate;
  final DateTime? targetDate;

  /// JSON-encodable body; dates are plain `YYYY-MM-DD` (no time, no zone).
  Map<String, dynamic> toBody() {
    final d = description?.trim();
    return {
      'title': title.trim(),
      'description': d == null || d.isEmpty ? null : d,
      'status': status.apiValue,
      'start_date': startDate == null ? null : formatDateForApi(startDate!),
      'target_date': targetDate == null ? null : formatDateForApi(targetDate!),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectDraft &&
      other.title == title &&
      other.description == description &&
      other.status == status &&
      other.startDate == startDate &&
      other.targetDate == targetDate;

  @override
  int get hashCode => Object.hash(title, description, status, startDate, targetDate);
}

/// Fields of a `PATCH /projects/{id}` body. Unset is not sent, clear sends
/// an explicit null (backend clears it), set sends the value. [title] and
/// [status] are never cleared (the backend rejects null for them).
@immutable
class ProjectChanges {
  const ProjectChanges({
    this.title = const PlanField.unset(),
    this.status = const PlanField.unset(),
    this.description = const PlanField.unset(),
    this.startDate = const PlanField.unset(),
    this.targetDate = const PlanField.unset(),
  });

  final PlanField<String> title;
  final PlanField<ProjectStatus> status;
  final PlanField<String> description;
  final PlanField<DateTime> startDate;
  final PlanField<DateTime> targetDate;

  bool get isEmpty =>
      title.isUnset &&
      status.isUnset &&
      description.isUnset &&
      startDate.isUnset &&
      targetDate.isUnset;

  /// JSON-encodable body: status as its wire string, dates as `YYYY-MM-DD`.
  Map<String, dynamic> toBody() {
    final body = <String, dynamic>{};
    title.writeTo(body, 'title');
    switch (status) {
      case PlanFieldUnset<ProjectStatus>():
        break;
      case PlanFieldSet<ProjectStatus>(:final value):
        body['status'] = value.apiValue;
      case PlanFieldClear<ProjectStatus>():
        body['status'] = null;
    }
    description.writeTo(body, 'description');
    _writeDate(body, 'start_date', startDate);
    _writeDate(body, 'target_date', targetDate);
    return body;
  }

  static void _writeDate(Map<String, dynamic> body, String key, PlanField<DateTime> field) {
    switch (field) {
      case PlanFieldUnset<DateTime>():
        break;
      case PlanFieldSet<DateTime>(:final value):
        body[key] = formatDateForApi(value);
      case PlanFieldClear<DateTime>():
        body[key] = null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ProjectChanges &&
      other.title == title &&
      other.status == status &&
      other.description == description &&
      other.startDate == startDate &&
      other.targetDate == targetDate;

  @override
  int get hashCode => Object.hash(title, status, description, startDate, targetDate);

  @override
  String toString() =>
      'ProjectChanges(title: $title, status: $status, '
      'description: $description, startDate: $startDate, targetDate: $targetDate)';
}

/// Diff of the form against [original]: only changed fields are set.
/// Title/description are compared trimmed; an emptied description and a
/// removed date become clear. Nothing changed → [ProjectChanges.isEmpty].
ProjectChanges computeProjectChanges(
  Project original, {
  required String title,
  required String description,
  required ProjectStatus status,
  DateTime? startDate,
  DateTime? targetDate,
}) {
  final t = title.trim();
  final d = description.trim();
  final originalDescription = original.description?.trim() ?? '';

  PlanField<DateTime> dateField(DateTime? before, DateTime? after) {
    final b = _day(before);
    final a = _day(after);
    if (a == b) return const PlanField.unset();
    return a == null ? const PlanField.clear() : PlanField.set(a);
  }

  return ProjectChanges(
    title: t == original.title ? const PlanField.unset() : PlanField.set(t),
    status: status == original.status ? const PlanField.unset() : PlanField.set(status),
    description: d == originalDescription
        ? const PlanField.unset()
        : (d.isEmpty ? const PlanField.clear() : PlanField.set(d)),
    startDate: dateField(original.startDate, startDate),
    targetDate: dateField(original.targetDate, targetDate),
  );
}
