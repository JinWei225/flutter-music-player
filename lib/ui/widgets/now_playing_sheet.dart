import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/player/player_model.dart';
import 'album_art.dart';
import 'player/queue_list.dart';
import 'player/seek_bar.dart';
import 'player/transport_buttons.dart';
import 'player/volume_control.dart';

/// Full-screen player for compact layouts, where the bottom bar only has room
/// for a mini player. Carries every control the desktop player bar has:
/// seek, transport, shuffle, repeat, volume and the queue.
class NowPlayingSheet extends StatelessWidget {
  const NowPlayingSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const NowPlayingSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final track = player.currentTrack;

    // Material rather than a decorated Container: the queue rows paint their
    // ink on the nearest Material ancestor.
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92,
        child: Column(
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: track == null
                  ? Center(
                      child: Text(
                        'Nothing playing',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    )
                  : _Body(player: player),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final PlayerModel player;

  const _Body({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final track = player.currentTrack!;
    final artSize = MediaQuery.sizeOf(context).width * 0.62;
    final queueLength = player.queueInPlayOrder.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Column(
              children: [
                AlbumArt(size: artSize, radius: 14, track: track),
                const SizedBox(height: 28),
                Text(
                  track.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${track.artist}  ·  ${track.album}',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 22),
                const SeekBar(),
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ShuffleButton(size: 22, compact: false),
                    SizedBox(width: 8),
                    SkipButton.previous(size: 38, prominent: true),
                    SizedBox(width: 6),
                    PlayPauseButton(diameter: 66, iconSize: 36),
                    SizedBox(width: 6),
                    SkipButton.next(size: 38, prominent: true),
                    SizedBox(width: 8),
                    RepeatButton(size: 22, compact: false),
                  ],
                ),
                const SizedBox(height: 12),
                const VolumeControl(),
                const SizedBox(height: 10),
              ],
            ),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 6),
            child: Row(
              children: [
                Icon(
                  Icons.queue_music_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'Queue',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$queueLength songs',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // Inside a scroll view already, so the list must size to its content.
          const QueueList(
            shrinkWrap: true,
            horizontalPadding: 24,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
