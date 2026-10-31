import 'package:flutter/material.dart';
import 'package:varys/features/home/data/date_utils.dart';

/// Header widget showing today's date in Turkish format.
/// Example: "Cuma, 30 Ekim"
class DateHeader extends StatelessWidget {
  const DateHeader({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedDate = formatDateForDisplay(date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        formattedDate,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}