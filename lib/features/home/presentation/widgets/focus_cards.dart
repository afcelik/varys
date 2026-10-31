import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/planning/domain/task.dart';

/// Main focus card - large card with accent border
class MainFocusCard extends ConsumerWidget {
  const MainFocusCard({super.key, required this.plan});

  final DailyPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mainFocus = plan.mainFocus;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.primary,
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Günün Ana Odak',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                if (mainFocus != null)
                  TextButton.icon(
                    onPressed: () => _clearFocus(ref),
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Temizle'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (mainFocus != null) ...[
              _FocusTaskTile(task: mainFocus),
            ] else ...[
              _EmptyFocusTile(
                onTap: () => _selectFocus(context, ref),
                label: 'Ana odak seç',
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _selectFocus(BuildContext context, WidgetRef ref) {
    context.push(AppRouter.focusTaskSelectionPath).then((result) {
      if (result != null && result is Task) {
        ref.read(dailyPlanProvider.notifier).updatePlan(
              mainFocusTaskId: int.tryParse(result.id),
            );
      }
      // If null (user backed out), do nothing - no change
    });
  }

  void _clearFocus(WidgetRef ref) {
    ref.read(dailyPlanProvider.notifier).clearMainFocus();
  }
}

/// Side focus card - smaller version
class SideFocusCard extends ConsumerWidget {
  const SideFocusCard({super.key, required this.plan});

  final DailyPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sideFocus = plan.sideFocus;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 20,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Text(
                  'İkincil Odak',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary.withValues(alpha: 0.8),
                  ),
                ),
                const Spacer(),
                if (sideFocus != null)
                  TextButton.icon(
                    onPressed: () => _clearFocus(ref),
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Temizle'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (sideFocus != null) ...[
              _FocusTaskTile(task: sideFocus, compact: true),
            ] else ...[
              _EmptyFocusTile(
                onTap: () => _selectFocus(context, ref),
                label: 'İkincil odak seç',
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _selectFocus(BuildContext context, WidgetRef ref) {
    context.push(AppRouter.focusTaskSelectionPath).then((result) {
      if (result != null && result is Task) {
        ref.read(dailyPlanProvider.notifier).updatePlan(
              sideFocusTaskId: int.tryParse(result.id),
            );
      }
    });
  }

  void _clearFocus(WidgetRef ref) {
    ref.read(dailyPlanProvider.notifier).clearSideFocus();
  }
}

/// Tile showing a focused task
class _FocusTaskTile extends StatelessWidget {
  const _FocusTaskTile({required this.task, this.compact = false});

  final Task task;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = task.isCompleted
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            task.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: statusColor,
            size: compact ? 20 : 24,
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: task.isCompleted
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                    decoration: task.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!compact && task.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    task.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  task.isCompleted ? 'Tamamlandı' : 'Devam ediyor',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tile shown when no focus is selected
class _EmptyFocusTile extends StatelessWidget {
  const _EmptyFocusTile({
    required this.onTap,
    required this.label,
    this.compact = false,
  });

  final VoidCallback onTap;
  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(compact ? 12 : 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.add_circle_outline,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              size: compact ? 20 : 24,
            ),
            SizedBox(width: compact ? 10 : 12),
            Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}