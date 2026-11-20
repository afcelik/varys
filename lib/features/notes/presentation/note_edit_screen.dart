import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:varys/core/errors/error_utils.dart';
import 'package:varys/core/errors/failure.dart';
import 'package:varys/core/router/app_router.dart';
import 'package:varys/features/notes/data/note_repository_impl.dart';
import 'package:varys/features/notes/domain/markdown_format.dart';
import 'package:varys/features/notes/domain/note.dart';
import 'package:varys/features/notes/domain/note_form.dart';
import 'package:varys/features/notes/presentation/notes_list_notifier.dart';
import 'package:varys/features/notes/presentation/widgets/markdown_toolbar.dart';
import 'package:varys/features/notes/presentation/widgets/note_markdown.dart';
import 'package:varys/features/notes/presentation/widgets/tag_input.dart';
import 'package:varys/shared/widgets/back_arrow.dart';

/// Tag names for the form's suggestions (`GET /tags`). A failure gives an
/// empty list: the form works without suggestions, silently. Lives while
/// the form is open.
final noteTagSuggestionsProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final repository = await ref.watch(noteRepositoryProvider.future);
  final result = await repository.getTags();
  return result.fold((_) => const <String>[], (tags) => [for (final t in tags) t.name]);
});

/// Create (`/notes/new`, [note] null) or edit (`/notes/edit`, [note] from
/// `extra`) form: title, Markdown body, tags, favorite.
///
/// The body has two tabs: "Yaz" (the text field with the [MarkdownToolbar]
/// above it) and "Önizle" ([NoteMarkdown] full, toolbar hidden). A format
/// button changes the text at the body's selection ([applyFormat]), keeps
/// the field focused (the keyboard stays open) and counts as a change; a
/// result over the length limit is refused with a snackbar and the text
/// stays as it was. Switching tabs keeps the text and the selection.
///
/// Kaydet sits in a fixed bottom bar (lifted above the keyboard; a floating
/// snackbar is laid out above it). It is disabled while the form is invalid,
/// while saving and, when editing, while nothing changed (no request). Edit
/// sends only the changed fields. On a server error the form stays open with
/// the typed values and a snackbar; on success the page closes.
class NoteEditScreen extends ConsumerStatefulWidget {
  const NoteEditScreen({super.key, this.note});

  final Note? note;

  static const String createTitle = 'Yeni not';
  static const String editTitle = 'Notu düzenle';
  static const String titleLabel = 'Başlık';
  static const String bodyLabel = 'Not';
  static const String favoriteLabel = 'Favori';
  static const String saveText = 'Kaydet';
  static const String writeTab = 'Yaz';
  static const String previewTab = 'Önizle';
  static const String previewEmpty = 'Önizlenecek bir şey yok';

  static String bodyCounter(String body) => '${body.runes.length} / $noteBodyMaxLength';

  @override
  ConsumerState<NoteEditScreen> createState() => _NoteEditScreenState();
}

