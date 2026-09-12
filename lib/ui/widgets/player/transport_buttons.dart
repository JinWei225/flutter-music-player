import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../../../core/player/player_model.dart';

/// Round primary-coloured play/pause control. Sized by the caller: 40 in the
/// player bar, 66 on the phone sheet.
class PlayPauseButton extends StatelessWidget {
  final double diameter;
  final double iconSize;

  /// Mentions the Space shortcut in the tooltip; only true where a keyboard
  /// is likely.
  final bool showShortcut;

  const PlayPauseButton({
    super.key,
    this.diameter = 40,
    this.iconSize = 24,
    this.showShortcut = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final enabled = player.hasTrack;
    final verb = player.isPlaying ? 'Pause' : 'Play';
    return Tooltip(
      message: showShortcut ? '$verb (Space)' : verb,
      child: Material(
        color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? player.togglePlayPause : null,
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: Icon(
              player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: iconSize,
              color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Previous / next. [prominent] draws the icon in the foreground colour at
/// normal density, for the phone sheet where it is a primary control.
class SkipButton extends StatelessWidget {
  final bool forward;
  final double size;
  final bool prominent;

  const SkipButton.previous({super.key, this.size = 26, this.prominent = false})
    : forward = false;
  const SkipButton.next({super.key, this.size = 26, this.prominent = false})
    : forward = true;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    return PlayerIconButton(
      icon: forward ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
      tooltip: forward ? 'Next' : 'Previous',
      size: size,
      compact: !prominent,
      color: prominent ? scheme.onSurface : null,
      onPressed: player.hasTrack
          ? (forward ? player.next : player.previous)
          : null,
    );
  }
}

class ShuffleButton extends StatelessWidget {
  final double size;
  final bool compact;

  const ShuffleButton({super.key, this.size = 20, this.compact = true});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    return PlayerIconButton(
      icon: Icons.shuffle_rounded,
      tooltip: player.shuffle ? 'Shuffle: on' : 'Shuffle: off',
      active: player.shuffle,
      size: size,
      compact: compact,
      onPressed: player.toggleShuffle,
    );
  }
}

class RepeatButton extends StatelessWidget {
  final double size;
  final bool compact;

  const RepeatButton({super.key, this.size = 20, this.compact = true});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final (icon, tooltip) = switch (player.repeat) {
      RepeatMode.off => (Icons.repeat_rounded, 'Repeat: off'),
      RepeatMode.all => (Icons.repeat_rounded, 'Repeat: list'),
      RepeatMode.one => (Icons.repeat_one_rounded, 'Repeat: one'),
    };
    return PlayerIconButton(
      icon: icon,
      tooltip: tooltip,
      active: player.repeat != RepeatMode.off,
      size: size,
      compact: compact,
      onPressed: player.cycleRepeat,
    );
  }
}

/// Icon button in the player's muted style; [active] lights it in the accent.
class PlayerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final bool compact;
  final double size;
  final Color? color;

  const PlayerIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.compact = true,
    this.size = 20,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: size),
      tooltip: tooltip,
      visualDensity: compact ? VisualDensity.compact : null,
      color: active ? scheme.primary : (color ?? scheme.onSurfaceVariant),
      disabledColor: scheme.onSurfaceVariant.withValues(alpha: 0.35),
    );
  }
}
