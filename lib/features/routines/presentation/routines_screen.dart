import 'package:flutter/material.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Full-screen routines page (outside the shell). Placeholder until routine
/// management is added.
class RoutinesScreen extends StatelessWidget {
  const RoutinesScreen({super.key});

  static const String placeholderText = 'Rutin yönetimi bir sonraki adımda eklenecek';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: const Text('Rutinler'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            placeholderText,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