class _NoteEditScreenState extends ConsumerState<NoteEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  final FocusNode _bodyFocus = FocusNode(debugLabel: 'note-body');
  late List<String> _tags;
  late bool _isFavorite;
  bool _titleTouched = false;
  bool _saving = false;
  bool _previewing = false;

  /// Body selection when "Önizle" was opened; put back on "Yaz".
  TextSelection? _selectionBeforePreview;

  Note? get _original => widget.note;

  @override
  void initState() {
    super.initState();
    final n = _original;
    _title = TextEditingController(text: n?.title ?? '');
    _body = TextEditingController(text: n?.body ?? '');
    _tags = List.of(n?.tags ?? const <String>[]);
    _isFavorite = n?.isFavorite ?? false;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  void _applyFormat(MarkdownFormat format) {
    final result = applyFormat(_body.text, _body.selection, format);
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(markdownFormatLimitMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      _body.value = TextEditingValue(text: result.text, selection: result.selection);
    });
    _bodyFocus.requestFocus();
  }

  void _setPreviewing(bool previewing) {
    if (previewing == _previewing) return;
    if (previewing) {
      _selectionBeforePreview = _body.selection;
      setState(() => _previewing = true);
      return;
    }
    setState(() => _previewing = false);
    final saved = _selectionBeforePreview;
    if (saved != null && saved.isValid && saved.end <= _body.text.length) {
      _body.selection = saved;
    }
    _bodyFocus.requestFocus();
  }

  bool get _valid => isNoteFormValid(title: _title.text, body: _body.text, tags: _tags);

  NoteChanges? get _changes {
    final n = _original;
    if (n == null) return null;
    return computeNoteChanges(
      n,
      title: _title.text,
      body: _body.text,
      tags: _tags,
      isFavorite: _isFavorite,
    );
  }

  bool get _canSave => !_saving && _valid && (_original == null || !_changes!.isEmpty);

  Future<void> _save() async {
    if (!_canSave) return;
    setState(() => _saving = true);
    final notifier = ref.read(notesListProvider.notifier);
    final original = _original;
    final Either<Failure, Object?> result = original == null
        ? await notifier.createNote(
            NoteDraft(
              title: _title.text,
              body: noteBodyValue(_body.text),
              tags: _tags,
              isFavorite: _isFavorite,
            ),
          )
        : await notifier.updateNote(original.id, _changes!);
    if (!mounted) return; // page closed while the request ran
    setState(() => _saving = false);
    result.fold(
      (failure) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userMessage(failure)), behavior: SnackBarBehavior.floating),
      ),
      (_) => context.canPop() ? context.pop() : context.go(AppRouter.notesPath),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = ref.watch(noteTagSuggestionsProvider).valueOrNull ?? const <String>[];
    final titleError = _titleTouched ? validateNoteTitle(_title.text) : null;
    final bodyError = validateNoteBody(_body.text);

    return Scaffold(
      appBar: AppBar(
        leading: context.backArrowLeading(),
        title: Text(
          _original == null ? NoteEditScreen.createTitle : NoteEditScreen.editTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          key: const ValueKey('note-form-scroll'),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('note-title-field'),
                controller: _title,
                enabled: !_saving,
                textInputAction: TextInputAction.next,
                maxLines: null,
                onChanged: (_) => setState(() => _titleTouched = true),
                decoration: InputDecoration(
                  labelText: NoteEditScreen.titleLabel,
                  errorText: titleError,
                  errorMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              _BodyTabs(previewing: _previewing, onChanged: _setPreviewing),
              const SizedBox(height: 8),
              if (_previewing)
                _BodyPreview(text: _body.text)
              else ...[
                MarkdownToolbar(enabled: !_saving, onFormat: _applyFormat),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('note-body-field'),
                  controller: _body,
                  focusNode: _bodyFocus,
                  enabled: !_saving,
                  keyboardType: TextInputType.multiline,
                  minLines: 5,
                  maxLines: 15,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: NoteEditScreen.bodyLabel,
                    alignLabelWithHint: true,
                    errorText: bodyError,
                    errorMaxLines: 2,
                    counter: Text(
                      NoteEditScreen.bodyCounter(_body.text),
                      key: const ValueKey('note-body-counter'),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TagInput(
                tags: _tags,
                suggestions: suggestions,
                enabled: !_saving,
                onChanged: (tags) => setState(() => _tags = tags),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const ValueKey('note-favorite-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text(NoteEditScreen.favoriteLabel),
                value: _isFavorite,
                onChanged: _saving ? null : (v) => setState(() => _isFavorite = v),
              ),
            ],
          ),
        ),
      ),
      // Kaydet stays outside the scroll view: always reachable, lifted above
      // the keyboard, and a floating snackbar is laid out above it instead
      // of covering it.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: FilledButton(
            key: const ValueKey('note-save'),
            onPressed: _canSave ? _save : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text(NoteEditScreen.saveText),
          ),
        ),
      ),
    );
  }
}

/// "Yaz" / "Önizle" switch above the body (each segment at least 48 high).
class _BodyTabs extends StatelessWidget {
  const _BodyTabs({required this.previewing, required this.onChanged});

  final bool previewing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      child: SegmentedButton<bool>(
        key: const ValueKey('note-body-tabs'),
        segments: const [
          ButtonSegment(
            value: false,
            icon: Icon(Icons.edit_outlined),
            label: Text(
              NoteEditScreen.writeTab,
              key: ValueKey('note-tab-write'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ButtonSegment(
            value: true,
            icon: Icon(Icons.visibility_outlined),
            label: Text(
              NoteEditScreen.previewTab,
              key: ValueKey('note-tab-preview'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        selected: {previewing},
        showSelectedIcon: false,
        onSelectionChanged: (s) => onChanged(s.single),
        style: const ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(48, 48)),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}

/// The body rendered as Markdown, or "Önizlenecek bir şey yok" when blank.
class _BodyPreview extends StatelessWidget {
  const _BodyPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('note-body-preview'),
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: text.trim().isEmpty
          ? Text(
              NoteEditScreen.previewEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : NoteMarkdown(data: text, mode: NoteMarkdownMode.full),
    );
  }
}

/// Shown when `/notes/edit` is opened without a [Note] as `extra` (deep
/// link, notification, wrong type). No silent fallback to create.
class NoteEditUnavailablePage extends StatelessWidget {
  const NoteEditUnavailablePage({super.key});

  static const String message = 'Bu sayfa doğrudan açılamaz.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: const BackArrow()),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
