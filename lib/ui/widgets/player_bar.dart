import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/player/player_model.dart';
import '../theme.dart';
import 'album_art.dart';
import 'player/seek_bar.dart';
import 'player/transport_buttons.dart';
import 'player/volume_control.dart';
import 'terminal_panel.dart';

/// Below this width the bar drops the volume line so the transport still has
/// room (a tablet held upright).
const double _kRoomyBarWidth = 860;

/// The boxed `┤ player ├` panel: track, transport, volume and the queue
/// toggle on one row, the position line with its times on the next.
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
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    final track = player.currentTrack;

    return TerminalPanel(
      title: 'player',
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final roomy = constraints.maxWidth >= _kRoomyBarWidth;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // --- now playing ---
                  // The sides split what the transport leaves equally, so
                  // play/pause sits on the bar's centre line.
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        // The track doubles as a shortcut to Now Playing.
                        onTap: track == null ? null : onToggleNowPlaying,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AlbumArt(
                                size: 22,
                                track: track,
                                outline: c.borderStrong,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text.rich(
                                  track == null
                                      ? TextSpan(
                                          text: 'nothing playing',
                                          style: TextStyle(color: c.textDim),
                                        )
                                      : TextSpan(
                                          text: track.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: ' — ${track.artist}',
                                              style: TextStyle(
                                                color: c.textDim,
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                          ],
                                        ),
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
                  const SizedBox(width: 16),

                  // --- transport ---
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ShuffleButton(),
                      SizedBox(width: 4),
                      SkipButton.previous(),
                      SizedBox(width: 4),
                      PlayPauseButton(showShortcut: true),
                      SizedBox(width: 4),
                      SkipButton.next(),
                      SizedBox(width: 4),
                      RepeatButton(),
                    ],
                  ),
                  const SizedBox(width: 16),

                  // --- volume, queue toggle ---
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (roomy) ...[
                          const Flexible(
                            child: VolumeControl(sliderWidth: 96),
                          ),
                          const SizedBox(width: 16),
                        ],
                        _QueueToggle(
                          open: nowPlayingOpen,
                          onPressed: onToggleNowPlaying,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const SeekBar(inline: true),
            ],
          );
        },
      ),
    );
  }
}

/// `≡ queue`: shows or hides Now Playing. Filled while the panel is open.
class _QueueToggle extends StatelessWidget {
  final bool open;
  final VoidCallback onPressed;

  const _QueueToggle({required this.open, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return Tooltip(
      message: open ? 'Hide Now Playing' : 'Show Now Playing',
      child: Material(
        color: open ? c.selection : Colors.transparent,
        shape: RoundedRectangleBorder(side: BorderSide(color: c.borderStrong)),
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              '≡ queue',
              maxLines: 1,
              style: TextStyle(color: open ? c.accent : c.text2),
            ),
          ),
        ),
      ),
    );
  }
}
