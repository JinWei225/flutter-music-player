import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../../core/player/player_model.dart';
import '../theme.dart';
import 'album_art.dart';

class PlayerBar extends StatelessWidget {
  final bool queueOpen;
  final VoidCallback onToggleQueue;

  const PlayerBar({
    super.key,
    required this.queueOpen,
    required this.onToggleQueue,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final track = player.currentTrack;

    return Container(
      height: 88,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // --- now playing ---
          SizedBox(
            width: 240,
            child: Row(
              children: [
                const AlbumArt(size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track?.title ?? 'Nothing playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: track == null
                              ? scheme.onSurfaceVariant
                              : scheme.onSurface,
                        ),
                      ),
                      if (track != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- transport + seek ---
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _IconAction(
                      icon: Icons.skip_previous_rounded,
                      tooltip: 'Previous',
                      size: 26,
                      onPressed: player.hasTrack ? player.previous : null,
                    ),
                    const SizedBox(width: 8),
                    _PlayPauseButton(player: player),
                    const SizedBox(width: 8),
                    _IconAction(
                      icon: Icons.skip_next_rounded,
                      tooltip: 'Next',
                      size: 26,
                      onPressed: player.hasTrack ? player.next : null,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const _SeekBar(),
              ],
            ),
          ),

          // --- modes, queue, volume ---
          SizedBox(
            width: 300,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _IconAction(
                  icon: Icons.shuffle_rounded,
                  tooltip: player.shuffle ? 'Shuffle: on' : 'Shuffle: off',
                  active: player.shuffle,
                  onPressed: player.toggleShuffle,
                ),
                _RepeatButton(player: player),
                _IconAction(
                  icon: Icons.queue_music_rounded,
                  tooltip: queueOpen ? 'Hide queue' : 'Show queue',
                  active: queueOpen,
                  onPressed: onToggleQueue,
                ),
                const SizedBox(width: 4),
                const _VolumeControl(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  final PlayerModel player;

  const _PlayPauseButton({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = player.hasTrack;
    return Tooltip(
      message: player.isPlaying ? 'Pause (Space)' : 'Play (Space)',
      child: Material(
        color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? player.togglePlayPause : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 24,
              color: enabled ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _RepeatButton extends StatelessWidget {
  final PlayerModel player;

  const _RepeatButton({required this.player});

  @override
  Widget build(BuildContext context) {
    final (icon, tooltip) = switch (player.repeat) {
      RepeatMode.off => (Icons.repeat_rounded, 'Repeat: off'),
      RepeatMode.all => (Icons.repeat_rounded, 'Repeat: list'),
      RepeatMode.one => (Icons.repeat_one_rounded, 'Repeat: one'),
    };
    return _IconAction(
      icon: icon,
      tooltip: tooltip,
      active: player.repeat != RepeatMode.off,
      onPressed: player.cycleRepeat,
    );
  }
}

/// Draggable position bar. Dragging is tracked locally so the thumb does not
/// snap back to the stream's value mid-gesture.
class _SeekBar extends StatefulWidget {
  const _SeekBar();

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, positionSnap) {
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durationSnap) {
            final duration = durationSnap.data ??
                player.currentTrack?.duration ??
                Duration.zero;
            final totalMs = duration.inMilliseconds.toDouble();
            final positionMs =
                positionSnap.data?.inMilliseconds.toDouble() ?? 0;
            final value = _dragValue ?? positionMs.clamp(0, totalMs);

            return Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(
                    formatDuration(Duration(milliseconds: value.round())),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      min: 0,
                      max: totalMs > 0 ? totalMs : 1,
                      value: totalMs > 0 ? value.clamp(0, totalMs) : 0,
                      onChanged: totalMs > 0
                          ? (v) => setState(() => _dragValue = v)
                          : null,
                      onChangeEnd: (v) {
                        player.seek(Duration(milliseconds: v.round()));
                        setState(() => _dragValue = null);
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    formatDuration(duration),
                    style: TextStyle(
                      fontSize: 11,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final v = player.volume;

    final icon = v == 0
        ? Icons.volume_off_rounded
        : v < 0.5
            ? Icons.volume_down_rounded
            : Icons.volume_up_rounded;

    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        SizedBox(
          width: 110,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              trackHeight: 3,
            ),
            child: Slider(
              min: 0,
              max: 1,
              value: v,
              onChanged: player.setVolume,
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(v * 100).round()}',
            style: TextStyle(
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double size;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: size),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: active ? scheme.primary : scheme.onSurfaceVariant,
      disabledColor: scheme.onSurfaceVariant.withValues(alpha: 0.35),
    );
  }
}
