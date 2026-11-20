import 'package:flutter_test/flutter_test.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:varys/features/notes/domain/markdown_preview.dart';
import 'package:varys/features/notes/domain/note_form.dart';

const _smile = '\u{1F600}';

/// Plain text of the preview of [data].
String _text(String data) => previewPlainText(buildMarkdownPreview(data));

/// Every element tag left in a sanitized tree.
Set<String> _tags(List<md.Node> nodes) {
  final out = <String>{};
  void walk(md.Node n) {
    if (n is md.Element) {
      out.add(n.tag);
      for (final c in n.children ?? const <md.Node>[]) {
        walk(c);
      }
    }
  }

  nodes.forEach(walk);
  return out;
}

String _sanitizedText(String data) => parseNoteMarkdown(data).map((n) => n.textContent).join('\n');

void main() {
  test('the escaped test character is what it claims (no lost escape)', () {
    expect(_smile.runes.toList(), [0x1F600]);
  });

  group('parseNoteMarkdown sanitizing', () {
    test('an https link keeps its text and shows its address; no a element is left', () {
      final nodes = parseNoteMarkdown('[site](https://ornek.com/yol)');
      expect(_tags(nodes), isNot(contains('a')));
      expect(_sanitizedText('[site](https://ornek.com/yol)'), 'site (https://ornek.com/yol)');
    });

    test('an autolink is not repeated', () {
      expect(_sanitizedText('https://ornek.com bak'), 'https://ornek.com bak');
    });

    test('javascript:, file: and data: links keep only their text', () {
      for (final href in [
        'javascript:alert(1)',
        'JAVASCRIPT:alert(1)',
        'file:///etc/passwd',
        'data:text/html,x',
      ]) {
        final nodes = parseNoteMarkdown('[tıkla]($href)');
        expect(_tags(nodes), isNot(contains('a')), reason: href);
        expect(_sanitizedText('[tıkla]($href)'), 'tıkla', reason: href);
      }
    });

    test('linkAddresses false drops the address', () {
      final nodes = parseNoteMarkdown('[site](https://ornek.com)', linkAddresses: false);
      expect(nodes.map((n) => n.textContent).join(), 'site');
    });

    test('an image becomes a text placeholder; no img element is left', () {
      final nodes = parseNoteMarkdown('![kedi](https://ornek.com/k.png)');
      expect(_tags(nodes), isNot(contains('img')));
      expect(_sanitizedText('![kedi](https://ornek.com/k.png)'), '[Resim: kedi]');
      expect(_sanitizedText('![](https://ornek.com/k.png)'), '[Resim]');
    });

    test('an image inside a link becomes the placeholder too', () {
      final nodes = parseNoteMarkdown('[![logo](https://o.com/l.png)](javascript:x)');
      expect(_tags(nodes), isNot(anyOf(contains('a'), contains('img'))));
      expect(nodes.map((n) => n.textContent).join(), '[Resim: logo]');
    });

    test('raw HTML is plain text, never an element', () {
      const html = '<script>alert(1)</script>\n\nmetin <img src="http://o.com/x.png"> son';
      final nodes = parseNoteMarkdown(html);
      expect(_tags(nodes), isNot(anyOf(contains('script'), contains('img'))));
      expect(_sanitizedText(html), contains('<script>alert(1)</script>'));
      expect(_sanitizedText(html), contains('<img src="http://o.com/x.png">'));
    });
  });

  group('buildMarkdownPreview blocks', () {
    test('headings are bold at body size, without #', () {
      expect(buildMarkdownPreview('# Başlık\nmetin'), const [
        PreviewSpan('Başlık', bold: true),
        PreviewSpan('\n'),
        PreviewSpan('metin'),
      ]);
      expect(buildMarkdownPreview('### Üç'), const [PreviewSpan('Üç', bold: true)]);
    });

    test('bullet list items get "• "', () {
      expect(_text('- elma\n- armut'), '• elma\n• armut');
    });

    test('numbered list items keep the list start', () {
      expect(_text('1. bir\n2. iki'), '1. bir\n2. iki');
      expect(_text('3. üç\n4. dört'), '3. üç\n4. dört');
    });

    test('nested list items are indented', () {
      expect(_text('- dış\n  - iç'), '• dış\n  • iç');
    });

    test('a loose list (blank lines between items) gives one line per item', () {
      expect(_text('- a\n\n- b'), '• a\n• b');
    });

    test('task list items get ☐ / ☑ instead of a bullet', () {
      expect(_text('- [ ] yap\n- [x] bitti'), '☐ yap\n☑ bitti');
    });

    test('a code block keeps its lines in code style, blank lines dropped', () {
      expect(buildMarkdownPreview('```dart\nkod 1\n\nkod 2\n```'), const [
        PreviewSpan('kod 1', code: true),
        PreviewSpan('\n'),
        PreviewSpan('kod 2', code: true),
      ]);
    });

    test('inline code is code style inside the line', () {
      expect(buildMarkdownPreview('a `b` c'), const [
        PreviewSpan('a '),
        PreviewSpan('b', code: true),
        PreviewSpan(' c'),
      ]);
    });

    test('a quote gets "│ " and keeps inline styles', () {
      expect(buildMarkdownPreview('> alıntı **kalın**'), const [
        PreviewSpan('│ alıntı '),
        PreviewSpan('kalın', bold: true),
      ]);
    });

    test('table rows join their cells with " · ", header cells bold', () {
      expect(buildMarkdownPreview('| a | b |\n| --- | --- |\n| x | y |'), const [
        PreviewSpan('a', bold: true),
        PreviewSpan(' · '),
        PreviewSpan('b', bold: true),
        PreviewSpan('\n'),
        PreviewSpan('x · y'),
      ]);
    });

    test('an image shows its alt text placeholder', () {
      expect(_text('önce ![kedi](https://o.com/k.png) sonra'), 'önce [Resim: kedi] sonra');
    });

    test('a link shows only its text (any scheme)', () {
      expect(_text('[site](https://o.com) ve [x](javascript:alert(1))'), 'site ve x');
    });

    test('raw HTML is plain text', () {
      expect(_text('<script>alert(1)</script>'), '<script>alert(1)</script>');
      expect(_text('a <b>kalın</b> c'), 'a <b>kalın</b> c');
    });

    test('a horizontal rule is "—" on its own line', () {
      expect(_text('a\n\n---\n\nb'), 'a\n—\nb');
    });

    test('bold, italic and strike runs', () {
      expect(buildMarkdownPreview('**k** *e* ~~s~~'), const [
        PreviewSpan('k', bold: true),
        PreviewSpan(' '),
        PreviewSpan('e', italic: true),
        PreviewSpan(' '),
        PreviewSpan('s', strike: true),
      ]);
    });
  });

  group('buildMarkdownPreview joining', () {
    test('blank lines vanish: consecutive blocks are joined with one newline', () {
      expect(_text('a\n\n\n\nb\n\n\nc'), 'a\nb\nc');
      expect(_text('# B\n\n- x\n\n> q'), 'B\n• x\n│ q');
    });

    test('soft line breaks inside a paragraph become spaces', () {
      expect(_text('satır bir\nsatır iki'), 'satır bir satır iki');
    });

    test('an empty or blank body gives no spans', () {
      expect(buildMarkdownPreview(''), isEmpty);
      expect(buildMarkdownPreview('\n\n   \n'), isEmpty);
    });

    test('emoji text passes through unchanged', () {
      expect(_text('# $_smile not'), '$_smile not');
    });
  });

  group('buildMarkdownPreview limits', () {
    test('at most previewMaxLines lines are built', () {
      final many = List.generate(100, (i) => '- madde $i').join('\n');
      final text = _text(many);
      expect('\n'.allMatches(text).length + 1, previewMaxLines);
      expect(text, startsWith('• madde 0\n• madde 1'));
    });

    test('a 20000 character body is cut and built quickly', () {
      final line = '## Başlık **kalın** `kod` [l](https://o.com) ${'x' * 40}\n';
      final body = (line * (noteBodyMaxLength ~/ line.length + 1)).substring(0, noteBodyMaxLength);
      expect(body.length, noteBodyMaxLength);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        buildMarkdownPreview(body);
      }
      sw.stop();
      // 20 builds of the cut input; the whole body is never parsed.
      expect(sw.elapsedMilliseconds, lessThan(2000), reason: '${sw.elapsedMilliseconds} ms');
      expect(_text(body).split('\n').length, lessThanOrEqualTo(previewMaxLines));
    });

    test('a single 20000 character line is cut to the source limit', () {
      final body = 'a' * noteBodyMaxLength;
      expect(_text(body).length, previewMaxSourceChars);
    });

    test('the cut never splits a surrogate pair', () {
      // The emoji's high surrogate sits at index previewMaxSourceChars - 1.
      final body = 'a' * (previewMaxSourceChars - 1) + _smile * 10;
      final text = _text(body);
      expect(text.length, previewMaxSourceChars - 1);
      for (final unit in text.codeUnits) {
        expect(unit >= 0xD800 && unit <= 0xDFFF, isFalse, reason: 'lone surrogate');
      }
    });
  });
}
