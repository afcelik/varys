import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:varys/features/planning/domain/task.dart';

part 'project.freezed.dart';
part 'project.g.dart';

/// Project lifecycle status matching backend values. Only [active] counts
/// toward the active project limit.
enum ProjectStatus {
  @JsonValue('active')
  active,
  @JsonValue('on_hold')
  onHold,
  @JsonValue('someday')
  someday,
  @JsonValue('completed')
  completed,
}

/// A project as returned by `GET /projects` (backend ProjectRead), with
/// progress over its non-deleted tasks.
///
/// [startDate] and [targetDate] are plain calendar dates (`YYYY-MM-DD`),
/// read as a local day with no time zone conversion ([TaskDateConverter]).
/// [progressPercent] is null when the project has no tasks.
@freezed
abstract class Project with _$Project {
  const factory Project({
    required int id,
    required String title,
    String? description,
    required ProjectStatus status,
    @TaskDateConverter() DateTime? startDate,
    @TaskDateConverter() DateTime? targetDate,
    required DateTime createdAt,
    required DateTime updatedAt,
    required int totalTasks,
    required int doneTasks,
    int? progressPercent,
  }) = _Project;

  factory Project.fromJson(Map<String, dynamic> json) => _$ProjectFromJson(json);
}

/// Active project limit and current usage (`GET /projects/limits`).
@freezed
abstract class ProjectLimits with _$ProjectLimits {
  const factory ProjectLimits({
    required int maxActive,
    required int activeCount,
  }) = _ProjectLimits;

  factory ProjectLimits.fromJson(Map<String, dynamic> json) => _$ProjectLimitsFromJson(json);
}
