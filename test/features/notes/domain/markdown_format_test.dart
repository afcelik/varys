import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/features/notes/domain/markdown_format.dart';
import 'package:varys/features/notes/domain/note_form.dart';

// Notation: «…» is a selection (start, end), ‸ a cursor. The markers never
// occur in the texts under test.

(String, TextSelection) _parse(String marked) {
  final cursor = marked.indexOf('‸');
  if (cursor != -1) {
    return (marked.replaceFirst('‸', ''), TextSelection.collapsed(offset: cursor));
  }
  final start = marked.indexOf('«');
  final end = marked.indexOf('»') - 1;
  expect(start, isNot(-1), reason: 'no selection in "$marked"');
  return (
    marked.replaceFirst('«', '').replaceFirst('»', ''),
    TextSelection(baseOffset: start, extentOffset: end),
  );
}

String _show(String text, TextSelection s) {
  if (s.isCollapsed) return '${text.substring(0, s.start)}‸${text.substring(s.start)}';
  return '${text.substring(0, s.start)}«${text.substring(s.start, s.end)}»${text.substring(s.end)}';
}

String _apply(String marked, MarkdownFormat f) {
  final (text, sel) = _parse(marked);
  final r = applyFormat(text, sel, f);
  expect(r, isNotNull, reason: 'format refused for "$marked"');
  return _show(r!.text, r.selection);
}

/// Applies [f] twice: the second application must give the input back.
void _expectToggle(String marked, MarkdownFormat f, String applied) {
  expect(_apply(marked, f), applied, reason: 'apply $f');
  expect(_apply(applied, f), marked, reason: 'remove $f');
}

// Escapes kept as escapes so no invisible character sits in the source.
const _combiningDot = '\u0307';
const _decomposedI = 'I$_combiningDot'; // İ as I + U+0307
const _zwj = '\u200D';
const _family = '\u{1F468}$_zwj\u{1F469}$_zwj\u{1F467}'; // man ZWJ woman ZWJ girl
const _flagTr = '\u{1F1F9}\u{1F1F7}'; // regional indicators T R
const _smile = '\u{1F600}';

