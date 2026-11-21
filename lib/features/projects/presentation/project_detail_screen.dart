import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/presentation/providers/eisenhower_tasks_provider.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/presentation/task_new_args.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/projects/domain/project.dart';
import 'package:varys/features/projects/domain/project_form.dart';
import 'package:varys/features/projects/domain/project_tasks.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Full-screen project detail page (outside the shell, pushed from a
/// /projects row or the Home "Aktif Projeler" card with the [Project] as
/// extra).
///
/// [initial] is only the starting value: the current project is read by id
/// from [projectsListProvider]. While that list has no value (loading or
/// failed) [initial] is shown; once loaded, a missing id means the project
/// was deleted ("Bu proje artık yok", no Düzenle / Görev ekle).
///
/// The tasks come from [eisenhowerTasksProvider] (the full list, not
/// narrowed by the Planning filter), narrowed here to this project
/// ([projectTaskGroups]). Their loading and error states stay inside the
/// task section; the project header is unaffected.
class ProjectDetailScreen extends ConsumerStatefulWidget {
  const ProjectDetailScreen({super.key, required this.initial});

  final Project initial;

  static const String title = 'Proje';
  static const String editText = 'Düzenle';
  static const String addTaskText = 'Görev ekle';
  static const String goneText = 'Bu proje artık yok';
  static const String backText = 'Geri dön';
  static const String noTasksText = 'Henüz görev yok';
  static const String pendingTitle = 'Bekleyen görevler';
  static const String emptyPendingText = 'Bu projede bekleyen görev yok';
  static const String retryText = 'Tekrar dene';
  static const String showAllText = 'Tümünü göster';
  static const String collapseText = 'Daralt';
  static const String startPrefix = 'Başlangıç: ';
  static const String targetPrefix = 'Hedef: ';

  /// Description lines shown before "Tümünü göster".
  static const int descriptionMaxLines = 6;

  static String doneTitle(int count) => 'Tamamlananlar ($count)';
  static String percentText(int percent) => '%$percent';
  static String countText(int done, int total) => '$done/$total görev';

