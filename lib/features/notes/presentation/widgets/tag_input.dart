import 'package:flutter/material.dart';
import 'package:varys/features/notes/domain/note_form.dart';

/// Tag editor of the note form: the current tags as chips (each with a
/// 48x48 remove button), a text field and suggestions.
///
/// A typed comma or Enter adds the tag (normalized the Turkish way: 'İş' →
/// 'iş'); pasted comma-separated text adds every part ([applyTagInput]).
/// Duplicates are dropped silently; invalid parts and tags beyond the limit
/// are skipped with a message. At [maxTagsPerNote] tags the field is
/// disabled and the limit message is shown. [suggestions] (tag names from
/// `/tags`) lists only tags not added yet, filtered by the typed text; a tap
/// adds one. No suggestions (e.g. `/tags` failed) is fine.
class TagInput extends StatefulWidget {
  const TagInput({
    super.key,
    required this.tags,
    required this.onChanged,
    this.suggestions = const [],
    this.enabled = true,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final List<String> suggestions;
  final bool enabled;

  static const String label = 'Etiketler';
  static const String hint = 'Etiket yaz, Enter ya da virgülle ekle';
  static const String removeTooltip = 'Etiketi kaldır';
  static const String suggestionsLabel = 'Öneriler';
  static const int maxSuggestions = 10;
  static const double chipMaxWidth = 220;

  @override
  State<TagInput> createState() => _TagInputState();
}

class _TagInputState extends State<TagInput> {
  final TextEditingController _controller = TextEditingController();
  String _lastText = '';
  String? _error;

  bool get _full => widget.tags.length >= maxTagsPerNote;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _apply(String text, {required bool submit}) {
    final r = applyTagInput(widget.tags, text, submit: submit);
    _controller.value = TextEditingValue(
      text: r.rest,
      selection: TextSelection.collapsed(offset: r.rest.length),
    );
    _lastText = r.rest;
    setState(() => _error = r.error);
    if (r.tags.length != widget.tags.length) widget.onChanged(r.tags);
  }

  void _onChanged(String text) {
    if (text.contains(',')) {
      // More than one character arriving at once with a comma is a paste:
      // every part is added, the last one too.
      final pasted = text.length - _lastText.length > 1;
      _apply(text, submit: pasted);
      return;
    }
    _lastText = text;
    setState(() => _error = null);
  }

  void _remove(String tag) {
    setState(() => _error = null);
    widget.onChanged([...widget.tags.where((t) => t != tag)]);
  }

  void _addSuggestion(String name) {
    final r = addTag(widget.tags, name);
    _controller.clear();
    _lastText = '';
    setState(() => _error = r.error);
    if (r.tags.length != widget.tags.length) widget.onChanged(r.tags);
  }

  List<String> _visibleSuggestions() {
    final query = normalizeTagText(_controller.text);
    return widget.suggestions
        .where((s) => !widget.tags.contains(s) && (query.isEmpty || s.contains(query)))
        .take(TagInput.maxSuggestions)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = widget.enabled && !_full ? _visibleSuggestions() : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in widget.tags)
                _TagChip(
                  key: ValueKey('note-tag-chip-$tag'),
                  tag: tag,
                  onRemove: widget.enabled ? () => _remove(tag) : null,
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          key: const ValueKey('note-tag-input'),
          controller: _controller,
          enabled: widget.enabled && !_full,
          onChanged: _onChanged,
          onSubmitted: (text) => _apply(text, submit: true),
          // Keeps the keyboard open after Enter so several tags can be typed.
          onEditingComplete: () {},
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: TagInput.label,
            hintText: TagInput.hint,
            helperText: _full ? tagLimitMessage : null,
            helperMaxLines: 2,
            errorText: _full ? null : _error,
            errorMaxLines: 2,
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            TagInput.suggestionsLabel,
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          Wrap(
            key: const ValueKey('note-tag-suggestions'),
            spacing: 6,
            children: [
              for (final name in suggestions)
                ActionChip(
                  key: ValueKey('note-tag-suggestion-$name'),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: TagInput.chipMaxWidth),
                    child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onPressed: () => _addSuggestion(name),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({super.key, required this.tag, required this.onRemove});

  final String tag;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: TagInput.chipMaxWidth),
            child: Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          IconButton(
            key: ValueKey('note-tag-remove-$tag'),
            icon: const Icon(Icons.close, size: 18),
            tooltip: TagInput.removeTooltip,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
