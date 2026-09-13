import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/track.dart';
import '../../core/player/player_model.dart';
import 'album_art.dart';
import 'player/queue_list.dart';
import 'player/seek_bar.dart';

/// Now Playing for wide layouts: the current track's art and position on top,
/// the queue in playback order underneath. Docked beside the library on
/// desktop; slid over it on a tablet held upright. Transport lives in the
/// player bar, which is always visible alongside, so it is not repeated here.
class NowPlayingPanel extends StatelessWidget {
  final double width;
  final VoidCallback onClose;

  /// Adds a shadow for when the panel floats over the library instead of
  /// sitting beside it.
  final bool elevated;

  const NowPlayingPanel({
    super.key,
    required this.width,
    required this.onClose,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final track = player.currentTrack;
    final tracks = player.queueInPlayOrder;
    final position = player.currentQueuePosition;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(left: BorderSide(color: scheme.outline)),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(-6, 0),
                ),
              ]
            : null,
      ),
      // Material so the queue rows have something to paint their ink on.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  Text(
                    'Now Playing',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Hide Now Playing',
                    color: scheme.onSurfaceVariant,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: scheme.outline),
            Expanded(
              child: track == null
                  ? Center(
                      child: Text(
                        'Nothing playing',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  // One list so the art scrolls away under a long queue
                  // rather than pinning the queue into a short strip.
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: tracks.length + 2,
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return _Hero(track: track, width: width);
                        }
                        if (i == 1) {
                          return _UpNextHeader(
                            position: position,
                            count: tracks.length,
                          );
                        }
                        final index = i - 2;
                        final t = tracks[index];
                        return QueueRow(
                          index: index,
                          title: t.title,
                          artist: t.artist,
                          duration: t.duration,
                          isCurrent: index == position,
                          isPast: index < position,
                          onTap: () => player.playQueuePosition(index),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final Track track;
  final double width;

  const _Hero({required this.track, required this.width});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AlbumArt(size: width - 32, radius: 10, track: track),
          const SizedBox(height: 14),
          Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.25,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${track.artist}  ·  ${track.album}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          const SeekBar(dense: true),
        ],
      ),
    );
  }
}

class _UpNextHeader extends StatelessWidget {
  final int position;
  final int count;

  const _UpNextHeader({required this.position, required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: scheme.outline)),
      ),
      child: Row(
        children: [
          Text(
            'Up next',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            '${position + 1} of $count',
            style: TextStyle(
              fontSize: 11.5,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