  @override
  ConsumerState<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends ConsumerState<ProjectDetailScreen> {
  bool _descriptionExpanded = false;
  bool _doneOpen = false;

  /// Task ids with a status change in flight (a second tap is ignored).
  final Set<int> _toggling = <int>{};

  void _openEdit(Project project) => context.push(AppRouter.projectsEditPath, extra: project);

  void _openAddTask(Project project) =>
      context.push(AppRouter.tasksNewPath, extra: TaskNewArgs(projectId: project.id));

  void _openTask(Task task) => context.push(AppRouter.tasksEditPath, extra: task);

  void _leave() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRouter.homePath);
    }
  }

  Future<void> _toggle(Task task) async {
    if (_toggling.contains(task.id)) return;
    setState(() => _toggling.add(task.id));
    final result = await ref.read(taskListNotifierProvider.notifier).toggleTaskCompletion(task.id);
    if (!mounted) return;
    setState(() => _toggling.remove(task.id));
    result.fold((failure) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
      );
    }, (_) {});
  }

  void _retryTasks() {
    if (ref.read(taskListNotifierProvider).hasError) {
      ref.invalidate(taskListNotifierProvider);
    } else {
      ref.invalidate(eisenhowerTasksProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(projectsListProvider).valueOrNull;
    final id = widget.initial.id;
    final Project? project = overview == null
        ? widget.initial
        : overview.projects.where((p) => p.id == id).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: const Text(ProjectDetailScreen.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (project != null) ...[
            IconButton(
              key: const ValueKey('project-detail-edit'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: ProjectDetailScreen.editText,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => _openEdit(project),
            ),
            IconButton(
              key: const ValueKey('project-detail-add-task'),
              icon: const Icon(Icons.add_task),
              tooltip: ProjectDetailScreen.addTaskText,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () => _openAddTask(project),
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: project == null ? _ProjectGone(onBack: _leave) : _buildBody(context, project),
      ),
    );
  }

  Widget _buildBody(BuildContext context, Project project) {
    final tasksValue = ref.watch(eisenhowerTasksProvider);
    final children = <Widget>[
      _ProjectHeader(
        project: project,
        descriptionExpanded: _descriptionExpanded,
        onToggleDescription: () => setState(() => _descriptionExpanded = !_descriptionExpanded),
      ),
      const Divider(height: 32),
      ..._taskSection(context, project, tasksValue),
    ];
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: children);
  }

  List<Widget> _taskSection(BuildContext context, Project project, AsyncValue<List<Task>> value) {
    final theme = Theme.of(context);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Text(
        ProjectDetailScreen.pendingTitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
      ),
    );

    if (value.hasError && !value.isLoading) {
      return [header, _TasksError(message: userMessage(value.error!), onRetry: _retryTasks)];
    }
    if (!value.hasValue) {
      return [
        header,
        const Padding(
          key: ValueKey('project-detail-tasks-loading'),
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    final groups = projectTaskGroups(value.requireValue, project.id);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return [
      header,
      if (groups.pending.isEmpty)
        Padding(
          key: const ValueKey('project-detail-tasks-empty'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(ProjectDetailScreen.emptyPendingText, style: muted),
        )
      else
        for (final task in groups.pending)
          _ProjectTaskRow(
            key: ValueKey('project-task-${task.id}'),
            task: task,
            busy: _toggling.contains(task.id),
            onToggle: () => _toggle(task),
            onTap: () => _openTask(task),
          ),
      if (groups.done.isNotEmpty) ...[
        const SizedBox(height: 8),
        InkWell(
          key: const ValueKey('project-detail-done-toggle'),
          onTap: () => setState(() => _doneOpen = !_doneOpen),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ProjectDetailScreen.doneTitle(groups.done.length),
                      key: const ValueKey('project-detail-done-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  Icon(_doneOpen ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
        ),
        if (_doneOpen)
          for (final task in groups.done)
            _ProjectTaskRow(
              key: ValueKey('project-task-${task.id}'),
              task: task,
              busy: _toggling.contains(task.id),
              onToggle: () => _toggle(task),
              onTap: () => _openTask(task),
            ),
      ],
    ];
  }
}

/// Title (3 lines), status label, description (6 lines + "Tümünü göster" /
/// "Daralt" when longer), dates (if any) and progress: a bar with "%N" and
/// "D/T görev", or "Henüz görev yok" when progress is null (0 is a percent).
class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({
    required this.project,
    required this.descriptionExpanded,
    required this.onToggleDescription,
  });

  final Project project;
  final bool descriptionExpanded;
  final VoidCallback onToggleDescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final description = project.description?.trim() ?? '';
    final percent = project.progressPercent;
    final start = project.startDate;
    final target = project.targetDate;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            project.title,
            key: const ValueKey('project-detail-title'),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              projectStatusLabels[project.status]!,
              key: const ValueKey('project-detail-status'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 12),
            _Description(
              text: description,
              expanded: descriptionExpanded,
              onToggle: onToggleDescription,
            ),
          ],
          if (start != null) ...[
            const SizedBox(height: 8),
            Text(
              '${ProjectDetailScreen.startPrefix}${shortTrDay(start)}',
              key: const ValueKey('project-detail-start'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ],
          if (target != null) ...[
            SizedBox(height: start == null ? 8 : 4),
            Text(
              '${ProjectDetailScreen.targetPrefix}${shortTrDay(target)}',
              key: const ValueKey('project-detail-target'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ],
          const SizedBox(height: 16),
          if (percent == null)
            Text(
              ProjectDetailScreen.noTasksText,
              key: const ValueKey('project-detail-no-tasks'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: LinearProgressIndicator(
                    key: const ValueKey('project-detail-progress'),
                    value: percent.clamp(0, 100) / 100,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                    semanticsLabel: ProjectDetailScreen.percentText(percent),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  ProjectDetailScreen.percentText(percent),
                  key: const ValueKey('project-detail-percent'),
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              ProjectDetailScreen.countText(project.doneTasks, project.totalTasks),
              key: const ValueKey('project-detail-count'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ],
        ],
      ),
    );
  }
}

/// Plain-text description: at most [ProjectDetailScreen.descriptionMaxLines]
/// lines with an ellipsis; the toggle is shown only when the text is longer.
class _Description extends StatelessWidget {
  const _Description({required this.text, required this.expanded, required this.onToggle});

  final String text;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: ProjectDetailScreen.descriptionMaxLines,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final long = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              key: const ValueKey('project-detail-description'),
              maxLines: expanded ? null : ProjectDetailScreen.descriptionMaxLines,
              overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: style,
            ),
            if (long)
              TextButton(
                key: const ValueKey('project-detail-description-toggle'),
                onPressed: onToggle,
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: Text(
                  expanded ? ProjectDetailScreen.collapseText : ProjectDetailScreen.showAllText,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One task: checkbox (48x48, completes/reopens), title (2 lines) and the
/// due day if any. Tapping the row opens the task edit form.
class _ProjectTaskRow extends StatelessWidget {
  const _ProjectTaskRow({
    super.key,
    required this.task,
    required this.busy,
    required this.onToggle,
    required this.onTap,
  });

  final Task task;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = task.isCompleted;
    final due = task.dueDate;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 16, 0),
          child: Row(
            children: [
              Checkbox(
                key: ValueKey('project-task-check-${task.id}'),
                value: done,
                materialTapTargetSize: MaterialTapTargetSize.padded,
                onChanged: busy ? null : (_) => onToggle(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  task.title,
                  key: ValueKey('project-task-title-${task.id}'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    decoration: done ? TextDecoration.lineThrough : null,
                    color: done ? theme.colorScheme.onSurfaceVariant : null,
                  ),
                ),
              ),
              if (due != null) ...[
                const SizedBox(width: 8),
                Text(
                  shortTrDay(due),
                  key: ValueKey('project-task-due-${task.id}'),
                  maxLines: 1,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TasksError extends StatelessWidget {
  const _TasksError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('project-detail-tasks-error'),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('project-detail-tasks-retry'),
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text(ProjectDetailScreen.retryText),
          ),
        ],
      ),
    );
  }
}

/// The project was deleted (missing from the loaded list): a fixed message
/// and "Geri dön"; no Düzenle / Görev ekle.
class _ProjectGone extends StatelessWidget {
  const _ProjectGone({required this.onBack});

  final VoidCallback onBack;

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
              ProjectDetailScreen.goneText,
              key: const ValueKey('project-detail-gone'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('project-detail-back'),
              onPressed: onBack,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(ProjectDetailScreen.backText),
            ),
          ],
        ),
      ),
    );
  }
}

/// `/projects/detail` opened without a [Project] extra (deep link,
/// notification, wrong type): a fixed message; BackArrow leaves.
class ProjectDetailUnavailablePage extends StatelessWidget {
  const ProjectDetailUnavailablePage({super.key});

  static const String message = 'Bu sayfa doğrudan açılamaz.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: const BackArrow()),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            key: const ValueKey('project-detail-unavailable'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
