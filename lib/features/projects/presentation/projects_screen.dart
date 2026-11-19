import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/plan_field.dart';
import 'package:varys/features/home/presentation/widgets/projects_card.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Full-screen projects page (outside the shell, opened with push from the
/// Home "Aktif Projeler" card): every project grouped by status, the active
/// counter, status changes, delete, and entry to the create/edit form.
class ProjectsScreen extends ConsumerStatefulWidget {
  const ProjectsScreen({super.key});

  static const String title = 'Projeler';
  static const String addText = 'Proje ekle';
  static const String emptyText = 'Henüz proje yok';
  static const String retryText = 'Tekrar dene';
  static const String noTasksText = 'Henüz görev yok';
  static const String targetPrefix = 'Hedef: ';
  static const String menuTooltip = 'Durum ve işlemler';

  static const String activateText = 'Aktif yap';
  static const String holdText = 'Beklemeye al';
  static const String somedayText = 'İleriye al';
  static const String completeText = 'Tamamla';
  static const String deleteText = 'Sil';
  static const String activateDisabledReason = 'Aktif proje sınırı dolu';

  static const String deleteQuestion =
      'Bu proje silinsin mi? Bağlı görevler silinmez, projeden ayrılır.';
  static const String deleteConfirmText = 'Sil';
  static const String deleteCancelText = 'Vazgeç';

  /// "Aktif N/M" counter in the app bar.
  static String activeCounter(ProjectLimits limits) =>
      'Aktif ${limits.activeCount}/${limits.maxActive}';

  /// Progress text: "%25" (0 is shown as "%0"); null means no tasks.
  static String progressText(int percent) => '%$percent';

  @override
  ConsumerState<ProjectsScreen> createState() => _ProjectsScreenState();
}

/// Row actions of the status menu.
enum ProjectRowAction { activate, hold, someday, complete, delete }

class _ProjectsScreenState extends ConsumerState<ProjectsScreen> {
  /// Project ids with a status change or delete request in flight.
  final Set<int> _busy = <int>{};

  void _openNew() => context.push(AppRouter.projectsNewPath);

  void _openEdit(Project project) => context.push(AppRouter.projectsEditPath, extra: project);

  void _showError(Object failure) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _onAction(Project project, ProjectRowAction action) async {
    switch (action) {
      case ProjectRowAction.activate:
        return _setStatus(project, ProjectStatus.active);
      case ProjectRowAction.hold:
        return _setStatus(project, ProjectStatus.onHold);
      case ProjectRowAction.someday:
        return _setStatus(project, ProjectStatus.someday);
      case ProjectRowAction.complete:
        return _setStatus(project, ProjectStatus.completed);
      case ProjectRowAction.delete:
        return _delete(project);
    }
  }

  Future<void> _setStatus(Project project, ProjectStatus status) async {
    if (_busy.contains(project.id)) return;
    setState(() => _busy.add(project.id));
    final result = await ref
        .read(projectsListProvider.notifier)
        .updateProject(project.id, ProjectChanges(status: PlanField.set(status)));
    if (!mounted) return;
    setState(() => _busy.remove(project.id));
    result.fold(_showError, (_) {});
  }

