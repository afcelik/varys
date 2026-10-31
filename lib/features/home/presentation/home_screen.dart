import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/home/domain/today_provider.dart';
import 'package:varys/features/home/presentation/providers/daily_plan_provider.dart';
import 'package:varys/features/home/presentation/widgets/date_header.dart';
import 'package:varys/features/home/presentation/widgets/focus_cards.dart';
import 'package:varys/features/home/presentation/widgets/say_no_card.dart';
import 'package:varys/features/home/presentation/widgets/daily_plan_state_widgets.dart';
import 'package:varys/features/home/presentation/widgets/inbox_card.dart';
import 'package:varys/features/home/presentation/widgets/random_note_card.dart';

/// Home screen - main dashboard view with "Today" mode
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayProvider);
    final dailyPlanAsync = ref.watch(dailyPlanProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ana Sayfa'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ayarlar',
            onPressed: () => context.push(AppRouter.settingsPath),
          ),
        ],
      ),
      body: SafeArea(
        child: dailyPlanAsync.when(
          data: (plan) => _buildPlanContent(context, theme, today, plan),
          loading: () => _buildLoadingContent(context),
          error: (error, stack) => _buildErrorContent(context, ref, error.toString()),
        ),
      ),
    );
  }

  Widget _buildPlanContent(
    BuildContext context,
    ThemeData theme,
    DateTime today,
    dynamic plan,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 800;

          if (isWide) {
            return _buildWideLayout(context, theme, today, plan);
          } else {
            return _buildNarrowLayout(context, theme, today, plan);
          }
        },
      ),
    );
  }

  Widget _buildWideLayout(
    BuildContext context,
    ThemeData theme,
    DateTime today,
    dynamic plan,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DateHeader(date: today),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MainFocusCard(plan: plan),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  SideFocusCard(plan: plan),
                  const SizedBox(height: 12),
                  SayNoCard(plan: plan),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildPlaceholderCards(context, theme),
      ],
    );
  }

  Widget _buildNarrowLayout(
    BuildContext context,
    ThemeData theme,
    DateTime today,
    dynamic plan,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DateHeader(date: today),
        const SizedBox(height: 16),
        MainFocusCard(plan: plan),
        const SizedBox(height: 12),
        SideFocusCard(plan: plan),
        const SizedBox(height: 12),
        SayNoCard(plan: plan),
        const SizedBox(height: 24),
        _buildPlaceholderCards(context, theme),
      ],
    );
  }

  Widget _buildPlaceholderCards(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Diğer Kategoriler',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        const RandomNoteCard(),
        const SizedBox(height: 16),
        const InboxCard(),
      ],
    );
  }

  Widget _buildLoadingContent(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: DailyPlanLoading(),
    );
  }

  Widget _buildErrorContent(BuildContext context, WidgetRef ref, String error) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: DailyPlanError(
        message: error,
        onRetry: () => ref.invalidate(dailyPlanProvider),
      ),
    );
  }
}