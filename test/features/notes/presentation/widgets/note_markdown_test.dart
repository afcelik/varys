// NoteMarkdown: every block type in full mode, the list/card previews (line
// limits), nothing tappable (links of any scheme), no network request for
// images or raw HTML <img>, raw <script> as text, and an overflow matrix
// (8 widths x text scale 1.0 / 1.5) for full, list and card.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varys/core/theme/app_theme.dart';
import 'package:varys/features/notes/presentation/widgets/note_markdown.dart';

const _widths = [360.0, 600.0, 800.0, 801.0, 1000.0, 1200.0, 1400.0, 1800.0];
const _textScales = [1.0, 1.5];
const _height = 800.0;

final _wideTable = [
  '| ${List.generate(8, (i) => 'Sütun başlığı $i').join(' | ')} |',
  '| ${List.filled(8, '---').join(' | ')} |',
  '| ${List.generate(8, (i) => 'uzun hücre içeriği numara $i').join(' | ')} |',
].join('\n');

final _unbroken = 'ş' * 255;

/// Every block type, a 255 character line without spaces, a very wide table
/// and a long code line.
final _worst = [
  '# Birinci düzey başlık ${'uzun ' * 10}',
  '## İkinci düzey',
  '### Üçüncü düzey',
  _unbroken,
  '**kalın** *eğik* ~~çizik~~ `satır içi kod` [site](https://ornek.com)',
  '- madde bir\n- madde iki\n  - iç madde',
  '1. bir\n2. iki',
  '- [ ] yapılacak\n- [x] bitti',
  '> alıntı ${'söz ' * 30}',
  '---',
  _wideTable,
  '```\n${'kod' * 120}\n```',
  '![kedi](https://ornek.com/kedi.png)',
].join('\n\n');

/// Counts every use of the network image client; any call fails.
class _CountingHttpClient implements HttpClient {
  int calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw const SocketException('network disabled in test');
  }
}

Future<void> _pump(
  WidgetTester tester,
  String data,
  NoteMarkdownMode mode, {
  double width = 400,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = Size(width, _height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  if (textScale != 1.0) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
  final md = NoteMarkdown(key: const ValueKey('md'), data: data, mode: mode);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: mode == NoteMarkdownMode.full
            ? ListView(padding: const EdgeInsets.all(16), children: [md])
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [md]),
              ),
      ),
    ),
  );
}

/// Root spans of every text drawn under the NoteMarkdown (RichText and
/// SelectableText).
List<InlineSpan> _rootSpans(WidgetTester tester) {
  final under = find.descendant(
    of: find.byKey(const ValueKey('md')),
    matching: find.byWidgetPredicate((_) => true),
  );
  return [
    for (final w in tester.widgetList(under))
      if (w is RichText) w.text else if (w is SelectableText) w.textSpan ?? TextSpan(text: w.data),
  ];
}

List<TextSpan> _allSpans(WidgetTester tester) {
  final out = <TextSpan>[];
  for (final root in _rootSpans(tester)) {
    root.visitChildren((s) {
      if (s is TextSpan) out.add(s);
      return true;
    });
  }
  return out;
}

String _visibleText(WidgetTester tester) =>
    _rootSpans(tester).map((s) => s.toPlainText()).join('\n');

/// The span whose own text is [text] (first match).
TextSpan _span(WidgetTester tester, String text) =>
    _allSpans(tester).firstWhere((s) => s.text == text, orElse: () => fail('no span "$text"'));

/// Style of [span] merged with its ancestors' styles.
TextStyle _effectiveStyle(WidgetTester tester, TextSpan target) {
  for (final root in _rootSpans(tester)) {
    TextStyle? found;
    void walk(InlineSpan s, TextStyle acc) {
      final style = s.style == null ? acc : acc.merge(s.style);
      if (identical(s, target)) found = style;
      if (s is TextSpan) {
        for (final c in s.children ?? const <InlineSpan>[]) {
          walk(c, style);
        }
      }
    }

    walk(root, const TextStyle());
    if (found != null) return found!;
  }
  fail('span not found');
}

double _oneLineHeight(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final oneLine = TextPainter(
    text: TextSpan(text: 'Ağ', style: (paragraph.text as TextSpan).style),
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
  )..layout();
  final height = oneLine.height;
  oneLine.dispose();
  return height;
}

/// Lines the text at [finder] really draws (Step 29 method).
int _drawnLines(WidgetTester tester, Finder finder) =>
    (tester.getSize(finder).height / _oneLineHeight(tester, finder)).round();

final _md = find.byKey(const ValueKey('md'));

