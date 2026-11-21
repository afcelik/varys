import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/routines/domain/recurrence_form.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/schedule_list_notifier.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Full-screen schedule page (outside the shell): every block with its time
/// range, title and recurrence summary; add, edit (row tap) and delete.
/// On reload the current list stays visible.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  static const String title = 'Günlük Program';
  static const String addText = 'Blok ekle';
  static const String emptyText = 'Henüz program bloğu yok';
  static const String retryText = 'Tekrar dene';
  static const String deleteTooltip = 'Sil';
  static const String deleteQuestion = 'Bu blok silinsin mi?';
  static const String deleteConfirmText = 'Sil';
  static const String deleteCancelText = 'Vazgeç';

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  /// Block ids with a delete request in flight.
  final Set<int> _deleting = <int>{};

  void _openNew() => context.push(AppRouter.scheduleNewPath);

  void _openEdit(ScheduleBlock block) => context.push(AppRouter.scheduleEditPath, extra: block);

  Future<void> _delete(ScheduleBlock block) async {
    if (_deleting.contains(block.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(blockTitle: block.title),
    );
    if (confirmed != true || !mounted || _deleting.contains(block.id)) return;

    setState(() => _deleting.add(block.id));
    final result = await ref.read(scheduleBlocksProvider.notifier).deleteBlock(block.id);
    if (!mounted) return;
    setState(() => _deleting.remove(block.id));
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
      ),
      (_) {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(scheduleBlocksProvider);

    final Widget body;
    if (value.hasValue) {
      final blocks = value.requireValue;
      body = blocks.isEmpty
          ? _EmptySchedule(onAdd: _openNew)
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: blocks.length,
              itemBuilder: (context, index) {
                final block = blocks[index];
                return _BlockRow(
                  key: ValueKey('schedule-list-row-${block.id}'),
                  block: block,
                  deleting: _deleting.contains(block.id),
                  onTap: () => _openEdit(block),
                  onDelete: () => _delete(block),
                );
              },
            );
    } else if (value.hasError) {
      body = _ScheduleError(
        message: userMessage(value.error!),
        onRetry: () => ref.invalidate(scheduleBlocksProvider),
      );
    } else {
      body = const Center(key: ValueKey('schedule-loading'), child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: const Text(ScheduleScreen.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('schedule-add'),
            icon: const Icon(Icons.add),
            tooltip: ScheduleScreen.addText,
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

/// Time range, title (max 2 lines) and recurrence summary; the row tap
/// (edit) and the delete button are separate targets.
class _BlockRow extends StatelessWidget {
  const _BlockRow({
    super.key,
    required this.block,
    required this.deleting,
    required this.onTap,
    required this.onDelete,
  });

  final ScheduleBlock block;
  final bool deleting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              key: ValueKey('schedule-list-tap-${block.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      formatTimeRange(block.startTime, block.endTime),
                      key: ValueKey('schedule-list-time-${block.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    Text(
                      block.title,
                      key: ValueKey('schedule-list-title-${block.id}'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      recurrenceSummaryOf(
                        block.recurrenceType,
                        daysOfWeek: block.daysOfWeek,
                        dayOfMonth: block.dayOfMonth,
                        intervalDays: block.intervalDays,
                        startDate: block.startDate,
                      ),
                      key: ValueKey('schedule-list-summary-${block.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('schedule-delete-${block.id}'),
            icon: const Icon(Icons.delete_outline),
            tooltip: ScheduleScreen.deleteTooltip,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: deleting ? null : onDelete,
          ),
        ],
      ),
    );
  }
}

/// Confirmation dialog. The first tap on "Sil" closes it; later taps (while
/// the close animation runs) are ignored, so a double tap pops only once.
class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog({required this.blockTitle});

  final String blockTitle;

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
      title: const Text(ScheduleScreen.deleteQuestion),
      content: Text(widget.blockTitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      actions: [
        TextButton(
          onPressed: () => _close(false),
          child: const Text(ScheduleScreen.deleteCancelText),
        ),
        FilledButton(
          key: const ValueKey('schedule-delete-confirm'),
          onPressed: () => _close(true),
          child: const Text(ScheduleScreen.deleteConfirmText),
        ),
      ],
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule({required this.onAdd});

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
              ScheduleScreen.emptyText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('schedule-empty-add'),
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text(ScheduleScreen.addText),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleError extends StatelessWidget {
  const _ScheduleError({required this.message, required this.onRetry});

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
              key: const ValueKey('schedule-retry'),
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(ScheduleScreen.retryText),
            ),
          ],
        ),
      ),
    );
  }
}
