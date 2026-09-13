import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/player/player_model.dart';
import 'album_art.dart';
import 'player/seek_bar.dart';
import 'player/transport_buttons.dart';
import 'player/volume_control.dart';

/// Below this width the bar drops the volume slider and narrows the track
/// block so the transport still has room (a tablet held upright).
const double _kRoomyBarWidth = 900;

class PlayerBar extends StatelessWidget {
  final bool nowPlayingOpen;
  final VoidCallback onToggleNowPlaying;

  const PlayerBar({
    super.key,
    required this.nowPlayingOpen,
    required this.onToggleNowPlaying,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final track = player.currentTrack;

    return LayoutBuilder(
      builder: (context, constraints) {
        final roomy = constraints.maxWidth >= _kRoomyBarWidth;
        // Transport block width; the sides split what is left equally so the
        // play button sits on the window's centre line, not the centre of
        // the space left over after two unequal side blocks.
        final centreWidth = (constraints.maxWidth * 0.42).clamp(280.0, 560.0);

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
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: roomy ? 240 : 200),
                    child: InkWell(
                      // The art doubles as a shortcut to the Now Playing panel.
                      onTap: track == null ? null : onToggleNowPlaying,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AlbumArt(size: 52, track: track),
                            const SizedBox(width: 12),
                            Flexible(
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
                    ),
                  ),
                ),
              ),

              // --- transport + seek ---
              SizedBox(
                width: centreWidth,
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ShuffleButton(),
                        SizedBox(width: 8),
                        SkipButton.previous(),
                        SizedBox(width: 8),
                        PlayPauseButton(showShortcut: true),
                        SizedBox(width: 8),
                        SkipButton.next(),
                        SizedBox(width: 8),
                        RepeatButton(),
                      ],
                    ),
                    SizedBox(height: 4),
                    SeekBar(inline: true, dense: true),
                  ],
                ),
              ),

              // --- now playing toggle, volume ---
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PlayerIconButton(
                      icon: Icons.queue_music_rounded,
                      tooltip: nowPlayingOpen
                          ? 'Hide Now Playing'
                          : 'Show Now Playing',
                      active: nowPlayingOpen,
                      onPressed: onToggleNowPlaying,
                    ),
                    if (roomy) ...[
                      const SizedBox(width: 4),
                      const VolumeControl(sliderWidth: 110, dense: true),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
