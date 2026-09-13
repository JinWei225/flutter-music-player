import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/album.dart';
import '../../core/player/player_model.dart';
import '../theme.dart';
import '../widgets/album_art.dart';
import '../widgets/edit_track_info_dialog.dart';
import '../widgets/track_row.dart';

class AlbumDetailPage extends StatelessWidget {
  final Album album;
  final VoidCallback onBack;

  const AlbumDetailPage({
    super.key,
    required this.album,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final current = player.currentTrack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 0),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Albums'),
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 640;
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, compact ? 14 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      AlbumArt(size: compact ? 96 : 160, radius: 10),
                      SizedBox(width: compact ? 14 : 22),
                      Expanded(
                        child: _Info(
                          album: album,
                          compact: compact,
                          // Beside a 96px cover there is not enough width for
                          // the buttons, so on a phone they move below.
                          actions: compact ? null : _actions(context, false),
                        ),
                      ),
                    ],
                  ),
                  if (compact) ...[
                    const SizedBox(height: 14),
                    _actions(context, true),
                  ],
                ],
              ),
            );
          },
        ),
        const TrackListHeader(showAlbum: false),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: album.tracks.length,
            itemBuilder: (context, i) {
              final t = album.tracks[i];
              return TrackRow(
                // Show the album's own track numbering, not the row position.
                leading: '${t.trackNumber ?? i + 1}',
                title: t.title,
                artist: t.artist,
                duration: t.duration,
                isCurrent: current == t,
                onPlay: () => player.playTracks(album.tracks, startIndex: i),
                onEdit: editTrackAction(context, t),
              );
            },
          ),
        ),
      ],
    );
  }

  /// When [fillWidth] the two buttons split the row evenly, which is what the
  /// phone layout wants; otherwise they size to their labels.
  Widget _actions(BuildContext context, bool fillWidth) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.read<PlayerModel>();

    final play = FilledButton.icon(
      onPressed: () =>
          player.playTracks(album.tracks, startIndex: 0, shuffle: false),
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: const Text('Play All', maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        padding: EdgeInsets.symmetric(
            horizontal: fillWidth ? 12 : 20, vertical: 14),
      ),
    );

    final shuffle = OutlinedButton.icon(
      onPressed: () => player.playTracks(album.tracks, shuffle: true),
      icon: const Icon(Icons.shuffle_rounded, size: 18),
      label: const Text('Shuffle', maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: EdgeInsets.symmetric(
            horizontal: fillWidth ? 12 : 20, vertical: 14),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
      ),
    );

    if (!fillWidth) {
      return Row(children: [play, const SizedBox(width: 10), shuffle]);
    }
    return Row(
      children: [
        Expanded(child: play),
        const SizedBox(width: 10),
        Expanded(child: shuffle),
      ],
    );
  }
}

class _Info extends StatelessWidget {
  final Album album;
  final bool compact;
  final Widget? actions;

  const _Info({required this.album, required this.compact, this.actions});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ALBUM',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: scheme.onSurfaceVariant,
          ),
        ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          album.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 21 : 30,
            fontWeight: FontWeight.w800,
            height: 1.1,
            color: scheme.onSurface,
          ),
        ),
        SizedBox(height: compact ? 4 : 8),
        Text(
          _subtitle(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (actions != null) ...[
          const SizedBox(height: 18),
          actions!,
        ],
      ],
    );
  }

  String _subtitle() {
    final parts = <String>[album.artist];
    if (album.year != null && album.year!.isNotEmpty) parts.add(album.year!);
    parts.add(
        '${album.tracks.length} ${album.tracks.length == 1 ? "song" : "songs"}');
    final total = album.totalDuration;
    if (total > Duration.zero) parts.add(formatDuration(total));
    return parts.join('  ·  ');
  }
}
