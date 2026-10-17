import 'package:flutter/material.dart';

import '../theme.dart';

/// A boxed region with its name set into the top border, `┤ name ├`, the way
/// htop or lazygit frame their panes. The sidebar, the main content, Now
/// Playing and the player bar are each one of these.
///
/// The label straddles the border, so the box itself starts [labelInset]
/// below the widget's top edge; the label, and any [trailing] control on the
/// right of the border, stay inside the widget's bounds and so stay
/// hit-testable. Lay panels out with that in mind: two panels stacked with a
/// gap of `16 - labelInset` read as 16 apart.
class TerminalPanel extends StatelessWidget {
  /// Half the label's line height: where the border runs through it.
  static const double labelInset = 9;

  /// Set in the top border. Null leaves the border unbroken (the icon rail,
  /// which is too narrow for a name).
  final String? title;
  final Widget child;

  /// Draws the border and title in the accent: the main content panel.
  final bool highlighted;

  /// Sits on the top border at the right, e.g. a close button.
  final Widget? trailing;

  /// Space between the border and [child]. The top value is measured from
  /// the border line, not the widget's top edge.
  final EdgeInsets padding;

  const TerminalPanel({
    super.key,
    required this.title,
    required this.child,
    this.highlighted = false,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 11, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final line = highlighted ? c.accent : c.border;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          top: labelInset,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.background,
              border: Border.all(color: line),
            ),
          ),
        ),
        Padding(
          padding: padding.copyWith(top: padding.top + labelInset),
          child: child,
        ),
        if (title != null)
          Positioned(
            top: 0,
            left: 10,
            right: trailing == null ? 10 : 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _OnBorder(
                child: Text(
                  '┤ $title ├',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: highlighted ? c.accent : c.textDim,
                  ),
                ),
              ),
            ),
          ),
        if (trailing != null)
          Positioned(top: 0, right: 10, child: _OnBorder(child: trailing!)),
      ],
    );
  }
}

/// Paints the ground colour behind [child] so it cuts the border line.
class _OnBorder extends StatelessWidget {
  final Widget child;

  const _OnBorder({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: TerminalPanel.labelInset * 2,
      color: TerminalColors.of(context).background,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      // Shrink-wrapped across, centred down: a plain alignment would stretch
      // the box (and its ground colour) over the whole border.
      child: Align(widthFactor: 1, child: child),
    );
  }
}
