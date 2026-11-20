import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:varys/features/notes/domain/markdown_preview.dart';

enum NoteMarkdownMode {
  /// Whole note (edit page preview): every block, selectable text.
  full,

  /// Notes list row: at most [NoteMarkdown.listMaxLines] lines.
  list,

  /// Home card: at most [NoteMarkdown.cardMaxLines] lines.
  card,
}

/// A note body rendered as Markdown, configured in this one place.
///
/// Nothing in it can be tapped: links are text (an http/https address is
/// shown after its text so it can be copied in [NoteMarkdownMode.full]),
/// images are a `[Resim: alt]` text and load nothing, raw HTML is plain text
/// (see [parseNoteMarkdown]).
///
/// [NoteMarkdownMode.full] renders every block with flutter_markdown_plus
/// (tables and code blocks scroll sideways; one SelectionArea makes the text
/// selectable with a long press).
/// [NoteMarkdownMode.list] and [NoteMarkdownMode.card] render one
/// non-selectable `Text.rich` from [buildMarkdownPreview] with a real line
/// limit and an ellipsis; headings stay at body size, in bold. A tap on them
/// reaches the surrounding InkWell.
class NoteMarkdown extends StatelessWidget {
  const NoteMarkdown({super.key, required this.data, required this.mode});

  final String data;
  final NoteMarkdownMode mode;

  static const int listMaxLines = 2;
  static const int cardMaxLines = 3;

  static const List<String> monospaceFallback = ['Menlo', 'Consolas', 'Courier New', 'Courier'];

  @override
  Widget build(BuildContext context) => switch (mode) {
    NoteMarkdownMode.full => _FullMarkdown(data: data),
    NoteMarkdownMode.list => _PreviewText(data: data, maxLines: listMaxLines),
    NoteMarkdownMode.card => _PreviewText(data: data, maxLines: cardMaxLines),
  };
}

TextStyle _monospace(TextStyle? base) => (base ?? const TextStyle()).copyWith(
  fontFamily: 'monospace',
  fontFamilyFallback: NoteMarkdown.monospaceFallback,
);

class _PreviewText extends StatelessWidget {
  const _PreviewText({required this.data, required this.maxLines});

  final String data;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final spans = buildMarkdownPreview(data);
    return Text.rich(
      TextSpan(
        children: [
          for (final s in spans)
            TextSpan(
              text: s.text,
              style: TextStyle(
                fontWeight: s.bold ? FontWeight.w600 : null,
                fontStyle: s.italic ? FontStyle.italic : null,
                decoration: s.strike ? TextDecoration.lineThrough : null,
                fontFamily: s.code ? 'monospace' : null,
                fontFamilyFallback: s.code ? NoteMarkdown.monospaceFallback : null,
              ),
            ),
        ],
      ),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: base,
    );
  }
}

class _FullMarkdown extends StatefulWidget {
  const _FullMarkdown({required this.data});

  final String data;

  @override
  State<_FullMarkdown> createState() => _FullMarkdownState();
}

class _FullMarkdownState extends State<_FullMarkdown> implements MarkdownBuilderDelegate {
  List<md.Node> _nodes = const [];

  /// Only reached if an `a` element survives sanitizing (it never should).
  final List<GestureRecognizer> _recognizers = [];

  @override
  void initState() {
    super.initState();
    _nodes = parseNoteMarkdown(widget.data);
  }

  @override
  void didUpdateWidget(_FullMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != oldWidget.data) _nodes = parseNoteMarkdown(widget.data);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  GestureRecognizer createLink(String text, String? href, String title) {
    final r = TapGestureRecognizer()..onTap = () {};
    _recognizers.add(r);
    return r;
  }

  @override
  TextSpan formatText(MarkdownStyleSheet styleSheet, String code) =>
      TextSpan(style: styleSheet.code, text: code.replaceAll(RegExp(r'\n$'), ''));

  MarkdownStyleSheet _styleSheet(ThemeData theme) {
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final body = text.bodyMedium;
    return MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: body,
      h1: text.titleLarge,
      h2: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      h3: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      h4: body?.copyWith(fontWeight: FontWeight.w600),
      h5: body?.copyWith(fontWeight: FontWeight.w600),
      h6: body?.copyWith(fontWeight: FontWeight.w600),
      a: body,
      code: _monospace(body).copyWith(backgroundColor: scheme.surfaceContainerLowest),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
      ),
      blockquote: body?.copyWith(color: scheme.onSurfaceVariant),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableBorder: TableBorder.all(color: scheme.outline),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_nodes.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    _disposeRecognizers();
    final children = MarkdownBuilder(
      delegate: this,
      // Plain text under one SelectionArea (below) instead of SelectableText
      // per block: a drag on a table or code block scrolls it sideways, and
      // a long press still selects and copies.
      selectable: false,
      styleSheet: _styleSheet(theme),
      imageDirectory: null,
      // No image element survives sanitizing; never load anything anyway.
      imageBuilder: (_, _, alt) => Text(markdownImagePlaceholder(alt)),
      checkboxBuilder: (checked) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 4),
        child: Icon(
          checked ? Icons.check_box : Icons.check_box_outline_blank,
          size: (theme.textTheme.bodyMedium?.fontSize ?? 14) + 4,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      bulletBuilder: null,
      builders: const {},
      paddingBuilders: const {},
      listItemCrossAxisAlignment: MarkdownListItemCrossAxisAlignment.baseline,
      fitContent: true,
    ).build(_nodes);
    return SelectionArea(
      child: Column(
        key: const ValueKey('note-markdown-full'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
