import 'package:flutter/material.dart';
import 'package:varys/features/notes/domain/markdown_format.dart';

/// Format buttons above the note body: one 48x48 IconButton per
/// [MarkdownFormat] with a Turkish tooltip, in one horizontally scrolled
/// row. A button calls [onFormat]; it never takes the focus from the body
/// field (the row is a [TextFieldTapRegion], so a tap here does not count as
/// a tap outside the field and the keyboard stays open).
class MarkdownToolbar extends StatelessWidget {
  const MarkdownToolbar({super.key, required this.onFormat, this.enabled = true});

  final ValueChanged<MarkdownFormat> onFormat;
  final bool enabled;

  static const Map<MarkdownFormat, String> tooltips = {
    MarkdownFormat.h1: 'Başlık 1',
    MarkdownFormat.h2: 'Başlık 2',
    MarkdownFormat.h3: 'Başlık 3',
    MarkdownFormat.bold: 'Kalın',
    MarkdownFormat.italic: 'İtalik',
    MarkdownFormat.strike: 'Üstü çizili',
    MarkdownFormat.inlineCode: 'Satır içi kod',
    MarkdownFormat.codeBlock: 'Kod bloğu',
    MarkdownFormat.bulletList: 'Madde işaretli liste',
    MarkdownFormat.numberedList: 'Numaralı liste',
    MarkdownFormat.taskList: 'Yapılacaklar listesi',
    MarkdownFormat.quote: 'Alıntı',
    MarkdownFormat.rule: 'Yatay çizgi',
    MarkdownFormat.link: 'Bağlantı',
    MarkdownFormat.table: 'Tablo',
  };

  static Key buttonKey(MarkdownFormat f) => ValueKey('note-format-${f.name}');

  static Widget _icon(MarkdownFormat f) => switch (f) {
    MarkdownFormat.h1 => const _HeadingIcon('H1'),
    MarkdownFormat.h2 => const _HeadingIcon('H2'),
    MarkdownFormat.h3 => const _HeadingIcon('H3'),
    MarkdownFormat.bold => const Icon(Icons.format_bold),
    MarkdownFormat.italic => const Icon(Icons.format_italic),
    MarkdownFormat.strike => const Icon(Icons.format_strikethrough),
    MarkdownFormat.inlineCode => const Icon(Icons.code),
    MarkdownFormat.codeBlock => const Icon(Icons.data_object),
    MarkdownFormat.bulletList => const Icon(Icons.format_list_bulleted),
    MarkdownFormat.numberedList => const Icon(Icons.format_list_numbered),
    MarkdownFormat.taskList => const Icon(Icons.checklist),
    MarkdownFormat.quote => const Icon(Icons.format_quote),
    MarkdownFormat.rule => const Icon(Icons.horizontal_rule),
    MarkdownFormat.link => const Icon(Icons.link),
    MarkdownFormat.table => const Icon(Icons.table_chart_outlined),
  };

  @override
  Widget build(BuildContext context) {
    return TextFieldTapRegion(
      child: SingleChildScrollView(
        key: const ValueKey('note-format-toolbar'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final f in MarkdownFormat.values)
              IconButton(
                key: buttonKey(f),
                tooltip: tooltips[f],
                icon: _icon(f),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: enabled ? () => onFormat(f) : null,
              ),
          ],
        ),
      ),
    );
  }
}

/// "H1"-style label sized like an icon; it never wraps or grows with the
/// text scale beyond the 48x48 button.
class _HeadingIcon extends StatelessWidget {
  const _HeadingIcon(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return SizedBox.square(
      dimension: 24,
      child: FittedBox(
        child: Text(
          label,
          maxLines: 1,
          textScaler: TextScaler.noScaling,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ),
    );
  }
}
