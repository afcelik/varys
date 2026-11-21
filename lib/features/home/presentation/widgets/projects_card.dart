import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/presentation/active_projects_notifier.dart';

/// Home card with the active projects: "Aktif N/M" counter, one row per
/// project (title, then progress bar + percent below it, or "Henüz görev
/// yok" when the project has no tasks). Loading and errors stay inside this
/// card; the rest of Home is unaffected.
class ProjectsCard extends ConsumerWidget {
  const ProjectsCard({super.key});

  static const String title = 'Aktif Projeler';
  static const String emptyText = 'Aktif proje yok';
  static const String noTasksText = 'Henüz görev yok';
  static const String moreText = 'Daha fazla';
  static const String retryText = 'Tekrar dene';

  static String counterText(int activeCount, int maxActive) => 'Aktif $activeCount/$maxActive';
  static String percentText(int percent) => '%$percent';

  /// Short Turkish day, e.g. "20 Kas". The day is a plain calendar date.
  static String formatTargetDate(DateTime day) => DateFormat('d MMM', 'tr_TR').format(day);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final value = ref.watch(activeProjectsProvider);

    final Widget body;
    String? counter;
    if (value.hasError && !value.isLoading) {
      body = _ProjectsCardError(
        message: userMessage(value.error!),
        onRetry: () => ref.invalidate(activeProjectsProvider),
      );
    } else if (value.hasValue) {
      final data = value.requireValue;
      counter = counterText(data.activeCount, data.maxActive);
      body = data.projects.isEmpty
          ? const _EmptyProjects()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final project in data.projects)
                  _ProjectRow(key: ValueKey('project-${project.id}'), project: project),
              ],
            );
    } else {
      body = const _ProjectsCardSkeleton();
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
                Icon(Icons.folder_outlined, size: 24, color: theme.colorScheme.primary),
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
                onPressed: () => context.push(AppRouter.projectsPath),
                child: const Text(moreText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Title (with the target day, if any) on its own line; below it either the
/// progress bar with the percent beside it, or "Henüz görev yok" (no bar).
/// Tapping the row opens the project detail page.
class _ProjectRow extends StatelessWidget {
  const _ProjectRow({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percent = project.progressPercent;
    final target = project.targetDate;

    return InkWell(
      onTap: () => context.push(AppRouter.projectDetailPath, extra: project),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    project.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
                if (target != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    ProjectsCard.formatTargetDate(target),
                    key: ValueKey('project-target-${project.id}'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            if (percent == null)
              Text(
                ProjectsCard.noTasksText,
                key: ValueKey('project-no-tasks-${project.id}'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              )
            else
              Row(
                key: ValueKey('project-progress-${project.id}'),
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: percent.clamp(0, 100) / 100,
                        minHeight: 6,
                        semanticsLabel: ProjectsCard.percentText(percent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    ProjectsCard.percentText(percent),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          ProjectsCard.emptyText,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

class _ProjectsCardSkeleton extends StatelessWidget {
  const _ProjectsCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final color =
        Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return Column(
      key: const ValueKey('projects-skeleton'),
      children: [
        for (var i = 0; i < 2; i++) ...[
          Container(
            height: 20,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          ),
          Container(
            height: 6,
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
          ),
        ],
      ],
    );
  }
}

class _ProjectsCardError extends StatelessWidget {
  const _ProjectsCardError({required this.message, required this.onRetry});

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
            label: const Text(ProjectsCard.retryText),
          ),
        ],
      ),
    );
  }
}
