import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/routines/domain/routine.dart';
import 'package:varys/features/routines/presentation/routines_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Full-screen routines page (outside the shell): list, add, edit, delete.
/// Streaks are not shown (GET /routines carries none).
class RoutinesScreen extends ConsumerStatefulWidget {
  const RoutinesScreen({super.key});

  static const String title = 'Rutinler';
  static const String addText = 'Rutin ekle';
  static const String emptyText = 'Henüz rutin yok';
  static const String retryText = 'Tekrar dene';
  static const String deleteTooltip = 'Sil';
  static const String deleteQuestion = 'Bu rutin silinsin mi?';
  static const String deleteConfirmText = 'Sil';
  static const String deleteCancelText = 'Vazgeç';

  @override
  ConsumerState<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends ConsumerState<RoutinesScreen> {
  /// Routine ids with a delete request in flight.
  final Set<int> _deleting = <int>{};

  void _openNew() => context.push(AppRouter.routinesNewPath);

  void _openEdit(Routine routine) => context.push(AppRouter.routinesEditPath, extra: routine);

  Future<void> _delete(Routine routine) async {
    if (_deleting.contains(routine.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(routineTitle: routine.title),
    );
    if (confirmed != true || !mounted || _deleting.contains(routine.id)) return;

    setState(() => _deleting.add(routine.id));
    final result = await ref.read(routinesListProvider.notifier).deleteRoutine(routine.id);
    if (!mounted) return;
    setState(() => _deleting.remove(routine.id));
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
      ),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(routinesListProvider);

    final Widget body;
    if (value.hasValue) {
      final routines = value.requireValue;
      body = routines.isEmpty
          ? _EmptyRoutines(onAdd: _openNew)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: routines.length,
              itemBuilder: (context, index) {
                final routine = routines[index];
                return _RoutineRow(
                  key: ValueKey('routine-row-${routine.id}'),
                  routine: routine,
                  deleting: _deleting.contains(routine.id),
                  onTap: () => _openEdit(routine),
                  onDelete: () => _delete(routine),
                );
              },
            );
    } else if (value.hasError) {
      body = _RoutinesError(
        message: userMessage(value.error!),
        onRetry: () => ref.invalidate(routinesListProvider),
      );
    } else {
      body = const Center(key: ValueKey('routines-loading'), child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: const Text(RoutinesScreen.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('routines-add'),
            icon: const Icon(Icons.add),
            tooltip: RoutinesScreen.addText,
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

class _RoutineRow extends StatelessWidget {
  const _RoutineRow({
    super.key,
    required this.routine,
    required this.deleting,
    required this.onTap,
    required this.onDelete,
  });

  final Routine routine;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      minTileHeight: 56,
      onTap: onTap,
      title: Text(routine.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        recurrenceSummary(routine),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: IconButton(
        key: ValueKey('routine-delete-${routine.id}'),
        icon: const Icon(Icons.delete_outline),
        tooltip: RoutinesScreen.deleteTooltip,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: deleting ? null : onDelete,
      ),
    );
  }
}

/// Confirmation dialog. The first tap on "Sil" closes it; later taps (while
/// the close animation runs) are ignored, so a double tap pops only once.
class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog({required this.routineTitle});

  final String routineTitle;

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
      title: const Text(RoutinesScreen.deleteQuestion),
      content: Text(widget.routineTitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      actions: [
        TextButton(
          onPressed: () => _close(false),
          child: const Text(RoutinesScreen.deleteCancelText),
        ),
        FilledButton(
          onPressed: () => _close(true),
          child: const Text(RoutinesScreen.deleteConfirmText),
        ),
      ],
    );
  }
}

class _EmptyRoutines extends StatelessWidget {
  const _EmptyRoutines({required this.onAdd});

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
              RoutinesScreen.emptyText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('routines-empty-add'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text(RoutinesScreen.addText),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutinesError extends StatelessWidget {
  const _RoutinesError({required this.message, required this.onRetry});

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
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(RoutinesScreen.retryText),
            ),
          ],
        ),
      ),
    );
  }
}
