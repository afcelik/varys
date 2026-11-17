import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/planning/domain/task.dart';

/// Which focus slot of the daily plan a selection is for.
enum FocusSlot { main, side }

/// How a task can be used when choosing the focus for a slot.
enum FocusCandidateState {
  /// Can be chosen for this slot.
  selectable,

  /// Already this slot's focus (choosing it changes nothing).
  selected,

  /// The other slot's focus; cannot be chosen here.
  blockedByOther,

  /// Temporary task (negative id) not yet saved on the server.
  pending,
}

/// A task from today's plan, with its state for one focus slot.
class FocusCandidate {
  const FocusCandidate({required this.task, required this.state, this.label});

  final Task task;
  final FocusCandidateState state;

  /// Shown next to non-selectable rows ("Ana odak", "İkincil odak", "Ekleniyor…").
  final String? label;

  static const String mainFocusLabel = 'Ana odak';
  static const String sideFocusLabel = 'İkincil odak';
  static const String pendingLabel = 'Ekleniyor…';
}

/// Focus candidates for [slot] from the plan's "Bugün Yapılacaklar" tasks.
///
/// Only unfinished tasks (todo, in_progress) are listed, in plan order.
/// Precedence: this slot's focus → selected; the other slot's focus →
/// blockedByOther; negative id → pending; otherwise selectable.
List<FocusCandidate> buildFocusCandidates(DailyPlan plan, FocusSlot slot) {
  final ownId = slot == FocusSlot.main ? plan.mainFocus?.id : plan.sideFocus?.id;
  final otherId = slot == FocusSlot.main ? plan.sideFocus?.id : plan.mainFocus?.id;
  final otherLabel =
      slot == FocusSlot.main ? FocusCandidate.sideFocusLabel : FocusCandidate.mainFocusLabel;

  final result = <FocusCandidate>[];
  for (final task in plan.tasks) {
    if (task.status == TaskStatus.done) continue;
    if (ownId != null && task.id == ownId) {
      result.add(FocusCandidate(task: task, state: FocusCandidateState.selected));
    } else if (otherId != null && task.id == otherId) {
      result.add(FocusCandidate(
          task: task, state: FocusCandidateState.blockedByOther, label: otherLabel));
    } else if (task.id < 0) {
      result.add(FocusCandidate(
          task: task, state: FocusCandidateState.pending, label: FocusCandidate.pendingLabel));
    } else {
      result.add(FocusCandidate(task: task, state: FocusCandidateState.selectable));
    }
  }
  return result;
}
