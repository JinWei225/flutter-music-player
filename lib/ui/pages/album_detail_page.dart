import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/album.dart';
import '../../core/player/player_model.dart';
import '../theme.dart';
import '../widgets/album_art.dart';
import '../widgets/edit_track_info_dialog.dart';
import '../widgets/phone_header.dart';
import '../widgets/play_next.dart';
import '../widgets/terminal_widgets.dart';
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
    final player = context.watch<PlayerModel>();
    final current = player.currentTrack;
    final phone = isPhoneLayout(context);
    // Only a compilation needs an artist per row; on a one-artist album it
    // would repeat the header on every line.
    final mixedArtists = album.tracks.map((t) => t.artist).toSet().length > 1;

    final list = ListView.builder(
      padding: EdgeInsets.only(top: phone ? 4 : 2, bottom: 8),
      itemCount: album.tracks.length,
      itemBuilder: (context, i) {
        final t = album.tracks[i];
        return TrackRow(
          // Show the album's own track numbering, not the row position.
          leading: '${t.trackNumber ?? i + 1}',
          title: t.title,
          artist: mixedArtists ? t.artist : null,
          duration: t.duration,
          isCurrent: current == t,
          onPlay: () => player.playTracks(album.tracks, startIndex: i),
          onPlayNext: playNextAction(context, t),
          onEdit: editTrackAction(context, t),
        );
      },
    );

    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhoneTopLine(path: '~/albums/${pathSlug(album.name)}'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BackLink(onBack: onBack, minHeight: 44),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AlbumArt(size: 96, track: album.tracks.first),
                    const SizedBox(width: 14),
                    Expanded(child: _Info(album: album, compact: true)),
                  ],
                ),
                const SizedBox(height: 14),
                // Beside a 96px cover there is not enough width for the
                // buttons, so on a phone they move below.
                _Actions(album: album, fillWidth: true),
              ],
            ),
          ),
          const DashedRule(),
          Expanded(child: list),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: _BackLink(onBack: onBack),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            // A narrow panel (Now Playing docked on a small window) gets a
            // smaller cover rather than a squeezed title.
            final artSize = constraints.maxWidth < 560 ? 140.0 : 220.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AlbumArt(size: artSize, track: album.tracks.first),
                const SizedBox(width: 24),
                Expanded(
                  child: _Info(
                    album: album,
                    compact: false,
                    actions: _Actions(album: album),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        TrackListHeader(showArtist: mixedArtists, showAlbum: false),
        Expanded(child: list),
      ],
    );
  }
}

/// `‹ cd ..  albums`
class _BackLink extends StatelessWidget {
  final VoidCallback onBack;
  final double minHeight;

  const _BackLink({required this.onBack, this.minHeight = 0});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return Semantics(
      button: true,
      label: 'Back to albums',
      excludeSemantics: true,
      child: InkWell(
        onTap: onBack,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text.rich(
            TextSpan(
              text: '‹ cd ..  ',
              style: TextStyle(color: c.text2),
              children: [
                TextSpan(text: 'albums', style: TextStyle(color: c.textDim)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  final Album album;

  /// The two buttons split the row evenly, which is what the phone layout
  /// wants; otherwise they size to their labels.
  final bool fillWidth;

  const _Actions({required this.album, this.fillWidth = false});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerModel>();

    final play = TermButton(
      primary: true,
      glyph: const Text('▶'),
      label: 'play all',
      minHeight: fillWidth ? 44 : 0,
      onPressed: () =>
          player.playTracks(album.tracks, startIndex: 0, shuffle: false),
    );
    final shuffle = TermButton(
      glyph: const ShuffleGlyph(),
      label: 'shuffle',
      minHeight: fillWidth ? 44 : 0,
      onPressed: () => player.playTracks(album.tracks, shuffle: true),
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
    final c = TerminalColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('ALBUM', style: columnHeadingStyle(context).copyWith(
          letterSpacing: 1.3,
        )),
        SizedBox(height: compact ? 2 : 6),
        Text(
          album.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 20 : 32,
            fontWeight: FontWeight.w700,
            height: 1.15,
          ),
        ),
        SizedBox(height: compact ? 2 : 6),
        Text(
          album.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: compact ? 13 : 15, color: c.text2),
        ),
        SizedBox(height: compact ? 0 : 6),
        Text(
          _details(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: compact ? 12 : 13, color: c.textDim),
        ),
        if (actions != null) ...[
          const SizedBox(height: 16),
          actions!,
        ],
      ],
    );
  }

  /// `2024 · 4 tracks · 16:59`
  String _details() {
    final count = album.tracks.length;
    final total = album.totalDuration;
    return [
      if (album.year != null && album.year!.isNotEmpty) album.year!,
      '$count ${count == 1 ? 'track' : 'tracks'}',
      if (total > Duration.zero) formatDuration(total),
    ].join(' · ');
  }
}
