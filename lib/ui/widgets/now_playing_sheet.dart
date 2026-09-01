import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../../core/player/player_model.dart';
import '../theme.dart';
import 'album_art.dart';

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

    // Material rather than a decorated Container: the queue's ListTiles paint
    // their ink on the nearest Material ancestor.
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
                      child: Text('Nothing playing',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
        children: [
          AlbumArt(size: artSize, radius: 14),
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
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 22),
          const _Seek(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: player.toggleShuffle,
                icon: const Icon(Icons.shuffle_rounded),
                iconSize: 22,
                color: player.shuffle ? scheme.primary : scheme.onSurfaceVariant,
                tooltip: player.shuffle ? 'Shuffle: on' : 'Shuffle: off',
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: player.previous,
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 38,
                color: scheme.onSurface,
                tooltip: 'Previous',
              ),
              const SizedBox(width: 6),
              Material(
                color: scheme.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: player.togglePlayPause,
                  child: SizedBox(
                    width: 66,
                    height: 66,
                    child: Icon(
                      player.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 36,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: player.next,
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 38,
                color: scheme.onSurface,
                tooltip: 'Next',
              ),
              const SizedBox(width: 8),
              _RepeatButton(player: player),
            ],
          ),
          const SizedBox(height: 12),
          _Volume(player: player),
          const SizedBox(height: 10),
          const Divider(height: 24),
          _Queue(player: player),
        ],
      ),
    );
  }
}

class _Seek extends StatefulWidget {
  const _Seek();

  @override
  State<_Seek> createState() => _SeekState();
}

class _SeekState extends State<_Seek> {
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

            return Column(
              children: [
                Slider(
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatDuration(Duration(milliseconds: value.round())),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        formatDuration(duration),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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

class _RepeatButton extends StatelessWidget {
  final PlayerModel player;

  const _RepeatButton({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, tooltip) = switch (player.repeat) {
      RepeatMode.off => (Icons.repeat_rounded, 'Repeat: off'),
      RepeatMode.all => (Icons.repeat_rounded, 'Repeat: list'),
      RepeatMode.one => (Icons.repeat_one_rounded, 'Repeat: one'),
    };
    return IconButton(
      onPressed: player.cycleRepeat,
      icon: Icon(icon),
      iconSize: 22,
      tooltip: tooltip,
      color: player.repeat != RepeatMode.off
          ? scheme.primary
          : scheme.onSurfaceVariant,
    );
  }
}

class _Volume extends StatelessWidget {
  final PlayerModel player;

  const _Volume({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = player.volume;
    return Row(
      children: [
        Icon(
          v == 0
              ? Icons.volume_off_rounded
              : v < 0.5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
          size: 20,
          color: scheme.onSurfaceVariant,
        ),
        Expanded(
          child: Slider(min: 0, max: 1, value: v, onChanged: player.setVolume),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(v * 100).round()}',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Queue extends StatelessWidget {
  final PlayerModel player;

  const _Queue({required this.player});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tracks = player.queueInPlayOrder;
    final current = player.currentQueuePosition;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.queue_music_rounded,
                size: 18, color: scheme.onSurfaceVariant),
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
              '${tracks.length} songs',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Inside a scroll view already, so the list must size to its content.
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            final isCurrent = i == current;
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 24,
                child: isCurrent
                    ? Icon(Icons.equalizer_rounded,
                        size: 16, color: scheme.primary)
                    : Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
              ),
              title: Text(
                t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  color: isCurrent ? scheme.primary : scheme.onSurface,
                ),
              ),
              subtitle: Text(
                t.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5),
              ),
              trailing: Text(
                formatDuration(t.duration),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
              onTap: () => player.playQueuePosition(i),
            );
          },
        ),
      ],
    );
  }
}
