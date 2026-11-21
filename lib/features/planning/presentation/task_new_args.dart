import 'package:flutter/foundation.dart';

/// Optional `extra` of `/tasks/new` (e.g. from the project detail page's
/// "Görev ekle"): the create form starts with project [projectId] chosen.
/// Without an extra the form starts with "Projesiz".
@immutable
class TaskNewArgs {
  const TaskNewArgs({required this.projectId});

  final int projectId;

  @override
  bool operator ==(Object other) => other is TaskNewArgs && other.projectId == projectId;

  @override
  int get hashCode => projectId.hashCode;

  @override
  String toString() => 'TaskNewArgs(projectId: $projectId)';
}
