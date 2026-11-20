import 'package:varys/features/planning/domain/task.dart';

/// Eisenhower matrix: pure helpers, no Flutter widgets, no I/O.
///
/// A quadrant comes only from the two task flags (`is_important`,
/// `is_urgent`). Quadrants are told apart by their Turkish name, never by
/// colour alone.
enum EisenhowerQuadrant {
  doNow(title: 'Hemen yap', subtitle: 'Önemli ve acil', pathSegment: 'do-now'),
  schedule(title: 'Planla', subtitle: 'Önemli, acil değil', pathSegment: 'schedule'),
  delegate(title: 'Devret ya da kısalt', subtitle: 'Acil, önemli değil', pathSegment: 'delegate'),
  eliminate(title: 'Ele ya da ertele', subtitle: 'Ne önemli ne acil', pathSegment: 'eliminate');

  const EisenhowerQuadrant({
    required this.title,
    required this.subtitle,
    required this.pathSegment,
  });

  final String title;
  final String subtitle;

  /// The `:quadrant` part of `/eisenhower/:quadrant`.
  final String pathSegment;

  /// The quadrant for a route parameter; null for anything unknown.
  static EisenhowerQuadrant? fromPathSegment(String? segment) {
    for (final q in values) {
      if (q.pathSegment == segment) return q;
    }
    return null;
  }
}

EisenhowerQuadrant quadrantOf(Task task) => switch ((task.isImportant, task.isUrgent)) {
  (true, true) => EisenhowerQuadrant.doNow,
  (true, false) => EisenhowerQuadrant.schedule,
  (false, true) => EisenhowerQuadrant.delegate,
  (false, false) => EisenhowerQuadrant.eliminate,
};

/// Open tasks per quadrant. Every quadrant is a key (an empty list when it
/// has no task). Done and deleted tasks are left out. Inside a quadrant the
/// newest comes first: `createdAt` descending, then `id` descending.
Map<EisenhowerQuadrant, List<Task>> groupByQuadrant(List<Task> tasks) {
  final groups = {for (final q in EisenhowerQuadrant.values) q: <Task>[]};
  for (final task in tasks) {
    if (task.status == TaskStatus.done || task.deletedAt != null) continue;
    groups[quadrantOf(task)]!.add(task);
  }
  for (final list in groups.values) {
    list.sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  }
  return groups;
}
