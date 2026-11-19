import 'package:freezed_annotation/freezed_annotation.dart';

part 'task.freezed.dart';
part 'task.g.dart';

/// Task status enumeration matching backend values.
enum TaskStatus {
  @JsonValue('todo')
  todo,
  @JsonValue('in_progress')
  inProgress,
  @JsonValue('done')
  done,
}

/// JSON converter for task-day fields (`planned_date`, `due_date`).
///
/// The backend sends naive datetimes (`YYYY-MM-DDT00:00:00`, no suffix).
/// Assumption: if a timezone suffix (`Z`, `+03:00`, `-05:00`) ever arrives,
/// the value is read as a WALL-CLOCK day/time, NOT as an instant: the suffix
/// is stripped and no UTC/local conversion happens, so the day never shifts.
/// The backend sends no suffix today; this is a defensive measure.
class TaskDateConverter implements JsonConverter<DateTime?, String?> {
  const TaskDateConverter();

  static final _tzSuffix = RegExp(r'(Z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

  @override
  DateTime? fromJson(String? json) {
    if (json == null) return null;
    final raw = json.trim();
    // Only strip a suffix after the time part ("T..."); a bare
    // "YYYY-MM-DD" must keep its "-DD".
    final tIndex = raw.indexOf(RegExp('[Tt ]'));
    if (tIndex == -1) return DateTime.parse(raw);
    final time = raw.substring(tIndex + 1).replaceFirst(_tzSuffix, '');
    return DateTime.parse('${raw.substring(0, tIndex)}T$time');
  }

  /// Yalnızca model gidiş-dönüşü içindir; istek gövdesinde KULLANMA, tarihler
  /// için plannedDateForApi kullan.
  @override
  String? toJson(DateTime? object) => object?.toIso8601String();
}

/// Task entity representing a single task in the planning feature.
@freezed
abstract class Task with _$Task {
  const factory Task({
    required int id,
    required String title,
    String? description,
    required TaskStatus status,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
    @TaskDateConverter() DateTime? plannedDate,
    @TaskDateConverter() DateTime? dueDate,
    /// Linked project (`project_id`); null when the task has no project.
    int? projectId,
  }) = _Task;

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
}

/// Extension for creating new tasks with default values
extension TaskCreation on Task {
  static Task create({
    required String title,
    String? description,
    TaskStatus status = TaskStatus.todo,
    DateTime? plannedDate,
    DateTime? dueDate,
    int id = 0, // Allow explicit ID for temporary tasks (e.g., -1, -2, -3)
  }) {
    final now = DateTime.now();
    return Task(
      id: id,
      title: title,
      description: description,
      status: status,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
      plannedDate: plannedDate,
      dueDate: dueDate,
    );
  }
}

/// Extension to maintain backward compatibility with UI code using isCompleted
extension TaskStatusExtension on Task {
  bool get isCompleted => status == TaskStatus.done;
}

/// Task filter options for the planning screen
enum TaskFilter {
  all(label: 'Tümü'),
  inProgress(label: 'Devam Ediyor'),
  completed(label: 'Tamamlandı');

  const TaskFilter({required this.label});
  final String label;
}