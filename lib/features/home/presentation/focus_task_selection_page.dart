import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/features/planning/data/task_repository_impl.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/features/planning/domain/task_repository.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Full-screen page for selecting a focus task.
/// Accessed via context.push() from the Home screen.
/// Returns the selected Task or null if user backs out (no change).
/// Clearing focus is done from the card's "Clear" action, not here.
class FocusTaskSelectionPage extends ConsumerWidget {
  const FocusTaskSelectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final taskRepositoryAsync = ref.watch(taskRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackArrow(),
        title: const Text('Odak Görevi Seç'),
      ),
      body: taskRepositoryAsync.when(
        data: (taskRepository) => _TaskListView(taskRepository: taskRepository),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Görevler yüklenemedi',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                error.toString(),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(taskRepositoryProvider),
                child: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// List view of tasks for selection
class _TaskListView extends ConsumerWidget {
  final TaskRepository taskRepository;

  const _TaskListView({required this.taskRepository});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: taskRepository.getTasksByFilter(TaskFilter.inProgress),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Hata: ${snapshot.error}'),
          );
        }

        final result = snapshot.data!;
        return result.fold(
          (failure) => Center(child: Text(failure.message)),
          (inProgressTasks) => _buildTaskList(context, inProgressTasks, ref),
        );
      },
    );
  }

  Widget _buildTaskList(BuildContext context, List<Task> inProgressTasks, WidgetRef ref) {
    // Also fetch completed tasks to show at the bottom
    return FutureBuilder(
      future: taskRepository.getTasksByFilter(TaskFilter.completed),
      builder: (context, completedSnapshot) {
        if (completedSnapshot.connectionState == ConnectionState.waiting) {
          return _buildListWithTasks(context, inProgressTasks, [], Theme.of(context));
        }

        final completedResult = completedSnapshot.data!;
        final completedTasks = completedResult.fold(
          (failure) => <Task>[],
          (tasks) => tasks,
        );

        return _buildListWithTasks(context, inProgressTasks, completedTasks, Theme.of(context));
      },
    );
  }

  Widget _buildListWithTasks(
    BuildContext context,
    List<Task> inProgressTasks,
    List<Task> completedTasks,
    ThemeData theme,
  ) {
    final allTasks = [...inProgressTasks, ...completedTasks];

    if (allTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.task_alt_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Henüz görev yok',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Planlama sekmesinden görev ekleyin',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: allTasks.length + 1, // +1 for section divider
      separatorBuilder: (context, index) {
        // Add a divider between in-progress and completed sections
        if (index == inProgressTasks.length && inProgressTasks.isNotEmpty && completedTasks.isNotEmpty) {
          return const Divider(height: 32);
        }
        return const Divider(height: 1);
      },
      itemBuilder: (context, index) {
        // Section header for completed tasks
        if (index == inProgressTasks.length && inProgressTasks.isNotEmpty && completedTasks.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Tamamlananlar',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        // Adjust index for completed tasks
        final taskIndex = index > inProgressTasks.length ? index - 1 : index;
        if (taskIndex >= allTasks.length) return const SizedBox.shrink();

        final task = allTasks[taskIndex];
        final isCompleted = task.isCompleted;

        return ListTile(
          leading: Icon(
            isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isCompleted
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(
            task.title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: isCompleted
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
              decoration: isCompleted ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: task.description.isNotEmpty
              ? Text(
                  task.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: isCompleted
              ? Icon(
                  Icons.done_all,
                  color: theme.colorScheme.primary,
                  size: 20,
                )
              : null,
          onTap: () => context.pop(task),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        );
      },
    );
  }
}