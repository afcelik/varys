import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dartz/dartz.dart' hide Task;
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_form.dart';
import 'package:varys/features/planning/presentation/task_notifier.dart';
import 'package:varys/features/projects/presentation/projects_list_notifier.dart';

/// Task list page - main planning screen with task management
class TaskListPage extends ConsumerStatefulWidget {
  const TaskListPage({super.key});

  @override
  ConsumerState<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends ConsumerState<TaskListPage> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(taskListNotifierProvider);
    // Project names for the rows (all statuses). Until loaded, or on a load
    // error, rows simply show no project name.
    final projectNames = projectNamesById(
      ref.watch(projectsListProvider).valueOrNull?.projects ?? const [],
    );

    return state.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) => Scaffold(
        appBar: AppBar(title: const Text('Planlama')),
        body: _ErrorView(
          message: userMessage(error),
          onRetry: () => ref.invalidate(taskListNotifierProvider),
        ),
      ),
      data: (taskState) => Scaffold(
        appBar: AppBar(
          title: const Text('Planlama'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async => _reportFailure(
                await ref
                    .read(taskListNotifierProvider.notifier)
                    .refreshTasks(),
              ),
              tooltip: 'Yenile',
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: _FilterTabs(
              currentFilter: taskState.currentFilter,
              onFilterChanged: (filter) async {
                _reportFailure(
                  await ref
                      .read(taskListNotifierProvider.notifier)
                      .changeFilter(filter),
                );
              },
            ),
          ),
        ),
        body: _TaskListView(
          tasks: taskState.tasks.value ?? [],
          projectNames: projectNames,
          onToggle: (id) async => _reportFailure(
            await ref
                .read(taskListNotifierProvider.notifier)
                .toggleTaskCompletion(id),
          ),
          onDelete: (id) async => _reportFailure(
            await ref.read(taskListNotifierProvider.notifier).deleteTask(id),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          // Full-screen create form outside the shell (push, never go).
          onPressed: () => context.push(AppRouter.tasksNewPath),
          icon: const Icon(Icons.add),
          label: const Text('Yeni Görev'),
        ),
      ),
    );
  }

  /// Shows a Turkish snackbar for a failed mutation; success needs no UI.
  void _reportFailure(Either<Failure, void> result) {
    result.fold((failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userMessage(failure)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }, (_) {});
  }
}

/// Filter tabs for task list
class _FilterTabs extends StatelessWidget {
  final TaskFilter currentFilter;
  final ValueChanged<TaskFilter> onFilterChanged;

  const _FilterTabs({
    required this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: TaskFilter.values.map((filter) {
          final isSelected = filter == currentFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(filter.label),
              selected: isSelected,
              onSelected: (_) => onFilterChanged(filter),
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Task list view
class _TaskListView extends StatelessWidget {
  final List<Task> tasks;
  final Map<int, String> projectNames;
  final ValueChanged<int> onToggle;
  final ValueChanged<int> onDelete;

  const _TaskListView({
    required this.tasks,
    required this.projectNames,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return _EmptyState(
        icon: Icons.task_alt,
        title: 'Görev bulunamadı',
        subtitle:
            'Henüz görev eklenmemiş. Yeni bir görev oluşturmak için + butonuna basın.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return _TaskTile(
          task: task,
          projectNames: projectNames,
          onToggle: () => onToggle(task.id),
          onDelete: () => onDelete(task.id),
          onEdit: () => context.push(AppRouter.tasksEditPath, extra: task),
        );
      },
    );
  }
}

/// Individual task tile
class _TaskTile extends StatelessWidget {
  final Task task;
  final Map<int, String> projectNames;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  /// Row body tap: opens the edit form. Completing is the checkbox only.
  final VoidCallback onEdit;

  const _TaskTile({
    required this.task,
    required this.projectNames,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDescription = task.description?.isNotEmpty == true;
    final meta = taskMetaLine(task, projectNames);

    return Dismissible(
      key: ValueKey(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Görevi Sil'),
                content: Text(
                  '"${task.title}" görevini silmek istediğinizden emin misiniz?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('İptal'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('Sil'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => onDelete(),
      child: Card(
        child: ListTile(
          leading: Checkbox(
            value: task.isCompleted,
            onChanged: (_) => onToggle(),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          title: Text(
            task.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              decoration: task.isCompleted ? TextDecoration.lineThrough : null,
              color: task.isCompleted
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
            ),
          ),
          // Description (if any) and the meta line (project · due day, if
          // any). Neither → no subtitle, as before; '' draws no empty line.
          subtitle: !hasDescription && meta == null
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasDescription)
                      Text(
                        task.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: task.isCompleted
                              ? theme.colorScheme.onSurfaceVariant
                              : null,
                        ),
                      ),
                    if (meta != null)
                      Text(
                        meta,
                        key: ValueKey('task-meta-${task.id}'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
            tooltip: 'Sil',
          ),
          onTap: onEdit,
        ),
      ),
    );
  }
}

/// Error view for failed states
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Bir hata oluştu',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state widget
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
