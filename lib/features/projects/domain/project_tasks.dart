import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';

/// Tasks of one project, split for the project detail page.
typedef ProjectTaskGroups = ({List<Task> pending, List<Task> done});

/// The tasks of project [projectId] from [tasks] (the full, unfiltered list):
/// deleted tasks are left out; [ProjectTaskGroups.pending] holds every task
/// that is not done, [ProjectTaskGroups.done] the done ones. Both are newest
/// first (`created_at` descending, then id descending for equal times).
ProjectTaskGroups projectTaskGroups(List<Task> tasks, int projectId) {
  final mine = tasks.where((t) => t.projectId == projectId && t.deletedAt == null).toList()
    ..sort((a, b) {
      final byCreated = b.createdAt.compareTo(a.createdAt);
      return byCreated != 0 ? byCreated : b.id.compareTo(a.id);
    });
  return (
    pending: mine.where((t) => t.status != TaskStatus.done).toList(),
    done: mine.where((t) => t.status == TaskStatus.done).toList(),
  );
}

/// Short Turkish day, e.g. "21 Kas" (same as intl's tr `d MMM`), from a fixed
/// table so it needs no locale data initialisation. A plain calendar day.
String shortTrDay(DateTime day) => '${day.day} ${trMonthNames[day.month - 1].substring(0, 3)}';
