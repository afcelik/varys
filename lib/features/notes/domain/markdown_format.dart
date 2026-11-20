import 'package:flutter/widgets.dart' show StringCharacters, TextSelection;
import 'package:varys/features/notes/domain/note_form.dart';

/// Pure Markdown formatting for the note body's toolbar. No widgets, no I/O.
///
/// Positions are UTF-16 indexes (as in [TextSelection]). A selection end that
/// falls inside a grapheme (surrogate pair, ZWJ emoji, flag, base letter +
/// combining mark) is first moved to a grapheme boundary, so marks are never
/// inserted inside a character.

enum MarkdownFormat {
  h1,
  h2,
  h3,
  bold,
  italic,
  strike,
  inlineCode,
  codeBlock,
  bulletList,
  numberedList,
  taskList,
  quote,
  rule,
  link,
  table,
}

/// Shown by the caller when [applyFormat] returns null.
const String markdownFormatLimitMessage = 'Not en fazla 20000 karakter olabilir; biçim uygulanmadı';

/// Placeholder link text when the selection is empty.
const String markdownLinkPlaceholder = 'bağlantı';
const String markdownLinkUrl = 'https://';
const String markdownTableHeader = 'Başlık';

typedef MarkdownFormatResult = ({String text, TextSelection selection});

/// Applies [format] to [text] at [selection].
///
/// Line formats (h1–h3, lists, task list, quote) act on every selected line
/// and are removed when every non-blank selected line already has them; a
/// different heading level or list type is replaced. Inline formats (bold,
/// italic, strike, inline code) wrap the selection, put the cursor between
/// the marks when it is empty, and remove the marks when already wrapped.
/// [MarkdownFormat.codeBlock] puts the selected lines between ``` lines
/// (removes them when already fenced); [MarkdownFormat.rule] and
/// [MarkdownFormat.table] insert below the cursor's line with blank lines
/// around; [MarkdownFormat.link] makes `[text](https://)` and selects the URL.
///
/// Returns null when the result would be longer than [noteBodyMaxLength]
/// code points and longer than [text] (removing marks is always allowed);
/// the text is then unchanged and the caller shows
/// [markdownFormatLimitMessage].
MarkdownFormatResult? applyFormat(String text, TextSelection selection, MarkdownFormat format) {
  final (start, end) = _normalize(text, selection);
  final result = switch (format) {
    MarkdownFormat.h1 => _heading(text, start, end, 1),
    MarkdownFormat.h2 => _heading(text, start, end, 2),
    MarkdownFormat.h3 => _heading(text, start, end, 3),
    MarkdownFormat.bulletList => _list(text, start, end, _ListKind.bullet),
    MarkdownFormat.numberedList => _list(text, start, end, _ListKind.numbered),
    MarkdownFormat.taskList => _list(text, start, end, _ListKind.task),
    MarkdownFormat.quote => _quote(text, start, end),
    MarkdownFormat.bold => _inline(text, start, end, '**'),
    MarkdownFormat.italic => _inline(text, start, end, '*'),
    MarkdownFormat.strike => _inline(text, start, end, '~~'),
    MarkdownFormat.inlineCode => _inline(text, start, end, '`'),
    MarkdownFormat.codeBlock => _codeBlock(text, start, end),
    MarkdownFormat.rule => _insertBelow(text, end, '---', null),
    MarkdownFormat.table => _insertBelow(
      text,
      end,
      '| $markdownTableHeader | $markdownTableHeader |\n| --- | --- |\n|  |  |',
      (2, 2 + markdownTableHeader.length),
    ),
    MarkdownFormat.link => _link(text, start, end),
  };
  final newLength = result.text.runes.length;
  if (newLength > noteBodyMaxLength && newLength > text.runes.length) return null;
  return result;
}

// ---------------------------------------------------------------------------
// Selection normalization

