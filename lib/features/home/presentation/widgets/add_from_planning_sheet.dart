import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/features/home/domain/addable_tasks.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';

/// Opens the "Planlamadan ekle" bottom sheet for the loaded daily plan.
Future<void> showAddFromPlanningSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const AddFromPlanningSheet(),
  );
}

/// Bottom sheet listing tasks that can be pulled into the plan's day
/// (multi-select + search). Closes when every selected task is added; on a
/// partial failure it stays open, keeps the failed tasks selected and
/// reloads the list from the server.
class AddFromPlanningSheet extends ConsumerStatefulWidget {
  const AddFromPlanningSheet({super.key});

  static const String title = 'Planlamadan ekle';
  static const String emptyMessage = 'Eklenecek görev yok';
  static const String noMatchMessage = 'Eşleşen görev yok';
  static const String retryLabel = 'Tekrar dene';
  static const String searchHint = 'Görev ara';

  static String addLabel(int n) => 'Ekle ($n)';
  static String partialFailureMessage(int n, String reason) => '$n görev eklenemedi. $reason';

  @override
  ConsumerState<AddFromPlanningSheet> createState() => _AddFromPlanningSheetState();
}

class _AddFromPlanningSheetState extends ConsumerState<AddFromPlanningSheet> {
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  List<Task>? _tasks;
  Object? _loadError;
  bool _loading = true;
  bool _submitting = false;
  String _query = '';
  Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Loads all tasks from the server. A [silent] reload keeps the current
  /// list on screen (no spinner) and keeps it if the reload fails.
  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    Object? error;
    List<Task>? tasks;
    try {
      final repository = await ref.read(taskRepositoryProvider.future);
      final result = await repository.getTasks();
      result.fold((f) => error = f, (t) => tasks = t);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (tasks != null) {
        _tasks = tasks;
        _loadError = null;
      } else if (!silent || _tasks == null) {
        _loadError = error;
      }
    });
  }

  Future<void> _submit(List<int> ids) async {
    if (_submitting || ids.isEmpty) return;
    setState(() => _submitting = true);

    final notifier = ref.read(dailyPlanProvider.notifier);
    final result = await notifier.addTasksToDay(ids);
    if (!mounted) return;

    await result.fold(
      (failure) async {
        setState(() => _submitting = false);
        _showSnackbar(userMessage(failure));
      },
      (r) async {
        if (r.failed.isEmpty) {
          Navigator.of(context).pop();
          return;
        }
        final succeeded = r.succeeded.toSet();
        setState(() {
          _submitting = false;
          _selected = r.failed.toSet();
          _tasks = _tasks?.where((t) => !succeeded.contains(t.id)).toList();
        });
        _showSnackbar(
          AddFromPlanningSheet.partialFailureMessage(r.failed.length, userMessage(r.firstFailure!)),
        );
        await _load(silent: true);
      },
    );
  }

  void _showSnackbar(String message) {
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planDate = ref.watch(dailyPlanProvider).value?.planDate;
    final tasks = _tasks;
    final addable = (tasks == null || planDate == null)
        ? const <AddableTask>[]
        : buildAddableTasks(tasks, planDate);
    // Only selections still in the loaded list count (and are sent).
    final effective = addable.map((a) => a.task.id).where(_selected.contains).toList();
    final visible = addable.where((a) => matchesQuery(a.task.title, _query)).toList();

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: ScaffoldMessenger(
        key: _messengerKey,
        // The "Ekle (n)" button lives in bottomNavigationBar so floating
        // snackbars sit above it (never cover it). The keyboard inset is
        // applied to that bar, which also shrinks the list above it.
        child: Scaffold(
          backgroundColor: Colors.transparent,
          resizeToAvoidBottomInset: false,
          bottomNavigationBar: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
            child: FilledButton(
              onPressed: (effective.isEmpty || _submitting) ? null : () => _submit(effective),
              child: Text(AddFromPlanningSheet.addLabel(effective.length)),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AddFromPlanningSheet.title,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: AddFromPlanningSheet.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(child: _buildBody(theme, addable, visible)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, List<AddableTask> addable, List<AddableTask> visible) {
    if (_loading && _tasks == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _loadError;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(userMessage(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _load,
              child: const Text(AddFromPlanningSheet.retryLabel),
            ),
          ],
        ),
      );
    }
    if (addable.isEmpty) {
      return _centeredHint(theme, AddFromPlanningSheet.emptyMessage);
    }
    if (visible.isEmpty) {
      return _centeredHint(theme, AddFromPlanningSheet.noMatchMessage);
    }
    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final item = visible[index];
        final id = item.task.id;
        return CheckboxListTile(
          key: ValueKey(id),
          value: _selected.contains(id),
          onChanged: _submitting
              ? null
              : (checked) => setState(() {
                  if (checked ?? false) {
                    _selected = {..._selected, id};
                  } else {
                    _selected = {..._selected}..remove(id);
                  }
                }),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(item.task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: item.dayLabel == null ? null : Text(item.dayLabel!),
        );
      },
    );
  }

  Widget _centeredHint(ThemeData theme, String text) => Center(
    child: Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    ),
  );
}
