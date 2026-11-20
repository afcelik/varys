import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/presentation/today_note_notifier.dart';
import 'package:varys/features/notes/presentation/widgets/note_markdown.dart';
import 'package:varys/features/notes/presentation/widgets/note_tag_chips.dart';

/// Home "Günün Notu" card with the note of the day ([todayNoteProvider]):
/// title (2 lines), the first lines of the body rendered as Markdown
/// ([NoteMarkdown] card: 3 lines, marks hidden, nothing tappable inside),
/// up to 3 tags and "+N". Tapping that
/// content (one InkWell, at least 48 high, semantics "Notu düzenle") pushes
/// the note edit page with the Note as `extra`. No notes → "Henüz not yok"
/// with "Not ekle". Loading and errors stay inside this card; "Tekrar dene"
/// reloads only the card. While refreshing, the previous note stays.
/// "Daha fazla" and "Not ekle" open the notes page with `push`; both sit
/// outside the content InkWell, so they never open the edit page.
class RandomNoteCard extends ConsumerWidget {
  const RandomNoteCard({super.key});

  static const String title = 'Günün Notu';
  static const String emptyText = 'Henüz not yok';
  static const String addText = 'Not ekle';
  static const String moreText = 'Daha fazla';
  static const String retryText = 'Tekrar dene';
  static const String editSemantics = 'Notu düzenle';

  static const int titleMaxLines = 2;
  static const int bodyMaxLines = NoteMarkdown.cardMaxLines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final value = ref.watch(todayNoteProvider);

    final Widget body;
    if (value.hasError && !value.isLoading) {
      body = _NoteCardError(
        message: userMessage(value.error!),
        onRetry: () => ref.invalidate(todayNoteProvider),
      );
    } else if (value.hasValue) {
      final note = value.requireValue;
      body = note == null
          ? _EmptyNote(onAdd: () => context.push(AppRouter.notesPath))
          : _OpenNote(
              onTap: () => context.push(AppRouter.notesEditPath, extra: note),
              child: _NoteContent(note: note),
            );
    } else {
      body = const _NoteCardSkeleton();
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.note_alt_outlined, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  key: const ValueKey('random-note-more'),
                  onPressed: () => context.push(AppRouter.notesPath),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text(moreText),
                ),
              ],
            ),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}

/// The tappable content area: one InkWell around title, body and tags,
/// at least 48 high. The card's buttons are not inside it.
class _OpenNote extends StatelessWidget {
  const _OpenNote({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: RandomNoteCard.editSemantics,
      child: InkWell(
        key: const ValueKey('random-note-open'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(constraints: const BoxConstraints(minHeight: 48), child: child),
      ),
    );
  }
}

class _NoteContent extends StatelessWidget {
  const _NoteContent({required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = note.body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          note.title,
          key: const ValueKey('random-note-title'),
          maxLines: RandomNoteCard.titleMaxLines,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (body != null) ...[
          const SizedBox(height: 6),
          NoteMarkdown(
            key: const ValueKey('random-note-body'),
            data: body,
            mode: NoteMarkdownMode.card,
          ),
        ],
        if (note.tags.isNotEmpty) ...[const SizedBox(height: 8), NoteTagChips(tags: note.tags)],
      ],
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          RandomNoteCard.emptyText,
          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('random-note-add'),
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text(RandomNoteCard.addText),
          style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
        ),
      ],
    );
  }
}

class _NoteCardSkeleton extends StatelessWidget {
  const _NoteCardSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      ),
    );
    return Column(
      key: const ValueKey('random-note-skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [bar(0.6, 20), bar(1, 14), bar(0.8, 14)],
    );
  }
}

class _NoteCardError extends StatelessWidget {
  const _NoteCardError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        children: [
          Text(
            message,
            key: const ValueKey('random-note-error'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('random-note-retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text(RandomNoteCard.retryText),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        ],
      ),
    );
  }
}