  Future<void> _delete(Project project) async {
    if (_busy.contains(project.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(projectTitle: project.title),
    );
    if (confirmed != true || !mounted || _busy.contains(project.id)) return;

    setState(() => _busy.add(project.id));
    final result = await ref.read(projectsListProvider.notifier).deleteProject(project.id);
    if (!mounted) return;
    setState(() => _busy.remove(project.id));
    result.fold(_showError, (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(projectsListProvider);
    final overview = value.valueOrNull;

    final Widget body;
    if (overview != null) {
      body = overview.projects.isEmpty
          ? _EmptyProjects(onAdd: _openNew)
          : _ProjectSections(
              overview: overview,
              busy: _busy,
              onTap: _openEdit,
              onAction: _onAction,
            );
    } else if (value.hasError) {
      body = _ProjectsError(
        message: userMessage(value.error!),
        onRetry: () => ref.invalidate(projectsListProvider),
      );
    } else {
      body = const Center(key: ValueKey('projects-loading'), child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: Row(
          children: [
            const Flexible(
              child: Text(ProjectsScreen.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (overview != null) ...[
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  ProjectsScreen.activeCounter(overview.limits),
                  key: const ValueKey('projects-active-counter'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('projects-add'),
            icon: const Icon(Icons.add),
            tooltip: ProjectsScreen.addText,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _openNew,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: body),
    );
  }
}

/// Status sections in fixed order; a status without projects is not drawn.
class _ProjectSections extends StatelessWidget {
  const _ProjectSections({
    required this.overview,
    required this.busy,
    required this.onTap,
    required this.onAction,
  });

  final ProjectsOverview overview;
  final Set<int> busy;
  final void Function(Project) onTap;
  final void Function(Project, ProjectRowAction) onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];
    for (final MapEntry(key: status, value: label) in projectStatusLabels.entries) {
      final projects = overview.projects.where((p) => p.status == status).toList();
      if (projects.isEmpty) continue;
      children.add(
        Padding(
          key: ValueKey('projects-section-${status.apiValue}'),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
      );
      for (final project in projects) {
        children.add(
          _ProjectRow(
            key: ValueKey('project-row-${project.id}'),
            project: project,
            canActivate: canChooseActive(overview.limits, editing: project),
            busy: busy.contains(project.id),
            onTap: () => onTap(project),
            onAction: (action) => onAction(project, action),
          ),
        );
      }
    }
    return ListView(padding: const EdgeInsets.only(bottom: 16), children: children);
  }
}

class _ProjectRow extends StatelessWidget {
  const _ProjectRow({
    super.key,
    required this.project,
    required this.canActivate,
    required this.busy,
    required this.onTap,
    required this.onAction,
  });

  final Project project;
  final bool canActivate;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<ProjectRowAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final percent = project.progressPercent;
    final target = project.targetDate;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      project.title,
                      key: ValueKey('project-title-${project.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 6),
                    if (percent == null)
                      Text(
                        ProjectsScreen.noTasksText,
                        key: ValueKey('project-no-tasks-${project.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              key: ValueKey('project-progress-${project.id}'),
                              value: percent / 100,
                              minHeight: 4,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(ProjectsScreen.progressText(percent), style: muted),
                        ],
                      ),
                    if (target != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${ProjectsScreen.targetPrefix}${ProjectsCard.formatTargetDate(target)}',
                        key: ValueKey('project-target-${project.id}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                  ],
                ),
              ),
              _StatusMenu(
                project: project,
                canActivate: canActivate,
                enabled: !busy,
                onSelected: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status menu of a row. "Aktif yap" is absent for an active project and
/// disabled (with the reason) when the limit is full; "Tamamla" only for a
/// project that is not completed. "Sil" is always last.
class _StatusMenu extends StatelessWidget {
  const _StatusMenu({
    required this.project,
    required this.canActivate,
    required this.enabled,
    required this.onSelected,
  });

  final Project project;
  final bool canActivate;
  final bool enabled;
  final ValueChanged<ProjectRowAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = project.status;
    return PopupMenuButton<ProjectRowAction>(
      key: ValueKey('project-menu-${project.id}'),
      tooltip: ProjectsScreen.menuTooltip,
      enabled: enabled,
      constraints: const BoxConstraints(minWidth: 200),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      onSelected: onSelected,
      itemBuilder: (context) => [
        if (status != ProjectStatus.active)
          PopupMenuItem(
            key: const ValueKey('project-action-activate'),
            value: ProjectRowAction.activate,
            enabled: canActivate,
            child: canActivate
                ? const Text(ProjectsScreen.activateText)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(ProjectsScreen.activateText),
                      Text(
                        ProjectsScreen.activateDisabledReason,
                        key: const ValueKey('project-action-activate-reason'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
          ),
        if (status != ProjectStatus.onHold)
          const PopupMenuItem(
            key: ValueKey('project-action-hold'),
            value: ProjectRowAction.hold,
            child: Text(ProjectsScreen.holdText),
          ),
        if (status != ProjectStatus.someday)
          const PopupMenuItem(
            key: ValueKey('project-action-someday'),
            value: ProjectRowAction.someday,
            child: Text(ProjectsScreen.somedayText),
          ),
        if (status != ProjectStatus.completed)
          const PopupMenuItem(
            key: ValueKey('project-action-complete'),
            value: ProjectRowAction.complete,
            child: Text(ProjectsScreen.completeText),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          key: ValueKey('project-action-delete'),
          value: ProjectRowAction.delete,
          child: Text(ProjectsScreen.deleteText),
        ),
      ],
    );
  }
}

/// Confirmation dialog. The first tap on "Sil" closes it; later taps (while
/// the close animation runs) are ignored, so a double tap pops only once.
class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog({required this.projectTitle});

  final String projectTitle;

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  bool _closed = false;

  void _close(bool confirmed) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.projectTitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      content: const Text(ProjectsScreen.deleteQuestion),
      actions: [
        TextButton(
          onPressed: () => _close(false),
          child: const Text(ProjectsScreen.deleteCancelText),
        ),
        FilledButton(
          key: const ValueKey('project-delete-confirm'),
          onPressed: () => _close(true),
          child: const Text(ProjectsScreen.deleteConfirmText),
        ),
      ],
    );
  }
}

class _EmptyProjects extends StatelessWidget {
  const _EmptyProjects({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              ProjectsScreen.emptyText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('projects-empty-add'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text(ProjectsScreen.addText),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectsError extends StatelessWidget {
  const _ProjectsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
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
              key: const ValueKey('projects-retry'),
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(ProjectsScreen.retryText),
            ),
          ],
        ),
      ),
    );
  }
}
