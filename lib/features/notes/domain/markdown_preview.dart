import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:markdown/markdown.dart' as md;

/// Pure Markdown parsing for notes, shared by every rendering mode. No
/// widgets, no I/O.
///
/// [parseNoteMarkdown] parses GitHub Flavored Markdown and sanitizes the
/// tree: nothing in it can be tapped or loads anything.
/// * Links (`a`) are unwrapped to their text. For an http/https link whose
///   text differs from its address, the address follows in parentheses so it
///   can be read and copied; any other scheme (javascript:, file:, data:, …)
///   keeps only its text.
/// * Images (`img`) become the text `[Resim: alt]` (no image widget, no
///   network request).
/// * Raw HTML is already plain text in the tree (the parser never builds
///   elements from it); it is shown as typed and never interpreted.
///
/// [buildMarkdownPreview] flattens the first lines of a note into styled
/// runs for the card and list previews (one `Text.rich` with maxLines).

const String markdownImageLabel = 'Resim';

/// Text shown in place of an image.
String markdownImagePlaceholder(String? alt) {
  final a = alt?.trim() ?? '';
  return a.isEmpty ? '[$markdownImageLabel]' : '[$markdownImageLabel: $a]';
}

/// Only these link schemes show their address.
bool isSafeLinkScheme(String? href) {
  if (href == null) return false;
  final scheme = Uri.tryParse(href.trim())?.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

/// Parses [data] and returns the sanitized tree (see the library comment).
/// [linkAddresses] false leaves out the http/https address after a link's
/// text (the previews show only the text).
List<md.Node> parseNoteMarkdown(String data, {bool linkAddresses = true}) {
  final document = md.Document(extensionSet: md.ExtensionSet.gitHubFlavored, encodeHtml: false);
  final nodes = document.parseLines(const LineSplitter().convert(data));
  return [
    for (final n in nodes)
      // A raw HTML block is a bare top-level Text, which the renderer would
      // skip silently: make it a paragraph so it shows as typed.
      if (n is md.Text)
        if (n.text.trim().isNotEmpty) md.Element('p', [md.Text(n.text.trim())]) else ...[]
      else
        ..._sanitize(n, linkAddresses),
  ];
}

List<md.Node> _sanitize(md.Node node, bool linkAddresses) {
  if (node is! md.Element) return [node];
  switch (node.tag) {
    case 'img':
      return [md.Text(markdownImagePlaceholder(node.attributes['alt']))];
    case 'a':
      final children = [
        for (final c in node.children ?? const <md.Node>[]) ..._sanitize(c, linkAddresses),
      ];
      final href = node.attributes['href'];
      if (!isSafeLinkScheme(href)) return children;
      if (!linkAddresses) return children;
      final label = children.map((c) => c.textContent).join();
      return [...children, if (label.trim() != href!.trim()) md.Text(' ($href)')];
  }
  final kids = node.children;
  final copy = kids == null
      ? md.Element.empty(node.tag)
      : md.Element(node.tag, [for (final c in kids) ..._sanitize(c, linkAddresses)]);
  copy.attributes.addAll(node.attributes);
  return [copy];
}

// ---------------------------------------------------------------------------
// Flattened preview

/// One styled run of preview text. A heading run is [bold].
@immutable
class PreviewSpan {
  const PreviewSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;

  @override
  bool operator ==(Object other) =>
      other is PreviewSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.strike == strike &&
      other.code == code;

  @override
  int get hashCode => Object.hash(text, bold, italic, strike, code);

  @override
  String toString() =>
      'PreviewSpan(${jsonEncode(text)}${bold ? ', bold' : ''}${italic ? ', italic' : ''}'
      '${strike ? ', strike' : ''}${code ? ', code' : ''})';
}

/// Plain text of [spans] (what the preview shows, without styles).
String previewPlainText(List<PreviewSpan> spans) => spans.map((s) => s.text).join();

/// Input cut for the preview: at most this many lines and UTF-16 units of
/// the note are parsed (the card shows 3 lines, the list 2), so a 20000
/// character body stays cheap.
const int previewMaxSourceLines = 40;
const int previewMaxSourceChars = 4000;

/// Output cut: at most this many preview lines are built.
const int previewMaxLines = 10;

/// Rules: each block starts a new line and blank lines vanish (blocks are
/// joined with one `\n`). Headings are bold at body size; bullets get `• `,
/// numbered items `n. ` (from the list's start), tasks `☐ ` / `☑ `, nested
/// items two spaces per level; quotes get `│ `; code blocks keep their lines
/// in [PreviewSpan.code]; table rows join their cells with ` · ` (header
/// cells bold); a rule is `—`; soft line breaks inside a paragraph become a
/// space; links show only their text; images show [markdownImagePlaceholder];
/// raw HTML is plain text.
List<PreviewSpan> buildMarkdownPreview(String data) {
  final nodes = parseNoteMarkdown(_cutSource(data), linkAddresses: false);
  final f = _Flattener();
  for (final n in nodes) {
    if (f.full) break;
    f.block(n, '');
  }
  return f.result();
}

String _cutSource(String data) {
  var end = 0;
  var lines = 0;
  while (end < data.length && lines < previewMaxSourceLines) {
    final nl = data.indexOf('\n', end);
    end = nl == -1 ? data.length : nl + 1;
    lines++;
  }
  if (end > previewMaxSourceChars) {
    end = previewMaxSourceChars;
    // Never cut a surrogate pair in half.
    final unit = data.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end--;
  }
  return data.substring(0, end);
}

class _Style {
  const _Style({this.bold = false, this.italic = false, this.strike = false, this.code = false});

  final bool bold;
  final bool italic;
  final bool strike;
  final bool code;

  _Style copyWith({bool? bold, bool? italic, bool? strike, bool? code}) => _Style(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    strike: strike ?? this.strike,
    code: code ?? this.code,
  );
}

/// Blocks inside a list item that start their own lines.
const Set<String> _nestedBlocks = {'ul', 'ol', 'pre', 'blockquote', 'table'};

class _Flattener {
  final List<List<PreviewSpan>> _lines = [];
  List<PreviewSpan>? _current;

  bool get full => _lines.length >= previewMaxLines;

  void _startLine(String prefix) {
    _current = [];
    _lines.add(_current!);
    if (prefix.isNotEmpty) _current!.add(PreviewSpan(prefix));
  }

  void _add(String text, _Style s) {
    if (text.isEmpty) return;
    if (_current == null) _startLine('');
    _current!.add(
      PreviewSpan(text, bold: s.bold, italic: s.italic, strike: s.strike, code: s.code),
    );
  }

  /// A block-level node; every line it starts begins with [prefix].
  void block(md.Node node, String prefix) {
    if (full) return;
    if (node is md.Text) {
      // Raw HTML block (or stray text): its lines as plain text.
      for (final line in node.text.split('\n')) {
        if (line.trim().isEmpty) continue;
        _startLine(prefix);
        _add(line.trim(), const _Style());
      }
      return;
    }
    if (node is! md.Element) return;
    final kids = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _startLine(prefix);
        _inlineAll(kids, const _Style(bold: true));
      case 'p':
        _startLine(prefix);
        _inlineAll(kids, const _Style());
      case 'blockquote':
        for (final c in kids) {
          block(c, '$prefix│ ');
        }
      case 'ul' || 'ol':
        _list(node, prefix);
      case 'pre':
        final code = node.textContent.replaceAll(RegExp(r'\n$'), '');
        for (final line in code.split('\n')) {
          if (full) return;
          if (line.trim().isEmpty) continue;
          _startLine(prefix);
          _add(line, const _Style(code: true));
        }
      case 'hr':
        _startLine(prefix);
        _add('—', const _Style());
      case 'table':
        for (final section in kids) {
          for (final row in (section is md.Element ? section.children : null) ?? <md.Node>[]) {
            if (full) return;
            if (row is! md.Element) continue;
            _startLine(prefix);
            var first = true;
            for (final cell in row.children ?? const <md.Node>[]) {
              if (cell is! md.Element) continue;
              if (!first) _add(' · ', const _Style());
              first = false;
              _inlineAll(cell.children ?? const [], _Style(bold: cell.tag == 'th'));
            }
          }
        }
      default:
        // Unknown block: treat its children as inline text on one line.
        _startLine(prefix);
        _inlineAll(kids, const _Style());
    }
  }

  void _list(md.Element list, String prefix) {
    final ordered = list.tag == 'ol';
    var n = int.tryParse(list.attributes['start'] ?? '') ?? 1;
    for (final item in list.children ?? const <md.Node>[]) {
      if (full) return;
      if (item is! md.Element) continue;
      final kids = item.children ?? const <md.Node>[];
      String marker = ordered ? '${n++}. ' : '• ';
      final inline = <md.Node>[];
      final nested = <md.Node>[];
      for (final c in kids) {
        if (c is md.Element && c.tag == 'input') {
          marker = c.attributes['checked'] == 'true' ? '☑ ' : '☐ ';
        } else if (c is md.Element && _nestedBlocks.contains(c.tag)) {
          nested.add(c);
        } else if (c is md.Element && c.tag == 'p') {
          // Loose list: paragraphs are the item's text.
          if (inline.isNotEmpty) inline.add(md.Text(' '));
          inline.addAll(c.children ?? const []);
        } else {
          inline.add(c);
        }
      }
      _startLine('$prefix$marker');
      _inlineAll(inline, const _Style());
      for (final c in nested) {
        block(c, '$prefix  ');
      }
    }
  }

  void _inlineAll(List<md.Node> nodes, _Style s) {
    for (final n in nodes) {
      _inline(n, s);
    }
  }

  void _inline(md.Node node, _Style s) {
    if (node is md.Text) {
      _add(node.text.replaceAll('\n', ' '), s);
      return;
    }
    if (node is! md.Element) return;
    final kids = node.children ?? const <md.Node>[];
    switch (node.tag) {
      case 'strong':
        _inlineAll(kids, s.copyWith(bold: true));
      case 'em':
        _inlineAll(kids, s.copyWith(italic: true));
      case 'del':
        _inlineAll(kids, s.copyWith(strike: true));
      case 'code':
        _inlineAll(kids, s.copyWith(code: true));
      case 'br':
        _add(' ', s);
      default:
        _inlineAll(kids, s);
    }
  }

  List<PreviewSpan> result() {
    final out = <PreviewSpan>[];
    for (final line in _lines) {
      if (line.every((s) => s.text.trim().isEmpty)) continue;
      if (out.isNotEmpty) out.add(const PreviewSpan('\n'));
      out.addAll(_merge(line));
    }
    return out;
  }

  /// Joins neighbouring runs with the same style.
  static List<PreviewSpan> _merge(List<PreviewSpan> line) {
    final out = <PreviewSpan>[];
    for (final s in line) {
      final last = out.isEmpty ? null : out.last;
      if (last != null &&
          last.bold == s.bold &&
          last.italic == s.italic &&
          last.strike == s.strike &&
          last.code == s.code) {
        out[out.length - 1] = PreviewSpan(
          last.text + s.text,
          bold: s.bold,
          italic: s.italic,
          strike: s.strike,
          code: s.code,
        );
      } else {
        out.add(s);
      }
    }
    return out;
  }
}
