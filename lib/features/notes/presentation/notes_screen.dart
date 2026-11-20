import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';
import 'package:varys/features/notes/presentation/notes_list_notifier.dart';
import 'package:varys/features/notes/presentation/widgets/note_tag_chips.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Notes page (`/notes`, opened with push; outside the menu).
///
/// Every note is loaded once ([notesListProvider]); search, "Favoriler" and
/// the tag chips filter on the client ([notesFilterProvider], [filterNotes])
/// and send no request. A row opens the edit form; its star toggles the
/// favorite (not optimistic: the row waits for the server); its delete
/// button asks first. States: loading (skeleton), error with "Tekrar dene",
/// no notes, no match for the filters, list.
class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});

  static const String title = 'Notlar';
  static const String addText = 'Not ekle';
  static const String searchHint = 'Notlarda ara';
  static const String clearSearchTooltip = 'Aramayı temizle';
  static const String favoritesText = 'Favoriler';
  static const String emptyText = 'Henüz not yok';
  static const String noMatchText = 'Eşleşen not yok';
  static const String clearFiltersText = 'Süzgeçleri temizle';
  static const String retryText = 'Tekrar dene';
  static const String favoriteAddTooltip = 'Favorilere ekle';
  static const String favoriteRemoveTooltip = 'Favorilerden çıkar';
  static const String deleteTooltip = 'Sil';
  static const String deleteQuestion = 'Bu not silinsin mi?';
  static const String deleteConfirmText = 'Sil';
  static const String deleteCancelText = 'Vazgeç';

  static const int titleMaxLines = 2;
  static const int bodyMaxLines = 2;

  /// Tag chip label width limit, so one long tag never fills the row.
  static const double tagChipMaxWidth = 220;

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  late final TextEditingController _search;

  /// Note ids with a favorite or delete request in flight (row disabled).
  final Set<int> _busy = <int>{};

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(notesFilterProvider).query);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  NotesFilterNotifier get _filter => ref.read(notesFilterProvider.notifier);

  void _openNew() => context.push(AppRouter.notesNewPath);

  void _openEdit(Note note) => context.push(AppRouter.notesEditPath, extra: note);

  void _clearFilters() {
    _search.clear();
    _filter.clear();
  }

  void _showError(Object failure) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _toggleFavorite(Note note) async {
    if (_busy.contains(note.id)) return;
    setState(() => _busy.add(note.id));
    final result = await ref.read(notesListProvider.notifier).toggleFavorite(note);
    if (!mounted) return;
    setState(() => _busy.remove(note.id));
    result.fold(_showError, (_) {});
  }

  Future<void> _delete(Note note) async {
    if (_busy.contains(note.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(noteTitle: note.title),
    );
    if (confirmed != true || !mounted || _busy.contains(note.id)) return;

    setState(() => _busy.add(note.id));
    final result = await ref.read(notesListProvider.notifier).deleteNote(note.id);
    if (!mounted) return;
    setState(() => _busy.remove(note.id));
    result.fold(_showError, (_) {});
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(notesListProvider);
    final filter = ref.watch(notesFilterProvider);
    final overview = value.valueOrNull;

    final Widget body;
    if (value.hasError && !value.isLoading) {
      body = _NotesError(
        message: userMessage(value.error!),
        onRetry: () => ref.invalidate(notesListProvider),
      );
    } else if (overview != null) {
      body = overview.notes.isEmpty
          ? _CenteredMessage(
              text: NotesScreen.emptyText,
              buttonKey: const ValueKey('notes-empty-add'),
              buttonText: NotesScreen.addText,
              onPressed: _openNew,
            )
          : _buildFiltered(overview, filter);
    } else {
      body = const _NotesSkeleton();
    }

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: const Text(NotesScreen.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            key: const ValueKey('notes-add'),
            icon: const Icon(Icons.add),
            tooltip: NotesScreen.addText,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _openNew,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: body),
    );
  }

  Widget _buildFiltered(NotesOverview overview, NotesFilter filter) {
    final visible = filterNotes(
      overview.notes,
      query: filter.query,
      tag: filter.tag,
      favoritesOnly: filter.favoritesOnly,
    );
    // A selected tag that no note uses any more still gets a chip, so it can
    // be removed.
    final tags = [
      ...overview.tags,
      if (filter.tag != null && !overview.tags.any((t) => t.name == filter.tag))
        TagCount(name: filter.tag!, noteCount: 0),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: _SearchField(controller: _search, onChanged: _filter.setQuery),
        ),
        _FilterChips(
          tags: tags,
          filter: filter,
          onFavorites: _filter.toggleFavorites,
          onTag: _filter.toggleTag,
        ),
        Expanded(
          child: visible.isEmpty
              ? _CenteredMessage(
                  text: NotesScreen.noMatchText,
                  buttonKey: const ValueKey('notes-clear-filters'),
                  buttonText: NotesScreen.clearFiltersText,
                  onPressed: _clearFilters,
                )
              : ListView.builder(
                  key: const ValueKey('notes-list'),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final note = visible[index];
                    return _NoteRow(
                      key: ValueKey('note-${note.id}'),
                      note: note,
                      busy: _busy.contains(note.id),
                      onTap: () => _openEdit(note),
                      onFavorite: () => _toggleFavorite(note),
                      onDelete: () => _delete(note),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        key: const ValueKey('notes-search'),
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: NotesScreen.searchHint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  key: const ValueKey('notes-search-clear'),
                  icon: const Icon(Icons.close),
                  tooltip: NotesScreen.clearSearchTooltip,
                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// "Favoriler" plus one chip per tag with its count, in one horizontally
/// scrolled row. Tapping the selected tag again removes it.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.tags,
    required this.filter,
    required this.onFavorites,
    required this.onTag,
  });

  final List<TagCount> tags;
  final NotesFilter filter;
  final VoidCallback onFavorites;
  final ValueChanged<String> onTag;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('notes-chips'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          FilterChip(
            key: const ValueKey('notes-chip-favorites'),
            avatar: const Icon(Icons.star, size: 18),
            label: const Text(NotesScreen.favoritesText),
            selected: filter.favoritesOnly,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => onFavorites(),
          ),
          for (final tag in tags) ...[
            const SizedBox(width: 8),
            FilterChip(
              key: ValueKey('notes-chip-tag-${tag.name}'),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: NotesScreen.tagChipMaxWidth),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(tag.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(' ${tag.noteCount}'),
                  ],
                ),
              ),
              selected: filter.tag == tag.name,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              onSelected: (_) => onTag(tag.name),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    super.key,
    required this.note,
    required this.busy,
    required this.onTap,
    required this.onFavorite,
    required this.onDelete,
  });

  final Note note;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = note.body;
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      note.title,
                      key: ValueKey('note-title-${note.id}'),
                      maxLines: NotesScreen.titleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium,
                    ),
                    if (body != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        key: ValueKey('note-body-${note.id}'),
                        maxLines: NotesScreen.bodyMaxLines,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (note.tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      NoteTagChips(tags: note.tags),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              key: ValueKey('note-favorite-${note.id}'),
              icon: Icon(note.isFavorite ? Icons.star : Icons.star_border),
              color: note.isFavorite ? theme.colorScheme.primary : null,
              tooltip: note.isFavorite
                  ? NotesScreen.favoriteRemoveTooltip
                  : NotesScreen.favoriteAddTooltip,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: busy ? null : onFavorite,
            ),
            IconButton(
              key: ValueKey('note-delete-${note.id}'),
              icon: const Icon(Icons.delete_outline),
              tooltip: NotesScreen.deleteTooltip,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: busy ? null : onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation; a second tap on a button after the first does nothing.
class _DeleteConfirmDialog extends StatefulWidget {
  const _DeleteConfirmDialog({required this.noteTitle});

  final String noteTitle;

  @override
  State<_DeleteConfirmDialog> createState() => _DeleteConfirmDialogState();
}

class _DeleteConfirmDialogState extends State<_DeleteConfirmDialog> {
  bool _closed = false;

  void _close(bool confirmed) {
    if (_closed) return;
    _closed = true;
    Navigator.of(context).pop(confirmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.noteTitle, maxLines: 3, overflow: TextOverflow.ellipsis),
      content: const Text(NotesScreen.deleteQuestion),
      actions: [
        TextButton(onPressed: () => _close(false), child: const Text(NotesScreen.deleteCancelText)),
        FilledButton(
          key: const ValueKey('note-delete-confirm'),
          onPressed: () => _close(true),
          child: const Text(NotesScreen.deleteConfirmText),
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.text,
    required this.buttonKey,
    required this.buttonText,
    required this.onPressed,
  });

  final String text;
  final Key buttonKey;
  final String buttonText;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: buttonKey,
              onPressed: onPressed,
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(buttonText),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotesError extends StatelessWidget {
  const _NotesError({required this.message, required this.onRetry});

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
            Text(
              message,
              key: const ValueKey('notes-error'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const ValueKey('notes-retry'),
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(NotesScreen.retryText),
            ),
          ],
        ),
      ),
    );
  }
}

/// Static placeholder rows (no animation).
class _NotesSkeleton extends StatelessWidget {
  const _NotesSkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3);
    return ListView(
      key: const ValueKey('notes-skeleton'),
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            height: 56,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
          ),
      ],
    );
  }
}
