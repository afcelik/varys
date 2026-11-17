import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/focus_candidates.dart';
import 'package:varys/features/planning/domain/task.dart';

/// Real backend JSON: tasks 1 todo, 2 in_progress, 3 done, 4 todo, 5 done.
List<Task> _fixtureTasks() {
  final json = jsonDecode(File('test/fixtures/daily_plan_with_tasks.json').readAsStringSync())
      as Map<String, dynamic>;
  return (json['tasks'] as List).map((t) => Task.fromJson(t as Map<String, dynamic>)).toList();
}

Task _byId(List<Task> tasks, int id) => tasks.firstWhere((t) => t.id == id);

DailyPlan _plan(List<Task> tasks, {Task? main, Task? side}) =>
    DailyPlan(planDate: DateTime(2026, 11, 1), mainFocus: main, sideFocus: side, tasks: tasks);

void main() {
  late List<Task> tasks;

  setUp(() => tasks = _fixtureTasks());

  List<int> ids(List<FocusCandidate> c) => c.map((e) => e.task.id).toList();
  FocusCandidate byTask(List<FocusCandidate> c, int id) => c.firstWhere((e) => e.task.id == id);

  test('done tasks are excluded, plan order is kept', () {
    for (final slot in FocusSlot.values) {
      final result = buildFocusCandidates(_plan(tasks), slot);
      expect(ids(result), [1, 2, 4]);
      expect(result.every((c) => c.state == FocusCandidateState.selectable), isTrue);
      expect(result.every((c) => c.label == null), isTrue);
    }
  });

  test('order follows the plan list, not ids', () {
    final reordered = [_byId(tasks, 4), _byId(tasks, 1), _byId(tasks, 2)];
    expect(ids(buildFocusCandidates(_plan(reordered), FocusSlot.main)), [4, 1, 2]);
  });

  test('main slot: side focus is blockedByOther with "İkincil odak"', () {
    final result =
        buildFocusCandidates(_plan(tasks, side: _byId(tasks, 2)), FocusSlot.main);
    final c = byTask(result, 2);
    expect(c.state, FocusCandidateState.blockedByOther);
    expect(c.label, 'İkincil odak');
    expect(byTask(result, 1).state, FocusCandidateState.selectable);
  });

  test('side slot: main focus is blockedByOther with "Ana odak"', () {
    final result =
        buildFocusCandidates(_plan(tasks, main: _byId(tasks, 1)), FocusSlot.side);
    final c = byTask(result, 1);
    expect(c.state, FocusCandidateState.blockedByOther);
    expect(c.label, 'Ana odak');
    expect(byTask(result, 4).state, FocusCandidateState.selectable);
  });

  test("this slot's focus is selected (no label)", () {
    final plan = _plan(tasks, main: _byId(tasks, 1), side: _byId(tasks, 4));
    final mainResult = buildFocusCandidates(plan, FocusSlot.main);
    expect(byTask(mainResult, 1).state, FocusCandidateState.selected);
    expect(byTask(mainResult, 1).label, isNull);
    expect(byTask(mainResult, 4).state, FocusCandidateState.blockedByOther);

    final sideResult = buildFocusCandidates(plan, FocusSlot.side);
    expect(byTask(sideResult, 4).state, FocusCandidateState.selected);
    expect(byTask(sideResult, 1).state, FocusCandidateState.blockedByOther);
  });

  test('negative id is pending with "Ekleniyor…"', () {
    final temp = _byId(tasks, 1).copyWith(id: -1, title: 'Geçici görev');
    final result = buildFocusCandidates(_plan([temp, ...tasks]), FocusSlot.main);
    expect(ids(result), [-1, 1, 2, 4]);
    expect(result.first.state, FocusCandidateState.pending);
    expect(result.first.label, 'Ekleniyor…');
  });

  test('focus not in plan.tasks is simply absent; others stay selectable', () {
    final moved = _byId(tasks, 1).copyWith(id: 99, title: 'Başka güne taşındı');
    final result = buildFocusCandidates(_plan(tasks, main: moved), FocusSlot.main);
    expect(ids(result), [1, 2, 4]);
    expect(result.every((c) => c.state == FocusCandidateState.selectable), isTrue);
  });

  test('empty task list gives an empty list', () {
    expect(buildFocusCandidates(_plan(const []), FocusSlot.main), isEmpty);
    expect(buildFocusCandidates(_plan(const []), FocusSlot.side), isEmpty);
  });

  test('all tasks done gives an empty list', () {
    final done = tasks.where((t) => t.status == TaskStatus.done).toList();
    expect(buildFocusCandidates(_plan(done, main: done.first), FocusSlot.side), isEmpty);
  });
}