void main() {
  test('the escaped test characters are what they claim (no lost escapes)', () {
    expect(_decomposedI.codeUnits, [0x49, 0x0307]);
    expect(_family.runes.toList(), [0x1F468, 0x200D, 0x1F469, 0x200D, 0x1F467]);
    expect(_family.length, 8);
    expect(_flagTr.runes.toList(), [0x1F1F9, 0x1F1F7]);
    expect(_smile.length, 2);
  });

  group('headings', () {
    test('h1 at a cursor adds "# " and keeps the cursor in the word', () {
      _expectToggle('Mer‸haba', MarkdownFormat.h1, '# Mer‸haba');
    });

    test('h2 on a selection inside one line of several', () {
      _expectToggle('a\n«bc»\nd', MarkdownFormat.h2, 'a\n## «bc»\nd');
    });

    test('h3 on an empty text puts the cursor after the mark', () {
      _expectToggle('‸', MarkdownFormat.h3, '### ‸');
    });

    test('h1 → h2 replaces the previous heading mark', () {
      expect(_apply('# Başlık‸', MarkdownFormat.h2), '## Başlık‸');
      expect(_apply('### Başlık‸', MarkdownFormat.h1), '# Başlık‸');
    });

    test('an already applied heading is removed', () {
      expect(_apply('## Başlık‸', MarkdownFormat.h2), 'Başlık‸');
    });

    test('a multi-line selection gets the mark on every line', () {
      _expectToggle('«a\nb\nc»', MarkdownFormat.h3, '### «a\n### b\n### c»');
    });

    test('a mixed multi-line selection is completed, not removed', () {
      expect(_apply('«# a\nb»', MarkdownFormat.h1), '# «a\n# b»');
    });

    test('at the start and the end of the text', () {
      expect(_apply('‸ilk\nson', MarkdownFormat.h1), '# ‸ilk\nson');
      expect(_apply('ilk\nson‸', MarkdownFormat.h1), 'ilk\n# son‸');
    });

    test('a range ending right after a newline does not take the next line', () {
      _expectToggle('«a\n»b', MarkdownFormat.h1, '# «a\n»b');
    });
  });

  group('lists', () {
    test('bullet at a cursor, then removed', () {
      _expectToggle('el‸ma', MarkdownFormat.bulletList, '- el‸ma');
    });

    test('numbered list numbers every selected line', () {
      _expectToggle('«a\nb\nc»', MarkdownFormat.numberedList, '1. «a\n2. b\n3. c»');
    });

    test('task list at a cursor, then removed', () {
      _expectToggle('süt‸', MarkdownFormat.taskList, '- [ ] süt‸');
    });

    test('a checked task is a task too: task list removes it', () {
      expect(_apply('- [x] süt‸', MarkdownFormat.taskList), 'süt‸');
    });

    test('one list type replaces another', () {
      expect(_apply('- «a\n- b»', MarkdownFormat.numberedList), '1. «a\n2. b»');
      expect(_apply('1. «a\n2. b»', MarkdownFormat.taskList), '- [ ] «a\n- [ ] b»');
      expect(_apply('- [ ] «a»', MarkdownFormat.bulletList), '- «a»');
    });

    test('blank lines inside a selection are skipped and not numbered', () {
      _expectToggle('«a\n\nb»', MarkdownFormat.numberedList, '1. «a\n\n2. b»');
    });

    test('a list on an empty text', () {
      _expectToggle('‸', MarkdownFormat.bulletList, '- ‸');
    });
  });

  group('quote', () {
    test('at a cursor, then removed', () {
      _expectToggle('söz‸', MarkdownFormat.quote, '> söz‸');
    });

    test('multi-line, and a mixed selection is completed', () {
      _expectToggle('«a\nb»', MarkdownFormat.quote, '> «a\n> b»');
      expect(_apply('«> a\nb»', MarkdownFormat.quote), '«> a\n> b»');
    });
  });

  group('inline formats', () {
    test('bold wraps a selection and unwraps it again', () {
      _expectToggle('a «kalın» b', MarkdownFormat.bold, 'a **«kalın»** b');
    });

    test('bold at a cursor puts it between the marks; again removes them', () {
      _expectToggle('a‸', MarkdownFormat.bold, 'a**‸**');
    });

    test('bold with the marks inside the selection removes them', () {
      expect(_apply('a «**kalın**» b', MarkdownFormat.bold), 'a «kalın» b');
    });

    test('italic wraps and unwraps', () {
      _expectToggle('«eğik»', MarkdownFormat.italic, '*«eğik»*');
      _expectToggle('‸', MarkdownFormat.italic, '*‸*');
    });

    test('italic and bold stack without eating each other', () {
      expect(_apply('**«x»**', MarkdownFormat.italic), '***«x»***');
      expect(_apply('***«x»***', MarkdownFormat.italic), '**«x»**');
      expect(_apply('***«x»***', MarkdownFormat.bold), '*«x»*');
      // Italic marks are not taken for bold.
      expect(_apply('*«x»*', MarkdownFormat.bold), '***«x»***');
    });

    test('strike wraps and unwraps', () {
      _expectToggle('«çizik»', MarkdownFormat.strike, '~~«çizik»~~');
      expect(_apply('«~~çizik~~»', MarkdownFormat.strike), '«çizik»');
    });

    test('inline code wraps and unwraps', () {
      _expectToggle('x «kod» y', MarkdownFormat.inlineCode, 'x `«kod»` y');
      _expectToggle('‸', MarkdownFormat.inlineCode, '`‸`');
    });

    test('at the start and the end of the text', () {
      expect(_apply('«ab»c', MarkdownFormat.bold), '**«ab»**c');
      expect(_apply('a«bc»', MarkdownFormat.bold), 'a**«bc»**');
    });
  });

  group('code block', () {
    test('cursor on an empty text opens an empty block with the cursor inside', () {
      _expectToggle('‸', MarkdownFormat.codeBlock, '```\n‸\n```');
    });

    test('selected lines go between fence lines; again removes the fences', () {
      _expectToggle('a\n«b\nc»\nd', MarkdownFormat.codeBlock, 'a\n```\n«b\nc»\n```\nd');
    });

    test('a cursor fences its whole line', () {
      _expectToggle('ön\nkod‸', MarkdownFormat.codeBlock, 'ön\n```\nkod‸\n```');
    });

    test('a fence with a language is removed too', () {
      expect(_apply('```dart\nx‸\n```', MarkdownFormat.codeBlock), 'x‸');
    });
  });

  group('rule, link, table', () {
    test('rule goes below the line with blank lines around', () {
      expect(_apply('metin‸', MarkdownFormat.rule), 'metin\n\n---\n\n‸');
      expect(_apply('a‸\nb', MarkdownFormat.rule), 'a\n\n---\n‸\nb');
      expect(_apply('a\n‸', MarkdownFormat.rule), 'a\n\n---\n\n‸');
    });

    test('rule on an empty text has no leading blank lines', () {
      expect(_apply('‸', MarkdownFormat.rule), '---\n\n‸');
    });

    test('rule below a selection goes under its last line', () {
      expect(_apply('«a\nb»\nc', MarkdownFormat.rule), 'a\nb\n\n---\n‸\nc');
    });

    test('link wraps the selection and selects the URL', () {
      expect(_apply('git «site» bak', MarkdownFormat.link), 'git [site](«https://») bak');
    });

    test('link at a cursor uses the placeholder text', () {
      expect(_apply('a‸', MarkdownFormat.link), 'a[bağlantı](«https://»)');
      expect(_apply('‸', MarkdownFormat.link), '[bağlantı](«https://»)');
    });

    test('table inserts a 2x2 template below and selects the first header', () {
      expect(
        _apply('x‸', MarkdownFormat.table),
        'x\n\n| «Başlık» | Başlık |\n| --- | --- |\n|  |  |\n\n',
      );
      expect(
        _apply('‸', MarkdownFormat.table),
        '| «Başlık» | Başlık |\n| --- | --- |\n|  |  |\n\n',
      );
    });
  });

  group('selection handling', () {
    test('a reversed selection (base > extent) is treated as the same range', () {
      final r = applyFormat(
        'kalın',
        const TextSelection(baseOffset: 5, extentOffset: 0),
        MarkdownFormat.bold,
      )!;
      expect(_show(r.text, r.selection), '**«kalın»**');
    });

    test('a reversed multi-line selection formats every line', () {
      final r = applyFormat(
        'a\nb',
        const TextSelection(baseOffset: 3, extentOffset: 0),
        MarkdownFormat.bulletList,
      )!;
      expect(r.text, '- a\n- b');
    });

    test('an invalid selection acts as a cursor at the end', () {
      final r = applyFormat('ab', const TextSelection.collapsed(offset: -1), MarkdownFormat.bold)!;
      expect(_show(r.text, r.selection), 'ab**‸**');
    });

    test('a selection past the end is clamped', () {
      final r = applyFormat(
        'ab',
        const TextSelection(baseOffset: 1, extentOffset: 99),
        MarkdownFormat.bold,
      )!;
      expect(_show(r.text, r.selection), 'a**«b»**');
    });
  });

  group('unicode', () {
    test('emoji text keeps its emoji intact', () {
      expect(_apply('a$_smile«b»', MarkdownFormat.bold), 'a$_smile**«b»**');
      expect(_apply('$_smile not‸', MarkdownFormat.h1), '# $_smile not‸');
    });

    test('a cursor between the halves of a surrogate pair moves to a boundary', () {
      // 'a<smile>b': boundaries 0, 1, 3, 4; offset 2 is inside the emoji.
      final r = applyFormat(
        'a${_smile}b',
        const TextSelection.collapsed(offset: 2),
        MarkdownFormat.bold,
      )!;
      expect(_show(r.text, r.selection), 'a**‸**${_smile}b');
      expect(r.text.contains(_smile), isTrue);
    });

    test('a range ending inside a surrogate pair grows to the whole emoji', () {
      final r = applyFormat(
        'a${_smile}b',
        const TextSelection(baseOffset: 0, extentOffset: 2),
        MarkdownFormat.bold,
      )!;
      expect(_show(r.text, r.selection), '**«a$_smile»**b');
    });

    test('a ZWJ family emoji is never split by marks or the selection', () {
      final text = 'x${_family}y'; // family spans offsets 1..9
      final inside = applyFormat(
        text,
        const TextSelection(baseOffset: 3, extentOffset: 6),
        MarkdownFormat.bold,
      )!;
      expect(_show(inside.text, inside.selection), 'x**«$_family»**y');

      final cursor = applyFormat(
        text,
        const TextSelection.collapsed(offset: 4),
        MarkdownFormat.italic,
      )!;
      expect(_show(cursor.text, cursor.selection), 'x*‸*${_family}y');
      expect(cursor.text.contains(_family), isTrue);
    });

    test('a flag (two regional indicators) is never split', () {
      final text = 'a${_flagTr}b'; // flag spans offsets 1..5
      final r = applyFormat(
        text,
        const TextSelection(baseOffset: 2, extentOffset: 3),
        MarkdownFormat.strike,
      )!;
      expect(_show(r.text, r.selection), 'a~~«$_flagTr»~~b');

      final cursor = applyFormat(
        text,
        const TextSelection.collapsed(offset: 3),
        MarkdownFormat.inlineCode,
      )!;
      expect(_show(cursor.text, cursor.selection), 'a`‸`${_flagTr}b');
    });

    test('a decomposed İ (I + U+0307) keeps its combining mark', () {
      final text = 'a${_decomposedI}b'; // İ spans offsets 1..3
      final r = applyFormat(
        text,
        const TextSelection(baseOffset: 1, extentOffset: 2),
        MarkdownFormat.bold,
      )!;
      expect(_show(r.text, r.selection), 'a**«$_decomposedI»**b');

      final cursor = applyFormat(
        text,
        const TextSelection.collapsed(offset: 2),
        MarkdownFormat.bold,
      )!;
      expect(cursor.text, 'a****${_decomposedI}b');
    });
  });

  group('20000 code point limit', () {
    test('a format that would exceed the limit is refused', () {
      final full = 'a' * noteBodyMaxLength;
      expect(
        applyFormat(full, TextSelection.collapsed(offset: full.length), MarkdownFormat.bold),
        isNull,
      );
      expect(
        applyFormat(full, const TextSelection.collapsed(offset: 0), MarkdownFormat.h1),
        isNull,
      );
      expect(
        applyFormat(
          'a' * (noteBodyMaxLength - 1),
          const TextSelection.collapsed(offset: 0),
          MarkdownFormat.rule,
        ),
        isNull,
      );
    });

    test('reaching the limit exactly is allowed, one more is refused', () {
      final fits = 'a' * (noteBodyMaxLength - 4);
      final r = applyFormat(
        fits,
        TextSelection.collapsed(offset: fits.length),
        MarkdownFormat.bold,
      );
      expect(r!.text.runes.length, noteBodyMaxLength);

      final over = 'a' * (noteBodyMaxLength - 3);
      expect(
        applyFormat(over, TextSelection.collapsed(offset: over.length), MarkdownFormat.bold),
        isNull,
      );
    });

    test('the limit counts code points, not UTF-16 units', () {
      final emojis = _smile * 9999; // 19998 UTF-16 units, 9999 code points
      final r = applyFormat(
        emojis,
        TextSelection.collapsed(offset: emojis.length),
        MarkdownFormat.bold,
      );
      expect(r, isNotNull);
      expect(r!.text.length, greaterThan(noteBodyMaxLength));
      expect(r.text.runes.length, 10003);
    });

    test('removing marks from an over-long text is still allowed', () {
      final inner = 'a' * noteBodyMaxLength;
      final text = '**$inner**';
      final r = applyFormat(
        text,
        TextSelection(baseOffset: 2, extentOffset: 2 + inner.length),
        MarkdownFormat.bold,
      );
      expect(r!.text, inner);
    });
  });
}
