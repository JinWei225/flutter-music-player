import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/player/player_model.dart';
import 'album_art.dart';
import 'now_playing_sheet.dart';

/// Compact-layout player strip. Only what fits on a phone; tapping it opens
/// [NowPlayingSheet] with the full control set.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final track = player.currentTrack;

    return InkWell(
      onTap: track == null ? null : () => NowPlayingSheet.show(context),
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outline)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            AlbumArt(size: 42, track: track),
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
                      fontSize: 13.5,
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
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: track == null ? null : player.togglePlayPause,
              icon: Icon(
                player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              iconSize: 30,
              color: scheme.onSurface,
              tooltip: player.isPlaying ? 'Pause' : 'Play',
            ),
            IconButton(
              onPressed: track == null ? null : player.next,
              icon: const Icon(Icons.skip_next_rounded),
              iconSize: 26,
              color: scheme.onSurface,
              tooltip: 'Next',
            ),
          ],
        ),
      ),
    );
  }
}
