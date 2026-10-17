import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../../../core/player/player_model.dart';
import '../../theme.dart';
import '../terminal_widgets.dart';

// The transport as mono glyphs: `⤮  |◂  ❚❚  ▸|  ↻`. Shuffle, repeat and the
// pause bars are not in JetBrains Mono, so those are square Material icons
// and a drawn glyph instead.

/// Accent-filled square block: `▶` while paused, `❚❚` while playing. Sized
/// by the caller: a compact block in the player bar, 88×52 on the phone
/// sheet, 44×44 in the mini player.
class PlayPauseButton extends StatelessWidget {
  final double width;
  final double height;
  final double glyphSize;

  /// Mentions the Space shortcut in the tooltip; only true where a keyboard
  /// is likely.
  final bool showShortcut;

  const PlayPauseButton({
    super.key,
    this.width = 50,
    this.height = 30,
    this.glyphSize = 13,
    this.showShortcut = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    final enabled = player.hasTrack;
    final verb = player.isPlaying ? 'Pause' : 'Play';
    final fg = enabled ? c.background : c.textDim;

    return Tooltip(
      message: showShortcut ? '$verb (Space)' : verb,
      child: Material(
        color: enabled ? c.accent : c.selection,
        child: InkWell(
          onTap: enabled ? player.togglePlayPause : null,
          hoverColor: Colors.white.withValues(alpha: 0.08),
          child: SizedBox(
            width: width,
            height: height,
            child: Center(
              child: player.isPlaying
                  ? PauseGlyph(size: glyphSize, color: fg)
                  : Text(
                      '▶',
                      style: TextStyle(
                        fontSize: glyphSize,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Previous / next as `|◂` and `▸|`. [outlined] boxes them, for the phone
/// sheet where they are primary controls.
class SkipButton extends StatelessWidget {
  final bool forward;
  final bool outlined;
  final double? width;
  final double? height;
  final double fontSize;

  const SkipButton.previous({
    super.key,
    this.outlined = false,
    this.width,
    this.height,
    this.fontSize = 13,
  }) : forward = false;

  const SkipButton.next({
    super.key,
    this.outlined = false,
    this.width,
    this.height,
    this.fontSize = 13,
  }) : forward = true;

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    final enabled = player.hasTrack;
    return GlyphButton(
      tooltip: forward ? 'Next' : 'Previous',
      outlined: outlined,
      width: width,
      height: height,
      onPressed: enabled ? (forward ? player.next : player.previous) : null,
      child: Text(
        forward ? '▸|' : '|◂',
        style: TextStyle(
          fontSize: fontSize,
          color: enabled ? c.text : c.textFaint,
        ),
      ),
    );
  }
}

class ShuffleButton extends StatelessWidget {
  /// Square tap target; null keeps the compact padded size of the bar.
  final double? extent;
  final double glyphSize;

  const ShuffleButton({super.key, this.extent, this.glyphSize = 15});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    return GlyphButton(
      tooltip: player.shuffle ? 'Shuffle: on' : 'Shuffle: off',
      width: extent,
      height: extent,
      onPressed: player.toggleShuffle,
      child: ShuffleGlyph(
        size: glyphSize,
        color: player.shuffle ? c.accent : c.textDim,
      ),
    );
  }
}

class RepeatButton extends StatelessWidget {
  final double? extent;
  final double glyphSize;

  const RepeatButton({super.key, this.extent, this.glyphSize = 15});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    final (icon, tooltip) = switch (player.repeat) {
      RepeatMode.off => (Icons.repeat_sharp, 'Repeat: off'),
      RepeatMode.all => (Icons.repeat_sharp, 'Repeat: list'),
      RepeatMode.one => (Icons.repeat_one_sharp, 'Repeat: one'),
    };
    return GlyphButton(
      tooltip: tooltip,
      width: extent,
      height: extent,
      onPressed: player.cycleRepeat,
      child: Icon(
        icon,
        size: glyphSize,
        color: player.repeat == RepeatMode.off ? c.textDim : c.accent,
      ),
    );
  }
}

/// A flat, square button around a glyph, optionally outlined. Without a
/// [width]/[height] it pads the glyph like the player bar's text buttons.
class GlyphButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;
  final bool outlined;
  final double? width;
  final double? height;

  const GlyphButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.outlined = false,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        type: MaterialType.transparency,
        shape: outlined
            ? RoundedRectangleBorder(side: BorderSide(color: c.borderStrong))
            : null,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: width,
            height: height,
            padding: width == null
                ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                : null,
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
