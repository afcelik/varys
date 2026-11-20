import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/schedule/domain/schedule_block.dart';
import 'package:varys/features/schedule/domain/schedule_form.dart';
import 'package:varys/features/schedule/presentation/minute_ticker.dart';
import 'package:varys/features/schedule/presentation/schedule_day_notifier.dart';

/// Home card with today's schedule blocks: time range + title per row, the
/// current block highlighted with a "Şimdi" label (text, not only color),
/// past blocks dimmed, and a quick-add field. At most [maxRows] rows; the
/// rest are behind "Tümünü gör (+N)". Loading and errors stay inside this
/// card; on reload the previous rows stay visible.
///
/// The whole card sits under a [MinuteTicker]: the "Şimdi" marker moves every
/// minute, and at midnight the ticker moves today to the new day, so the card
/// loads the new day's blocks.
class ScheduleCard extends ConsumerWidget {
  const ScheduleCard({super.key});

  static const String title = 'Günlük Program';
  static const String emptyText = 'Bugün için program yok';
  static const String moreText = 'Daha fazla';
  static const String addTooltip = 'Blok ekle';
  static const String retryText = 'Tekrar dene';
  static const String nowLabel = 'Şimdi';
  static const String quickAddHint = 'Örn: 08:30-09:00 kahvaltı';
  static const int maxRows = 8;

  static String seeAllText(int hidden) => 'Tümünü gör (+$hidden)';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MinuteTicker(builder: (context, now) => _ScheduleCardBody(now: now));
  }
}

class _ScheduleCardBody extends ConsumerWidget {
  const _ScheduleCardBody({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final value = ref.watch(todayScheduleProvider);

    final Widget body;
    var hidden = 0;
    if (value.hasError && !value.isLoading) {
      body = _ScheduleCardError(
        message: userMessage(value.error!),
        onRetry: () => ref.invalidate(scheduleForDayProvider(today)),
      );
    } else if (value.hasValue) {
      final blocks = value.requireValue;
      final shown = blocks.take(ScheduleCard.maxRows).toList();
      hidden = blocks.length - shown.length;
      final minute = minuteOfDay(now);
      body = blocks.isEmpty
          ? const _EmptySchedule()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final block in shown)
                  _ScheduleRow(
                    key: ValueKey('schedule-row-${block.id}'),
                    block: block,
                    status: blockStatusAt(block, minute),
                  ),
              ],
            );
    } else {
      body = const _ScheduleCardSkeleton();
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, size: 24, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ScheduleCard.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('schedule-card-add'),
                  icon: const Icon(Icons.add),
                  tooltip: ScheduleCard.addTooltip,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () => context.push(AppRouter.scheduleNewPath),
                ),
              ],
            ),
            const SizedBox(height: 8),
            body,
            const SizedBox(height: 8),
            const _QuickAddField(),
            Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (hidden > 0)
                  TextButton(
                    key: const ValueKey('schedule-card-see-all'),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    onPressed: () => context.push(AppRouter.schedulePath),
                    child: Text(ScheduleCard.seeAllText(hidden)),
                  ),
                TextButton(
                  key: const ValueKey('schedule-card-more'),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => context.push(AppRouter.schedulePath),
                  child: const Text(ScheduleCard.moreText),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One block: fixed-width time column (tabular figures; the "Şimdi" label
/// under the time of the current block) and the title (max 2 lines). Tapping
/// the row opens the edit form.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({super.key, required this.block, required this.status});

  final ScheduleBlock block;
  final BlockStatus status;

  static const _sample = '00:00\u201300:00';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNow = status == BlockStatus.current;
    final timeStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: isNow ? FontWeight.w600 : null,
      color: isNow ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
    );
    // Width of the widest time range in this style and text scale.
    final painter = TextPainter(
      text: TextSpan(
        text: _sample,
        style: timeStyle?.copyWith(fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final timeWidth = painter.width.ceilToDouble();
    painter.dispose();

    final row = InkWell(
      key: ValueKey('schedule-row-tap-${block.id}'),
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.push(AppRouter.scheduleEditPath, extra: block),
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: isNow
            ? BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: theme.colorScheme.primary, width: 3)),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: timeWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    formatTimeRange(block.startTime, block.endTime),
                    key: ValueKey('schedule-time-${block.id}'),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.clip,
                    style: timeStyle,
                  ),
                  if (isNow)
                    Text(
                      ScheduleCard.nowLabel,
                      key: ValueKey('schedule-now-${block.id}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                block.title,
                key: ValueKey('schedule-title-${block.id}'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: isNow ? FontWeight.w600 : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Past blocks are dimmed but stay readable.
    return status == BlockStatus.past
        ? Opacity(key: ValueKey('schedule-past-${block.id}'), opacity: 0.6, child: row)
        : row;
  }
}

/// Quick add: "08:30-09:00 kahvaltı" + Enter creates a daily block from
/// today. A parse error shows a message under the field and sends nothing;
/// while the request runs the field is disabled (a second Enter sends
/// nothing); on success the field is cleared; on a server error the text
/// stays and a snackbar shows the message.
class _QuickAddField extends ConsumerStatefulWidget {
  const _QuickAddField();

  @override
  ConsumerState<_QuickAddField> createState() => _QuickAddFieldState();
}

class _QuickAddFieldState extends ConsumerState<_QuickAddField> {
  final _controller = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit(String text) async {
    if (_sending) return;
    switch (parseQuickAdd(text)) {
      case QuickAddError(:final message):
        setState(() => _error = message);
      case final QuickAddOk parsed:
        setState(() {
          _error = null;
          _sending = true;
        });
        final day = ref.read(todayProvider);
        final result = await ref.read(scheduleForDayProvider(day).notifier).quickAdd(parsed);
        if (!mounted) return;
        setState(() => _sending = false);
        result.fold(
          (failure) => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
          ),
          (_) => _controller.clear(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('schedule-quick-add'),
      controller: _controller,
      enabled: !_sending,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: ScheduleCard.quickAddHint,
        hintMaxLines: 1,
        errorText: _error,
        errorMaxLines: 3,
        prefixIcon: const Icon(Icons.bolt_outlined),
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: _submit,
    );
  }
}

class _EmptySchedule extends StatelessWidget {
  const _EmptySchedule();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        ScheduleCard.emptyText,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _ScheduleCardSkeleton extends StatelessWidget {
  const _ScheduleCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return Column(
      key: const ValueKey('schedule-skeleton'),
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

class _ScheduleCardError extends StatelessWidget {
  const _ScheduleCardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          message,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('schedule-card-retry'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text(ScheduleCard.retryText),
        ),
      ],
    );
  }
}
