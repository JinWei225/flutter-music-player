import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/player/player_model.dart';
import '../theme.dart';
import 'album_art.dart';
import 'now_playing_sheet.dart';
import 'player/transport_buttons.dart';
import 'terminal_widgets.dart';

/// Compact-layout player strip: a progress line along the top edge, then the
/// track and pause/next. Tapping it opens [NowPlayingSheet] with the full
/// control set.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    final track = player.currentTrack;

    return Material(
      color: c.surfaceRaised,
      child: InkWell(
        onTap: track == null ? null : () => NowPlayingSheet.show(context),
        child: StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, snapshot) {
            final position = snapshot.data ?? Duration.zero;
            final total = track?.duration ?? Duration.zero;
            final fraction = total.inMilliseconds > 0
                ? position.inMilliseconds / total.inMilliseconds
                : 0.0;

            return Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.accent)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 8,
                    child: Center(child: BoxCharLine(fraction: fraction)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 6),
                    child: Row(
                      children: [
                        AlbumArt(
                          size: 40,
                          track: track,
                          outline: c.borderStrong,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                track?.title ?? 'nothing playing',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: track == null ? c.textDim : c.text,
                                ),
                              ),
                              if (track != null)
                                Text(
                                  '${track.artist} · '
                                  '${formatDuration(position)}/'
                                  '${formatDuration(total)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.textDim,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const PlayPauseButton(width: 44, height: 44),
                        const SkipButton.next(width: 44, height: 44),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