/// Ordered (start, end), clamped to the text, ends moved to grapheme
/// boundaries: a range grows to whole graphemes, a cursor moves to the
/// nearest boundary (the earlier one on a tie). An invalid selection is a
/// cursor at the end.
(int, int) _normalize(String text, TextSelection selection) {
  if (!selection.isValid) return (text.length, text.length);
  var start = selection.start.clamp(0, text.length);
  var end = selection.end.clamp(0, text.length);
  final bounds = _graphemeBoundaries(text);
  if (start == end) {
    final p = _nearest(bounds, start);
    return (p, p);
  }
  start = _floor(bounds, start);
  end = _ceil(bounds, end);
  return (start, end);
}

List<int> _graphemeBoundaries(String text) {
  final out = <int>[0];
  var i = 0;
  for (final g in text.characters) {
    i += g.length;
    out.add(i);
  }
  return out;
}

int _floor(List<int> bounds, int p) {
  var best = 0;
  for (final b in bounds) {
    if (b > p) break;
    best = b;
  }
  return best;
}

int _ceil(List<int> bounds, int p) {
  for (final b in bounds) {
    if (b >= p) return b;
  }
  return bounds.last;
}

int _nearest(List<int> bounds, int p) {
  final lo = _floor(bounds, p);
  final hi = _ceil(bounds, p);
  return (p - lo) <= (hi - p) ? lo : hi;
}

// ---------------------------------------------------------------------------
// Line formats

/// Start of the first and end of the last selected line. A range that ends
/// right after a newline does not take in the next line.
(int, int) _lineSpan(String text, int start, int end) {
  final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
  final effectiveEnd = (end > start && text[end - 1] == '\n') ? end - 1 : end;
  final nl = text.indexOf('\n', effectiveEnd);
  return (lineStart, nl == -1 ? text.length : nl);
}

final RegExp _headingPrefix = RegExp(r'^(#{1,6}) ');
final RegExp _taskPrefix = RegExp(r'^- \[[ xX]\] ');
final RegExp _bulletPrefix = RegExp(r'^[-*+] ');
final RegExp _numberedPrefix = RegExp(r'^\d+\. ');
const String _quotePrefix = '> ';

/// Rewrites the prefix of every selected line. [rewrite] gets the line and
/// its index among the edited lines and returns (old prefix length, new
/// prefix); null leaves the line alone. Positions inside an old prefix map
/// to the end of the new prefix; later positions shift by the difference.
MarkdownFormatResult _rewriteLines(
  String text,
  int start,
  int end,
  (int, String)? Function(String line, int index) rewrite,
) {
  final (lineStart, lineEnd) = _lineSpan(text, start, end);
  final lines = text.substring(lineStart, lineEnd).split('\n');
  final out = StringBuffer();
  var oldPos = lineStart;
  var newPos = lineStart;
  int mapStart = start;
  int mapEnd = end;
  var edited = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final r = rewrite(line, edited);
    final oldPrefix = r?.$1 ?? 0;
    final newPrefix = r?.$2 ?? '';
    if (r != null) edited++;
    final newLine = r == null ? line : newPrefix + line.substring(oldPrefix);
    int map(int p) {
      final c = p - oldPos;
      if (r == null) return newPos + c;
      return c <= oldPrefix ? newPos + newPrefix.length : newPos + c - oldPrefix + newPrefix.length;
    }

    final lineEndOld = oldPos + line.length;
    if (start >= oldPos && start <= lineEndOld) mapStart = map(start);
    if (end >= oldPos && end <= lineEndOld) mapEnd = map(end);
    out.write(newLine);
    if (i < lines.length - 1) out.write('\n');
    oldPos = lineEndOld + 1;
    newPos += newLine.length + 1;
  }
  final rewritten = out.toString();
  final newText = text.substring(0, lineStart) + rewritten + text.substring(lineEnd);
  // A range ending right after the last line's newline lies past the span.
  if (end > lineEnd) mapEnd = end + rewritten.length - (lineEnd - lineStart);
  if (mapEnd < mapStart) mapEnd = mapStart;
  return (
    text: newText,
    selection: start == end
        ? TextSelection.collapsed(offset: mapStart)
        : TextSelection(baseOffset: mapStart, extentOffset: mapEnd),
  );
}

/// Lines to edit: every non-blank line, or every line when all are blank.
bool Function(String) _editable(String text, int start, int end) {
  final (lineStart, lineEnd) = _lineSpan(text, start, end);
  final allBlank = text.substring(lineStart, lineEnd).split('\n').every((l) => l.trim().isEmpty);
  return (line) => allBlank || line.trim().isNotEmpty;
}

