import 'package:intl/intl.dart';
import 'package:varys/features/home/data/date_utils.dart';
import 'package:varys/features/planning/domain/task.dart';

/// A task that can be pulled into a day's plan.
/// [dayLabel] is set (e.g. "17 Kas") when the task is planned for another day.
class AddableTask {
  const AddableTask({required this.task, this.dayLabel});

  final Task task;
  final String? dayLabel;
}

/// Tasks that can be added to [planDay]: not done (todo, in_progress) and not
/// already planned for [planDay]. Unplanned tasks come first (input order),
/// then tasks planned for other days (by date, ascending).
///
/// Only the year-month-day of planned_date counts (via [dayOnly]); no
/// timezone conversion.
List<AddableTask> buildAddableTasks(List<Task> all, DateTime planDay) {
  final day = dayOnly(planDay);
  final unplanned = <AddableTask>[];
  final otherDay = <Task>[];

  for (final task in all) {
    if (task.status == TaskStatus.done) continue;
    final planned = task.plannedDate;
    if (planned == null) {
      unplanned.add(AddableTask(task: task));
    } else if (dayOnly(planned) != day) {
      otherDay.add(task);
    }
  }

  otherDay.sort((a, b) => dayOnly(a.plannedDate!).compareTo(dayOnly(b.plannedDate!)));
  final format = DateFormat('d MMM', 'tr_TR');
  return [
    ...unplanned,
    ...otherDay.map((t) => AddableTask(task: t, dayLabel: format.format(dayOnly(t.plannedDate!)))),
  ];
}

/// Turkish-aware lowercase: İ → i and I → ı, then the default lowercase.
String turkishLower(String s) => s.replaceAll('İ', 'i').replaceAll('I', 'ı').toLowerCase();

/// Case-insensitive (Turkish-aware) substring match. An empty query matches all.
bool matchesQuery(String title, String query) {
  final q = turkishLower(query.trim());
  if (q.isEmpty) return true;
  return turkishLower(title).contains(q);
}
