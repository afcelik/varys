import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/features/home/domain/daily_plan.dart';
import 'package:varys/features/home/domain/focus_candidates.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/home/presentation/widgets/add_from_planning_sheet.dart';
import 'package:varys/features/planning/domain/task.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Full-screen page for choosing the focus task of [slot] from today's
/// plan ("Bugün Yapılacaklar"). Opened via context.push() from the focus cards.
///
/// Pop contract: returns the chosen [Task], or null when nothing changes
/// (back, or tapping the slot's current focus). Null never clears a focus;
/// clearing is done from the card's "Temizle" action.
class FocusTaskSelectionPage extends ConsumerWidget {
  const FocusTaskSelectionPage({super.key, required this.slot});

  final FocusSlot slot;

  static const String mainTitle = 'Ana odak seç';
  static const String sideTitle = 'İkincil odak seç';
  static const String emptyMessage = 'Bugün için seçilebilecek görev yok';
  static const String retryLabel = 'Tekrar dene';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(dailyPlanProvider);
    // A loaded plan stays on screen while it reloads (invalidate, or after
    // addTasksToDay); spinner/error only when there is no plan yet.
    final plan = planAsync.valueOrNull;

    final Widget body;
    if (plan != null) {
      body = _CandidateList(plan: plan, slot: slot);
    } else if (planAsync.hasError && !planAsync.isLoading) {
      body = _ErrorView(
        message: userMessage(planAsync.error!),
        onRetry: () => ref.invalidate(dailyPlanProvider),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        leading: const BackArrow(),
        title: Text(slot == FocusSlot.main ? mainTitle : sideTitle),
        actions: [
          // Tap target pinned to at least 48x48 on every platform.
          IconButton(
            onPressed: () => showAddFromPlanningSheet(context),
            tooltip: AddFromPlanningSheet.title,
            icon: const Icon(Icons.playlist_add),
            visualDensity: VisualDensity.standard,
            style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.padded),
          ),
        ],
      ),
      body: body,
    );
  }
}

class _CandidateList extends StatelessWidget {
  const _CandidateList({required this.plan, required this.slot});

  final DailyPlan plan;
  final FocusSlot slot;

  @override
  Widget build(BuildContext context) {
    final candidates = buildFocusCandidates(plan, slot);
    if (candidates.isEmpty) return const _EmptyView();

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: candidates.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) => _CandidateTile(candidate: candidates[index]),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate});

  final FocusCandidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = candidate.task;

    final title = Text(
      task.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium,
    );
    final leading = Icon(
      task.status == TaskStatus.inProgress ? Icons.timelapse : Icons.radio_button_unchecked,
      color: theme.colorScheme.onSurfaceVariant,
    );

    switch (candidate.state) {
      case FocusCandidateState.selectable:
        return ListTile(
          leading: leading,
          title: title,
          onTap: () => context.pop(task),
        );
      case FocusCandidateState.selected:
        return ListTile(
          leading: leading,
          title: title,
          trailing: Icon(Icons.check_circle, color: theme.colorScheme.primary),
          selected: true,
          // Already this slot's focus: go back without a change.
          onTap: () => context.pop(),
        );
      case FocusCandidateState.blockedByOther:
      case FocusCandidateState.pending:
        return Opacity(
          opacity: 0.5,
          child: ListTile(
            enabled: false,
            leading: leading,
            title: title,
            trailing: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                candidate.label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium,
              ),
            ),
          ),
        );
    }
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              FocusTaskSelectionPage.emptyMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => showAddFromPlanningSheet(context),
              icon: const Icon(Icons.playlist_add),
              label: const Text(AddFromPlanningSheet.title),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

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
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text(FocusTaskSelectionPage.retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the focus selection route is opened without a [FocusSlot]
/// extra (deep link, notification, wrong type). No silent default slot.
class FocusSelectionUnavailablePage extends StatelessWidget {
  const FocusSelectionUnavailablePage({super.key});

  static const String message = 'Bu sayfa doğrudan açılamaz.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: const BackArrow()),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
