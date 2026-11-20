import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/presentation/providers/eisenhower_tasks_provider.dart';
import 'package:varys/features/planning/domain/eisenhower.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';

/// Home card "Öncelik Matrisi": the open tasks in the four Eisenhower
/// quadrants. Each quadrant is ONE tap target (opens its page); it shows the
/// name, the subtitle, a count and up to [maxTitles] task titles, then "+N".
/// Card width >= [twoColumnMinWidth]: 2x2 grid, otherwise one column.
///
/// States: skeleton (first load only), error with "Tekrar dene" (reloads
/// only this card's data), "Bekleyen görev yok", filled. While data is
/// recomputed (Planning filter change, task edit) the old content stays.
/// Colour is only a thin accent; quadrants are told apart by their label.
class EisenhowerCard extends ConsumerWidget {
  const EisenhowerCard({super.key});

  static const String title = 'Öncelik Matrisi';
  static const String emptyText = 'Bekleyen görev yok';
  static const String retryText = 'Tekrar dene';
  static const int maxTitles = 3;
  static const double twoColumnMinWidth = 600;

  static String moreText(int hidden) => '+$hidden';

  /// Thin accent per quadrant, from the theme's existing colours.
  static Color accentOf(ColorScheme colors, EisenhowerQuadrant q) => switch (q) {
    EisenhowerQuadrant.doNow => colors.error,
    EisenhowerQuadrant.schedule => colors.primary,
    EisenhowerQuadrant.delegate => colors.tertiary,
    EisenhowerQuadrant.eliminate => colors.outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final value = ref.watch(eisenhowerTasksProvider);

    final Widget body;
    if (value.hasError && !value.isLoading) {
      body = _CardError(
        message: userMessage(value.error!),
        onRetry: () {
          // The Planning list itself failed: reload it (this card follows);
          // otherwise only this card's own request is repeated.
          if (ref.read(taskListNotifierProvider).hasError) {
            ref.invalidate(taskListNotifierProvider);
          } else {
            ref.invalidate(eisenhowerTasksProvider);
          }
        },
      );
    } else if (value.hasValue) {
      final groups = groupByQuadrant(value.requireValue);
      body = groups.values.every((tasks) => tasks.isEmpty) ? const _Empty() : _Grid(groups: groups);
    } else {
      body = const _Skeleton();
    }

    return Card(
      key: const ValueKey('eisenhower-card'),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.grid_view_outlined, size: 24, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey('eisenhower-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            body,
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.groups});

  final Map<EisenhowerQuadrant, List<Task>> groups;

  @override
  Widget build(BuildContext context) {
    Widget tile(EisenhowerQuadrant q) => _QuadrantTile(quadrant: q, tasks: groups[q]!);
    const gap = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < EisenhowerCard.twoColumnMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, q) in EisenhowerQuadrant.values.indexed) ...[
                if (i > 0) const SizedBox(height: gap),
                tile(q),
              ],
            ],
          );
        }
        Widget row(EisenhowerQuadrant a, EisenhowerQuadrant b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: tile(a)),
              const SizedBox(width: gap),
              Expanded(child: tile(b)),
            ],
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row(EisenhowerQuadrant.doNow, EisenhowerQuadrant.schedule),
            const SizedBox(height: gap),
            row(EisenhowerQuadrant.delegate, EisenhowerQuadrant.eliminate),
          ],
        );
      },
    );
  }
}

/// One quadrant: a single InkWell (>= 48 high); the title lines inside are
/// plain text and never swallow the tap.
class _QuadrantTile extends StatelessWidget {
  const _QuadrantTile({required this.quadrant, required this.tasks});

  final EisenhowerQuadrant quadrant;
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final segment = quadrant.pathSegment;
    final shown = tasks.take(EisenhowerCard.maxTitles).toList();
    final hidden = tasks.length - shown.length;

    return Material(
      color: colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('eisenhower-quadrant-$segment'),
        onTap: () => context.push(AppRouter.eisenhowerPath(quadrant)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: EisenhowerCard.accentOf(colors, quadrant), width: 3),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          quadrant.title,
                          key: ValueKey('eisenhower-name-$segment'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CountBadge(key: ValueKey('eisenhower-count-$segment'), count: tasks.length),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quadrant.subtitle,
                    key: ValueKey('eisenhower-subtitle-$segment'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  for (final task in shown) ...[
                    const SizedBox(height: 6),
                    Text(
                      task.title,
                      key: ValueKey('eisenhower-task-${task.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                  if (hidden > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      EisenhowerCard.moreText(hidden),
                      key: ValueKey('eisenhower-more-$segment'),
                      maxLines: 1,
                      style: theme.textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count',
        maxLines: 1,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        EisenhowerCard.emptyText,
        key: const ValueKey('eisenhower-empty'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _CardError extends StatelessWidget {
  const _CardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('eisenhower-error'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        Center(
          child: OutlinedButton(
            key: const ValueKey('eisenhower-retry'),
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text(EisenhowerCard.retryText),
          ),
        ),
      ],
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    return Column(
      key: const ValueKey('eisenhower-loading'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Container(
            height: 48,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
          ),
        ],
      ],
    );
  }
}
