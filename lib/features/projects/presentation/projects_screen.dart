import 'package:flutter/material.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Full-screen projects page (outside the shell, opened with push from the
/// Home "Aktif Projeler" card). Placeholder until project management lands.
class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  static const String title = 'Projeler';
  static const String placeholderText = 'Proje yönetimi bir sonraki adımda eklenecek';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: const Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Text(
              placeholderText,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
