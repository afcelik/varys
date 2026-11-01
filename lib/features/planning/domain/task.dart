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
    DateTime? plannedDate,
    DateTime? dueDate,
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
  }) {
    final now = DateTime.now();
    return Task(
      id: 0,
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