/// Position of the horizontal Scrollable of [scroll] (each SelectableText
/// inside also has a vertical one).
ScrollPosition _horizontalPosition(WidgetTester tester, Finder scroll) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: scroll,
            matching: find.byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
            ),
          )
          .first,
    )
    .position;

void main() {
  group('full mode blocks', () {
    testWidgets('headings show without # and in bold, larger than body', (tester) async {
      await _pump(tester, '# Bir\n\n## İki\n\n### Üç\n\nmetin', NoteMarkdownMode.full);
      final text = _visibleText(tester);
      expect(text, contains('Bir'));
      expect(text, isNot(contains('#')));
      final body = _effectiveStyle(tester, _span(tester, 'metin'));
      for (final h in ['Bir', 'İki', 'Üç']) {
        final style = _effectiveStyle(tester, _span(tester, h));
        expect(style.fontWeight!.value, greaterThanOrEqualTo(600), reason: h);
        expect(style.fontSize!, greaterThanOrEqualTo(body.fontSize!), reason: h);
      }
      expect(_effectiveStyle(tester, _span(tester, 'Bir')).fontSize!, greaterThan(body.fontSize!));
    });

    testWidgets('bold, italic, strike and inline code styles', (tester) async {
      await _pump(tester, '**kalın** *eğik* ~~çizik~~ `kod`', NoteMarkdownMode.full);
      expect(_visibleText(tester), isNot(contains('*')));
      expect(
        _effectiveStyle(tester, _span(tester, 'kalın')).fontWeight!.value,
        greaterThanOrEqualTo(600),
      );
      expect(_effectiveStyle(tester, _span(tester, 'eğik')).fontStyle, FontStyle.italic);
      expect(
        _effectiveStyle(tester, _span(tester, 'çizik')).decoration,
        TextDecoration.lineThrough,
      );
      expect(_effectiveStyle(tester, _span(tester, 'kod')).fontFamily, 'monospace');
    });

    testWidgets('bullet and numbered lists show items and markers', (tester) async {
      await _pump(tester, '- elma\n- armut\n\n3. üç\n4. dört', NoteMarkdownMode.full);
      final text = _visibleText(tester);
      for (final t in ['elma', 'armut', 'üç', 'dört', '•', '3.', '4.']) {
        expect(text, contains(t), reason: t);
      }
      expect(text, isNot(contains('- ')));
    });

    testWidgets('task list is visual only: icons, no checkbox, a tap changes nothing', (
      tester,
    ) async {
      await _pump(tester, '- [ ] yap\n- [x] bitti', NoteMarkdownMode.full);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(_visibleText(tester), isNot(contains('[ ]')));
      await tester.tap(find.byIcon(Icons.check_box_outline_blank));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.check_box_outline_blank), findsOneWidget);
      expect(find.byIcon(Icons.check_box), findsOneWidget);
    });

    testWidgets('quote shows its text with a left border, no >', (tester) async {
      await _pump(tester, '> alıntı metni', NoteMarkdownMode.full);
      expect(_visibleText(tester), contains('alıntı metni'));
      expect(_visibleText(tester), isNot(contains('>')));
      final quoteBox = find.ancestor(
        of: find.text('alıntı metni', findRichText: true),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              ((w.decoration as BoxDecoration).border as Border?)?.left.width == 3,
        ),
      );
      expect(quoteBox, findsOneWidget);
    });

    testWidgets('horizontal rule is drawn, not shown as ---', (tester) async {
      await _pump(tester, 'üst\n\n---\n\nalt', NoteMarkdownMode.full);
      expect(_visibleText(tester), isNot(contains('---')));
      final rule = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            ((w.decoration as BoxDecoration).border as Border?)?.top.width == 1,
      );
      expect(rule, findsOneWidget);
    });

    testWidgets('a very wide table scrolls sideways without overflow at 360px', (tester) async {
      await _pump(tester, _wideTable, NoteMarkdownMode.full, width: 360);
      expect(tester.takeException(), isNull);
      expect(find.byType(Table), findsOneWidget);
      final scroll = find.ancestor(
        of: find.byType(Table),
        matching: find.byWidgetPredicate(
          (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
        ),
      );
      expect(scroll, findsOneWidget);
      final position = _horizontalPosition(tester, scroll);
      expect(position.maxScrollExtent, greaterThan(0));
      // The table is far wider than the window: start the drag on a visible
      // cell (its center is off screen).
      await tester.dragFrom(
        tester.getTopLeft(scroll) + const Offset(100, 20),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a code block is monospace and scrolls sideways', (tester) async {
      final code = 'kod' * 120;
      await _pump(tester, '```\n$code\n```', NoteMarkdownMode.full, width: 360);
      expect(tester.takeException(), isNull);
      expect(_effectiveStyle(tester, _span(tester, code)).fontFamily, 'monospace');
      final scroll = find.byWidgetPredicate(
        (w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
      );
      expect(scroll, findsOneWidget);
      expect(_horizontalPosition(tester, scroll).maxScrollExtent, greaterThan(0));
    });

    testWidgets('a 255 character line without spaces wraps without overflow', (tester) async {
      await _pump(tester, _unbroken, NoteMarkdownMode.full, width: 360);
      expect(tester.takeException(), isNull);
      expect(_visibleText(tester), contains(_unbroken));
    });

    testWidgets('an empty body draws nothing', (tester) async {
      await _pump(tester, '', NoteMarkdownMode.full);
      expect(_visibleText(tester), isEmpty);
      // Zero height counts as offstage for finders.
      expect(tester.getSize(find.byKey(const ValueKey('md'), skipOffstage: false)).height, 0);
    });
  });

  group('nothing is tappable', () {
    const links =
        '[site](https://ornek.com/yol) [tıkla](javascript:alert(1)) '
        '[dosya](file:///etc/passwd) [veri](data:text/html,x)';

    for (final mode in NoteMarkdownMode.values) {
      testWidgets('no text span has a tap recognizer, ${mode.name}', (tester) async {
        await _pump(tester, links, mode);
        final spans = _allSpans(tester);
        expect(spans, isNotEmpty);
        for (final s in spans) {
          expect(s.recognizer, isNull, reason: 'span "${s.text}" is tappable');
        }
        expect(
          find.byType(GestureDetector).evaluate().where((e) {
            final g = e.widget as GestureDetector;
            return g.onTap != null;
          }),
          isEmpty,
        );
      });
    }

    testWidgets('full: https shows its address; javascript:/file:/data: show only text', (
      tester,
    ) async {
      await _pump(tester, links, NoteMarkdownMode.full);
      final text = _visibleText(tester);
      expect(text, contains('site (https://ornek.com/yol)'));
      expect(text, contains('tıkla'));
      expect(text, contains('dosya'));
      expect(text, contains('veri'));
      expect(text, isNot(contains('javascript')));
      expect(text, isNot(contains('file:')));
      expect(text, isNot(contains('data:')));
    });

    testWidgets('full: the https address is plain body text (not link styled)', (tester) async {
      await _pump(tester, '[site](https://ornek.com) ve metin\n\nsade', NoteMarkdownMode.full);
      // The link text, its address and the rest are one plain run.
      final link = _span(tester, 'site (https://ornek.com) ve metin');
      final style = _effectiveStyle(tester, link);
      expect(style.color, _effectiveStyle(tester, _span(tester, 'sade')).color);
      expect(style.decoration, isNot(TextDecoration.underline));
    });

    testWidgets('full: tapping a javascript: link text does nothing', (tester) async {
      await _pump(tester, '[tıkla](javascript:alert(1))', NoteMarkdownMode.full);
      await tester.tap(find.text('tıkla', findRichText: true));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_visibleText(tester), 'tıkla');
    });

    for (final mode in [NoteMarkdownMode.list, NoteMarkdownMode.card]) {
      testWidgets('${mode.name}: links show only their text, no address', (tester) async {
        await _pump(tester, links, mode);
        expect(_visibleText(tester), 'site tıkla dosya veri');
      });
    }
  });

  group('images and raw HTML load nothing', () {
    const data =
        '![kedi](https://ornek.com/kedi.png)\n\n'
        'önce <img src="http://ornek.com/x.png"> sonra\n\n'
        '<script>alert(1)</script>';

    for (final mode in NoteMarkdownMode.values) {
      testWidgets('no network request and a placeholder, ${mode.name}', (tester) async {
        final client = _CountingHttpClient();
        debugNetworkImageHttpClientProvider = () => client;
        try {
          await _pump(tester, data, mode);
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump();
          expect(client.calls, 0, reason: 'network image client was used');
          expect(find.byType(Image), findsNothing);
          final text = _visibleText(tester);
          expect(text, contains('[Resim: kedi]'));
          expect(text, isNot(contains('https://ornek.com/kedi.png')));
        } finally {
          debugNetworkImageHttpClientProvider = null;
        }
      });
    }

    testWidgets('full: raw <img> and <script> are plain text, not interpreted', (tester) async {
      await _pump(tester, data, NoteMarkdownMode.full);
      final text = _visibleText(tester);
      expect(text, contains('<img src="http://ornek.com/x.png">'));
      expect(text, contains('<script>alert(1)</script>'));
      expect(find.byType(Image), findsNothing);
    });
  });

  group('list and card line limits', () {
    final long = List.generate(
      12,
      (i) => '## Başlık $i\n\nparagraf $i ${'kelime ' * 20}',
    ).join('\n\n');

    testWidgets('card draws at most 3 lines and marks the cut', (tester) async {
      await _pump(tester, long, NoteMarkdownMode.card, width: 360);
      expect(_drawnLines(tester, _md), NoteMarkdown.cardMaxLines);
      expect(tester.renderObject<RenderParagraph>(_md).didExceedMaxLines, isTrue);
      expect(_visibleText(tester), isNot(contains('#')));
    });

    testWidgets('list draws at most 2 lines', (tester) async {
      await _pump(tester, long, NoteMarkdownMode.list, width: 360);
      expect(_drawnLines(tester, _md), NoteMarkdown.listMaxLines);
      expect(tester.renderObject<RenderParagraph>(_md).didExceedMaxLines, isTrue);
    });

    testWidgets('a short body draws one line', (tester) async {
      await _pump(tester, 'kısa not', NoteMarkdownMode.card);
      expect(_drawnLines(tester, _md), 1);
      expect(tester.renderObject<RenderParagraph>(_md).didExceedMaxLines, isFalse);
    });

    testWidgets('card headings are bold at body size', (tester) async {
      await _pump(tester, '# Başlık\n\nmetin', NoteMarkdownMode.card);
      final heading = _effectiveStyle(tester, _span(tester, 'Başlık'));
      final body = _effectiveStyle(tester, _span(tester, 'metin'));
      expect(heading.fontWeight, FontWeight.w600);
      expect(heading.fontSize, body.fontSize);
      expect(_visibleText(tester), 'Başlık\nmetin');
    });

    testWidgets('card and list text is not selectable; full text is (one SelectionArea)', (
      tester,
    ) async {
      for (final mode in [NoteMarkdownMode.card, NoteMarkdownMode.list]) {
        await _pump(tester, '**kalın** metin', mode);
        expect(find.byType(SelectionArea), findsNothing, reason: mode.name);
        expect(find.byType(SelectableText), findsNothing, reason: mode.name);
        expect(find.byType(EditableText), findsNothing, reason: mode.name);
      }
      await _pump(tester, '**kalın** metin', NoteMarkdownMode.full);
      expect(find.descendant(of: _md, matching: find.byType(SelectionArea)), findsOneWidget);
    });

    testWidgets('a 20000 character body is cut in the card, drawn in full', (tester) async {
      final body = ('${'x' * 79}\n') * 250; // 20000 characters
      expect(body.length, 20000);
      await _pump(tester, body, NoteMarkdownMode.card, width: 360);
      expect(tester.takeException(), isNull);
      expect(_drawnLines(tester, _md), NoteMarkdown.cardMaxLines);
      await _pump(tester, body, NoteMarkdownMode.full, width: 360);
      expect(tester.takeException(), isNull);
      expect(_visibleText(tester), contains('x' * 79));
    });
  });

  group('overflow matrix', () {
    for (final width in _widths) {
      for (final scale in _textScales) {
        final label = '${width.toInt()}px x$scale';

        testWidgets('full, every block, $label', (tester) async {
          await _pump(tester, _worst, NoteMarkdownMode.full, width: width, textScale: scale);
          expect(tester.takeException(), isNull, reason: label);
          // Scroll to the end: the table and the code block lay out too.
          await tester.drag(find.byType(ListView), const Offset(0, -5000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
          final r = tester.getRect(_md);
          expect(r.left, greaterThanOrEqualTo(-0.5), reason: label);
          expect(r.right, lessThanOrEqualTo(width + 0.5), reason: label);
        });

        testWidgets('card and list, every block, $label', (tester) async {
          await _pump(tester, _worst, NoteMarkdownMode.card, width: width, textScale: scale);
          expect(tester.takeException(), isNull, reason: '$label card');
          expect(_drawnLines(tester, _md), lessThanOrEqualTo(NoteMarkdown.cardMaxLines));
          await _pump(tester, _worst, NoteMarkdownMode.list, width: width, textScale: scale);
          expect(tester.takeException(), isNull, reason: '$label list');
          expect(_drawnLines(tester, _md), lessThanOrEqualTo(NoteMarkdown.listMaxLines));
        });
      }
    }
  });
}
