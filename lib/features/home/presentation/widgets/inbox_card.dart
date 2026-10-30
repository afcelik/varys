import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/router/app_router.dart';

/// Card widget showing inbox status on the Home screen.
///
/// Displays "No new items" with a "More" button that navigates to the Inbox screen.
/// Uses [context.push()] so the back button returns to Home.
class InboxCard extends StatelessWidget {
  const InboxCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Gelen Kutusu',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push(AppRouter.inboxPath),
                  child: const Text('Daha Fazla'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Yeni öğe yok',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Gelen bildirimler burada görünecek',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}