import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../breakpoints.dart';
import '../theme.dart';
import 'terminal_widgets.dart';

/// True where the shell uses the phone layout. Pages ask this rather than
/// measuring themselves, since on desktop they sit inside a panel that can be
/// narrow too.
bool isPhoneLayout(BuildContext context) =>
    MediaQuery.sizeOf(context).width < kCompactBreakpoint;

/// The phone's top line, `mewsic ~/songs`, with an optional control (the
/// sort menu) and the theme toggle on the right. The sidebar carries the
/// toggle everywhere else.
class PhoneTopLine extends StatelessWidget {
  final String path;
  final Widget? trailing;

  const PhoneTopLine({super.key, required this.path, this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final theme = context.watch<ThemeController>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'mewsic ',
                style: TextStyle(color: c.accent, fontWeight: FontWeight.w700),
                children: [
                  TextSpan(
                    text: path,
                    style: TextStyle(
                      color: c.textDim,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
          ),
          ?trailing,
          IconButton(
            onPressed: theme.toggle,
            icon: const ThemeGlyph(size: 18),
            color: c.textDim,
            tooltip: theme.isDark ? 'Light mode' : 'Dark mode',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
        ],
      ),
    );
  }
}

/// `all songs 16`: the phone's page heading with a dim count beside it.
class PhoneHeading extends StatelessWidget {
  final String title;
  final String? count;

  const PhoneHeading({super.key, required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 10),
          Text(count!, style: TextStyle(fontSize: 14, color: c.textDim)),
        ],
      ],
    );
  }
}
