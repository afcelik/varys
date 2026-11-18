import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/presentation/routines_day_notifier.dart';

/// Home card with today's routines: "completed/total" counter, checkboxes,
/// streaks. Loading and errors stay inside this card; the rest of Home is
/// unaffected.
class RoutinesCard extends ConsumerWidget {
  const RoutinesCard({super.key});

  static const String title = 'Rutinler';
  static const String emptyText = 'Bugün için rutin yok';
  static const String moreText = 'Daha fazla';
  static const String retryText = 'Tekrar dene';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final value = ref.watch(todayRoutinesProvider);

    final Widget body;
    String? counter;
    if (value.hasError && !value.isLoading) {
      body = _RoutinesCardError(
        message: userMessage(value.error!),
        onRetry: () => ref.invalidate(routinesForDayProvider(today)),
      );
    } else if (value.hasValue) {
      final items = value.requireValue;
      final open = items.where((i) => !i.completed);
      final done = items.where((i) => i.completed).toList();
      counter = '${done.length}/${items.length}';
      body = items.isEmpty
          ? const _EmptyRoutines()
          : Column(
              children: [
                for (final item in [...open, ...done])
                  _RoutineRow(key: ValueKey(item.id), item: item, day: today),
              ],
            );
    } else {
      body = const _RoutinesCardSkeleton();
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.repeat, size: 24, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                if (counter != null)
                  Text(
                    counter,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            body,
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => context.push(AppRouter.routinesPath),
                child: const Text(moreText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineRow extends ConsumerStatefulWidget {
  const _RoutineRow({super.key, required this.item, required this.day});

  final RoutineDayItem item;
  final DateTime day;

  @override
  ConsumerState<_RoutineRow> createState() => _RoutineRowState();
}

class _RoutineRowState extends ConsumerState<_RoutineRow> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    final result =
        await ref.read(routinesForDayProvider(widget.day).notifier).toggle(widget.item.id);
    if (!mounted) return;
    setState(() => _busy = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
      ),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final pending =
        _busy || ref.read(routinesForDayProvider(widget.day).notifier).isPending(item.id);

    return Opacity(
      opacity: item.completed ? 0.6 : 1.0,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Checkbox(
          value: item.completed,
          onChanged: pending ? null : (_) => _toggle(),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        title: Text(
          item.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            decoration: item.completed ? TextDecoration.lineThrough : null,
            color: item.completed
                ? theme.colorScheme.onSurfaceVariant
                : theme.colorScheme.onSurface,
          ),
        ),
        trailing: item.currentStreak > 0
            ? Row(
                key: ValueKey('streak-${item.id}'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_fire_department, size: 16, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 2),
                  Text('${item.currentStreak}', style: theme.textTheme.labelMedium),
                ],
              )
            : null,
      ),
    );
  }
}

class _EmptyRoutines extends StatelessWidget {
  const _EmptyRoutines();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          RoutinesCard.emptyText,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _RoutinesCardSkeleton extends StatelessWidget {
  const _RoutinesCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return Column(
      key: const ValueKey('routines-skeleton'),
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            height: 20,
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          ),
      ],
    );
  }
}

class _RoutinesCardError extends StatelessWidget {
  const _RoutinesCardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text(RoutinesCard.retryText),
          ),
        ],
      ),
    );
  }
}