Iterable<String> _editedLines(String text, int start, int end) {
  final (lineStart, lineEnd) = _lineSpan(text, start, end);
  final take = _editable(text, start, end);
  return text.substring(lineStart, lineEnd).split('\n').where(take);
}

MarkdownFormatResult _heading(String text, int start, int end, int level) {
  final marks = '#' * level;
  final all = _editedLines(
    text,
    start,
    end,
  ).every((l) => _headingPrefix.firstMatch(l)?.group(1) == marks);
  final take = _editable(text, start, end);
  return _rewriteLines(text, start, end, (line, _) {
    if (!take(line)) return null;
    final old = _headingPrefix.firstMatch(line)?.end ?? 0;
    return (old, all ? '' : '$marks ');
  });
}

enum _ListKind { bullet, numbered, task }

_ListKind? _listKindOf(String line) {
  if (_taskPrefix.hasMatch(line)) return _ListKind.task;
  if (_bulletPrefix.hasMatch(line)) return _ListKind.bullet;
  if (_numberedPrefix.hasMatch(line)) return _ListKind.numbered;
  return null;
}

int _listPrefixLength(String line) =>
    (_taskPrefix.firstMatch(line) ??
            _bulletPrefix.firstMatch(line) ??
            _numberedPrefix.firstMatch(line))
        ?.end ??
    0;

MarkdownFormatResult _list(String text, int start, int end, _ListKind kind) {
  final all = _editedLines(text, start, end).every((l) => _listKindOf(l) == kind);
  final take = _editable(text, start, end);
  return _rewriteLines(text, start, end, (line, index) {
    if (!take(line)) return null;
    final old = _listPrefixLength(line);
    if (all) return (old, '');
    return (
      old,
      switch (kind) {
        _ListKind.bullet => '- ',
        _ListKind.numbered => '${index + 1}. ',
        _ListKind.task => '- [ ] ',
      },
    );
  });
}

MarkdownFormatResult _quote(String text, int start, int end) {
  final all = _editedLines(text, start, end).every((l) => l.startsWith(_quotePrefix));
  final take = _editable(text, start, end);
  return _rewriteLines(text, start, end, (line, _) {
    if (!take(line)) return null;
    if (all) return (_quotePrefix.length, '');
    return line.startsWith(_quotePrefix) ? (0, '') : (0, _quotePrefix);
  });
}

// ---------------------------------------------------------------------------
// Inline formats

/// Length of the run of [ch] ending at [p] (going left).
int _runBefore(String text, int p, String ch) {
  var n = 0;
  while (p - n - 1 >= 0 && text[p - n - 1] == ch) {
    n++;
  }
  return n;
}

/// Length of the run of [ch] starting at [p].
int _runAfter(String text, int p, String ch) {
  var n = 0;
  while (p + n < text.length && text[p + n] == ch) {
    n++;
  }
  return n;
}

/// Whether a run of [n] marks of a star-type mark of length [m] contains it:
/// bold (`**`) needs at least two; italic (`*`) an odd count (`*` or `***`).
bool _hasStar(int n, int m) => m == 2 ? n >= 2 : n.isOdd;

