import 'package:flutter/material.dart';

/// Read-only tag chips of a note: at most [maxVisible] tags, then a "+N"
/// chip for the rest. Each tag is one line, cut with an ellipsis when it is
/// wider than the row. Not tappable (no tap target).
class NoteTagChips extends StatelessWidget {
  const NoteTagChips({super.key, required this.tags, this.maxVisible = 3});

  final List<String> tags;
  final int maxVisible;

  static String moreText(int hidden) => '+$hidden';

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final visible = tags.take(maxVisible).toList();
    final hidden = tags.length - visible.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in visible) _TagLabel(text: tag),
        if (hidden > 0) _TagLabel(key: const ValueKey('note-tags-more'), text: moreText(hidden)),
      ],
    );
  }
}

class _TagLabel extends StatelessWidget {
  const _TagLabel({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
