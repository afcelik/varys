import 'package:dartz/dartz.dart' hide Task, State;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/home/presentation/widgets/add_from_planning_sheet.dart';
import 'package:varys/features/planning/domain/task.dart';

/// Daily tasks card showing tasks for the current day with progress counter
class DailyTasksCard extends ConsumerWidget {
  const DailyTasksCard({super.key, required this.plan});

  final DailyPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = plan.tasks;

    // Separate incomplete and complete tasks
    final incompleteTasks = tasks.where((t) => t.status != TaskStatus.done).toList();
    final completeTasks = tasks.where((t) => t.status == TaskStatus.done).toList();
    final allTasks = [...incompleteTasks, ...completeTasks];

    // Progress counter: COMPLETED/TOTAL
    final completedCount = completeTasks.length;
    final totalCount = tasks.length;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with progress counter (COMPLETED/TOTAL)
            Row(
              children: [
                Icon(
                  Icons.checklist_outlined,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Bugün Yapılacaklar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                // Tooltip doubles as the semantics label. Tap target is pinned to
                // at least 48x48 on every platform (desktop themes default to
                // shrinkWrap + compact density, which would give 40x40 or less).
                IconButton(
                  onPressed: () => showAddFromPlanningSheet(context),
                  tooltip: AddFromPlanningSheet.title,
                  icon: const Icon(Icons.playlist_add),
                  visualDensity: VisualDensity.standard,
                  style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.padded),
                ),
                Text(
                  '$completedCount/$totalCount',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Task list or empty state
            if (tasks.isEmpty)
              _EmptyTasks()
            else
              _TaskList(
                tasks: allTasks,
                onToggle: (taskId, currentStatus) async {
                  final result = await ref.read(dailyPlanProvider.notifier).toggleTaskStatus(taskId, currentStatus);
                  result.fold(
                    (failure) => _showSnackbar(context, userMessage(failure)),
                    (_) {}, // Success - no action needed
                  );
                },
              ),

            const SizedBox(height: 16),

            // Add task field
            _AddTaskField(
              onSubmit: (title) async {
                final result = await ref.read(dailyPlanProvider.notifier).addTask(title);
                result.fold(
                  (failure) => _showSnackbar(context, userMessage(failure)),
                  (_) {}, // Success - field clears in widget
                );
                return result;
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}

class _TaskList extends ConsumerWidget {
  final List<Task> tasks;
  final Future<void> Function(int taskId, TaskStatus currentStatus) onToggle;

  const _TaskList({required this.tasks, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: tasks.map((task) => _TaskRow(
        key: ValueKey(task.id), // ValueKey for proper reconciliation
        task: task,
        onToggle: onToggle,
      )).toList(),
    );
  }
}

class _TaskRow extends ConsumerStatefulWidget {
  final Task task;
  final Future<void> Function(int taskId, TaskStatus currentStatus) onToggle;

  const _TaskRow({super.key, required this.task, required this.onToggle});

  @override
  ConsumerState<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends ConsumerState<_TaskRow> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = widget.task.status == TaskStatus.done;
    final isTemp = widget.task.id < 0; // Temporary negative ID

    return Opacity(
      opacity: isDone ? 0.6 : 1.0,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Checkbox(
          value: isDone,
          onChanged: (isTemp || _isLoading) ? null : (_) async {
            setState(() => _isLoading = true);
            await widget.onToggle(widget.task.id, widget.task.status);
            if (mounted) setState(() => _isLoading = false);
          },
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        title: Text(
          widget.task.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            decoration: isDone ? TextDecoration.lineThrough : null,
            color: isDone ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
          ),
        ),
        // No onTap - removed empty callback
      ),
    );
  }
}

class _AddTaskField extends StatefulWidget {
  final Future<Either<Failure, void>> Function(String title) onSubmit;

  const _AddTaskField({required this.onSubmit});

  @override
  State<_AddTaskField> createState() => _AddTaskFieldState();
}

class _AddTaskFieldState extends State<_AddTaskField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isSubmitting = false;
  String? _lastSubmittedTitle; // Store text if submission fails and field is empty

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final title = _controller.text.trim();
    if (title.isEmpty || _isSubmitting) return;

    _lastSubmittedTitle = title;
    _controller.clear();
    setState(() => _isSubmitting = true);

    final result = await widget.onSubmit(title);

    if (mounted) {
      setState(() => _isSubmitting = false);

      result.fold(
        (failure) {
          // On failure, if field is empty, restore the typed text
          if (_controller.text.isEmpty) {
            _controller.text = _lastSubmittedTitle ?? '';
          }
          // Snackbar shown by caller
        },
        (_) {
          // Success - field already cleared, retain focus for sequential additions
          _lastSubmittedTitle = null;
          _focusNode.requestFocus();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      onSubmitted: (_) => _handleSubmit(),
      decoration: InputDecoration(
        hintText: 'Yeni görev ekle...',
        hintStyle: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        // NO loading indicator in field
        suffixIcon: null,
      ),
    );
  }
}

class _EmptyTasks extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'Bugün için görev yok',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}