MarkdownFormatResult _inline(String text, int start, int end, String mark) {
  final m = mark.length;
  final selected = text.substring(start, end);

  // 1. Marks inside the selection: "**x**" selected → "x".
  if (selected.length >= 2 * m) {
    final bool inside;
    if (mark == '*' || mark == '**') {
      inside =
          _hasStar(_runAfter(selected, 0, '*'), m) &&
          _hasStar(_runBefore(selected, selected.length, '*'), m) &&
          selected.length > 2 * m;
    } else {
      inside = selected.startsWith(mark) && selected.endsWith(mark) && selected.length > 2 * m;
    }
    if (inside) {
      final inner = selected.substring(m, selected.length - m);
      return (
        text: text.substring(0, start) + inner + text.substring(end),
        selection: TextSelection(baseOffset: start, extentOffset: start + inner.length),
      );
    }
  }

  // 2. Marks around the selection: "**[x]**" → "x".
  final bool around;
  if (mark == '*' || mark == '**') {
    around = _hasStar(_runBefore(text, start, '*'), m) && _hasStar(_runAfter(text, end, '*'), m);
  } else {
    around =
        start >= m &&
        end + m <= text.length &&
        text.substring(start - m, start) == mark &&
        text.substring(end, end + m) == mark;
  }
  if (around) {
    final newText = text.substring(0, start - m) + selected + text.substring(end + m);
    return (
      text: newText,
      selection: start == end
          ? TextSelection.collapsed(offset: start - m)
          : TextSelection(baseOffset: start - m, extentOffset: end - m),
    );
  }

  // 3. Wrap.
  final newText = text.substring(0, start) + mark + selected + mark + text.substring(end);
  return (
    text: newText,
    selection: start == end
        ? TextSelection.collapsed(offset: start + m)
        : TextSelection(baseOffset: start + m, extentOffset: end + m),
  );
}

// ---------------------------------------------------------------------------
// Blocks and inserts

const String _fence = '```';

MarkdownFormatResult _codeBlock(String text, int start, int end) {
  final (lineStart, lineEnd) = _lineSpan(text, start, end);

  // Already fenced: the line before is ``` and the line after is ```.
  if (lineStart >= _fence.length + 1 && lineEnd + 1 + _fence.length <= text.length) {
    final beforeStart = text.lastIndexOf('\n', lineStart - 2) + 1;
    final before = text.substring(beforeStart, lineStart - 1);
    final afterEndIdx = text.indexOf('\n', lineEnd + 1);
    final afterEnd = afterEndIdx == -1 ? text.length : afterEndIdx;
    final after = text.substring(lineEnd + 1, afterEnd);
    if (before.startsWith(_fence) && after == _fence) {
      final cut = lineStart - beforeStart; // fence line + its newline
      final newText =
          text.substring(0, beforeStart) +
          text.substring(lineStart, lineEnd) +
          text.substring(afterEnd);
      return (
        text: newText,
        selection: start == end
            ? TextSelection.collapsed(offset: start - cut)
            : TextSelection(baseOffset: start - cut, extentOffset: end - cut),
      );
    }
  }

  const open = '$_fence\n';
  const close = '\n$_fence';
  final newText =
      text.substring(0, lineStart) +
      open +
      text.substring(lineStart, lineEnd) +
      close +
      text.substring(lineEnd);
  return (
    text: newText,
    selection: start == end
        ? TextSelection.collapsed(offset: start + open.length)
        : TextSelection(baseOffset: start + open.length, extentOffset: end + open.length),
  );
}

/// Inserts [block] on its own lines below the line holding [at], with a
/// blank line before (none at the very start of the text) and after.
/// [select] is a range inside [block] to select; null puts the cursor after
/// the inserted text.
MarkdownFormatResult _insertBelow(String text, int at, String block, (int, int)? select) {
  final (_, lineEnd) = _lineSpan(text, at, at);
  final head = text.substring(0, lineEnd);
  final tail = text.substring(lineEnd);
  final String lead;
  if (head.isEmpty) {
    lead = '';
  } else if (head.endsWith('\n')) {
    lead = '\n'; // cursor on an empty line: one more newline makes it blank
  } else {
    lead = '\n\n';
  }
  final trail = tail.startsWith('\n') ? '\n' : '\n\n';
  final inserted = lead + block + trail;
  final blockStart = lineEnd + lead.length;
  return (
    text: head + inserted + tail,
    selection: select == null
        ? TextSelection.collapsed(offset: lineEnd + inserted.length)
        : TextSelection(baseOffset: blockStart + select.$1, extentOffset: blockStart + select.$2),
  );
}

MarkdownFormatResult _link(String text, int start, int end) {
  final label = start == end ? markdownLinkPlaceholder : text.substring(start, end);
  final inserted = '[$label]($markdownLinkUrl)';
  final urlStart = start + label.length + 3; // "[" + label + "]("
  return (
    text: text.substring(0, start) + inserted + text.substring(end),
    selection: TextSelection(baseOffset: urlStart, extentOffset: urlStart + markdownLinkUrl.length),
  );
}
