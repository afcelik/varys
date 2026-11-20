import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/presentation/providers/eisenhower_tasks_provider.dart';
import 'package:varys/features/planning/domain/eisenhower.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// `/eisenhower/:quadrant`: the open tasks of one quadrant (newest first),
/// outside the shell, not a menu destination. A row opens the edit form; a
/// task whose flags change there leaves this list by itself (same data as
/// the Home card). Project names come from [projectsListProvider]; until
/// they load (or on error) rows show no project name.
class EisenhowerQuadrantPage extends ConsumerWidget {
  const EisenhowerQuadrantPage({super.key, required this.quadrant});

  final EisenhowerQuadrant quadrant;

  static const String emptyText = 'Bu bölmede görev yok';
  static const String retryText = 'Tekrar dene';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final value = ref.watch(eisenhowerTasksProvider);
    final projectNames = projectNamesById(
      ref.watch(projectsListProvider).valueOrNull?.projects ?? const [],
    );

    final Widget body;
    if (value.hasError && !value.isLoading) {
      body = _PageError(
        message: userMessage(value.error!),
        onRetry: () {
          if (ref.read(taskListNotifierProvider).hasError) {
            ref.invalidate(taskListNotifierProvider);
          } else {
            ref.invalidate(eisenhowerTasksProvider);
          }
        },
      );
    } else if (value.hasValue) {
      final tasks = groupByQuadrant(value.requireValue)[quadrant]!;
      body = tasks.isEmpty
          ? _Message(
              key: const ValueKey('eisenhower-page-empty'),
              text: emptyText,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : ListView.separated(
              key: const ValueKey('eisenhower-page-list'),
              padding: const EdgeInsets.all(16),
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final task = tasks[i];
                final meta = taskMetaLine(task, projectNames);
                return Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    key: ValueKey('eisenhower-page-task-${task.id}'),
                    title: Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: meta == null
                        ? null
                        : Text(
                            meta,
                            key: ValueKey('eisenhower-page-meta-${task.id}'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                    onTap: () => context.push(AppRouter.tasksEditPath, extra: task),
                  ),
                );
              },
            );
    } else {
      body = const Center(
        child: CircularProgressIndicator(key: ValueKey('eisenhower-page-loading')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackArrow(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              quadrant.title,
              key: const ValueKey('eisenhower-page-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              quadrant.subtitle,
              key: const ValueKey('eisenhower-page-subtitle'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      body: SafeArea(child: body),
    );
  }
}

class _PageError extends StatelessWidget {
  const _PageError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        key: const ValueKey('eisenhower-page-error'),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const ValueKey('eisenhower-page-retry'),
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(EisenhowerQuadrantPage.retryText),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
        ),
      ),
    );
  }
}

/// Shown for `/eisenhower/<unknown>` (deep link, typo). Leaves with
/// BackArrow (pop, or /home).
class EisenhowerUnavailablePage extends StatelessWidget {
  const EisenhowerUnavailablePage({super.key});

  static const String message = 'Bu sayfa doğrudan açılamaz.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: const BackArrow()),
      body: _Message(
        key: const ValueKey('eisenhower-unavailable'),
        text: message,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}
