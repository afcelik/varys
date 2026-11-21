import 'package:flutter/material.dart';
import 'package:varys/features/home/data/date_utils.dart';

/// Header widget showing today's date in Turkish format.
/// Example: "Cuma, 30 Ekim"
///
/// With [onTap] the whole header is one button (at least 48 high, Semantics
/// label 'Takvimi aç', the date as its value); without it, plain text.
class DateHeader extends StatelessWidget {
  const DateHeader({super.key, required this.date, this.onTap});

  final DateTime date;
  final VoidCallback? onTap;

  static const String openCalendarLabel = 'Takvimi aç';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedDate = formatDateForDisplay(date);

    final text = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        formattedDate,
        style: theme.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
    final tap = onTap;
    if (tap == null) return text;

    return Semantics(
      button: true,
      label: openCalendarLabel,
      value: formattedDate,
      child: InkWell(
        key: const ValueKey('date-header-tap'),
        borderRadius: BorderRadius.circular(8),
        onTap: tap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          // The date is the value above; the text itself is not read twice.
          child: Align(alignment: Alignment.centerLeft, child: ExcludeSemantics(child: text)),
        ),
      ),
    );
  }
}
