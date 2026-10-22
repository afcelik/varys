import 'package:freezed_annotation/freezed_annotation.dart';

part 'task.freezed.dart';
part 'task.g.dart';

/// Task entity representing a single task in the planning feature.
@freezed
abstract class Task with _$Task {
  const factory Task({
    required String id,
    required String title,
    required String description,
    required bool isCompleted,
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? completedAt,
  }) = _Task;

  factory Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);
}

/// Extension for creating new tasks with default values
extension TaskCreation on Task {
  static Task create({
    required String title,
    required String description,
  }) {
    final now = DateTime.now();
    return Task(
      id: '',
      title: title,
      description: description,
      isCompleted: false,
      createdAt: now,
      updatedAt: now,
      completedAt: null,
    );
  }
}

/// Task filter options for the planning screen
enum TaskFilter {
  all(label: 'Tümü'),
  inProgress(label: 'Devam Ediyor'),
  completed(label: 'Tamamlandı');

  const TaskFilter({required this.label});
  final String label;
}