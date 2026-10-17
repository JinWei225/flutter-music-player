import 'package:flutter/material.dart';

import '../theme.dart';

// Small pieces of the terminal look shared across pages: square buttons,
// the glyphs JetBrains Mono lacks, column headings and divider rules.

/// Uppercase column heading: `#  TITLE  ARTIST`, `UP NEXT`, `ALBUM`.
TextStyle columnHeadingStyle(BuildContext context) => TextStyle(
  fontSize: 11,
  height: 1.5,
  letterSpacing: 1.0,
  color: TerminalColors.of(context).textDim,
);

/// Lowercases an album name and joins its words with dashes for the path
/// breadcrumb: "Saltwater Hymns" -> "saltwater-hymns".
String pathSlug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? '_' : slug;
}

/// A square button with a glyph and a lowercase label. [primary] is the
/// accent-filled `▶ play all`; otherwise it is outlined (`⤮ shuffle`).
class TermButton extends StatelessWidget {
  final String label;
  final Widget? glyph;
  final VoidCallback? onPressed;
  final bool primary;

  /// 44 on a phone so the button is a comfortable tap target.
  final double minHeight;

  const TermButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.glyph,
    this.primary = false,
    this.minHeight = 0,
  });

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final fg = primary ? c.background : c.text;

    return Material(
      color: primary ? c.accent : Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: primary ? c.accent : c.borderStrong),
      ),
      child: InkWell(
        onTap: onPressed,
        hoverColor: primary ? Colors.white.withValues(alpha: 0.08) : c.hover,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: IconTheme.merge(
              data: IconThemeData(color: fg, size: 15),
              child: DefaultTextStyle.merge(
                style: TextStyle(
                  color: fg,
                  fontWeight: primary ? FontWeight.w700 : FontWeight.w400,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (glyph != null) ...[glyph!, const SizedBox(width: 8)],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `❚❚`, which JetBrains Mono does not have, drawn as two bars sized to the
/// surrounding text.
class PauseGlyph extends StatelessWidget {
  final double size;
  final Color? color;

  const PauseGlyph({super.key, this.size = 13, this.color});

  @override
  Widget build(BuildContext context) {
    final fill = color ?? DefaultTextStyle.of(context).style.color;
    final bar = SizedBox(
      width: size * 0.26,
      height: size * 0.82,
      child: ColoredBox(color: fill ?? Colors.white),
    );
    return SizedBox(
      width: size,
      height: size * 1.2,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [bar, SizedBox(width: size * 0.2), bar],
      ),
    );
  }
}

/// `⤮`, missing from the font: the square-cornered Material shuffle icon.
class ShuffleGlyph extends StatelessWidget {
  final double size;
  final Color? color;

  const ShuffleGlyph({super.key, this.size = 15, this.color});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.shuffle_sharp, size: size, color: color);
}

/// `◐`, missing from the font: the half-filled contrast icon.
class ThemeGlyph extends StatelessWidget {
  final double size;
  final Color? color;

  const ThemeGlyph({super.key, this.size = 14, this.color});

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.contrast_sharp, size: size, color: color);
}

/// A labelled rule: `UP NEXT ──────────── 5`.
class SectionRule extends StatelessWidget {
  final String label;
  final String? trailing;

  const SectionRule({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final style = columnHeadingStyle(context);
    return Row(
      children: [
        Text(label, style: style),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: c.border)),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing!, style: style),
        ],
      ],
    );
  }
}

/// The dashed rule under a table's column headings.
class DashedRule extends StatelessWidget {
  const DashedRule({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(
        painter: _DashPainter(TerminalColors.of(context).border),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;

  _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 3, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// A non-interactive `━━━━───` line, e.g. along the mini player's top edge.
class BoxCharLine extends StatelessWidget {
  final double fraction;
  final double height;
  final Color? done;

  const BoxCharLine({
    super.key,
    required this.fraction,
    this.height = 3,
    this.done,
  });

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return CustomPaint(
      size: Size(double.infinity, height),
      painter: _LinePainter(fraction, done ?? c.accent, c.borderStrong),
    );
  }
}

class _LinePainter extends CustomPainter {
  final double fraction;
  final Color done;
  final Color rest;

  _LinePainter(this.fraction, this.done, this.rest);

  @override
  void paint(Canvas canvas, Size size) => paintBoxCharLine(
    canvas,
    Offset.zero & size,
    fraction: fraction,
    done: done,
    rest: rest,
  );

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.fraction != fraction || old.done != done || old.rest != rest;
}

/// Shown while the library is scanned, in place of a spinner.
class LoadingNote extends StatelessWidget {
  const LoadingNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'scanning library…',
        style: TextStyle(color: TerminalColors.of(context).textDim),
      ),
    );
  }
}
