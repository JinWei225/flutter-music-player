import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_model.dart';
import '../../core/models/album.dart';
import '../../core/player/player_model.dart';
import '../theme.dart';
import '../widgets/album_art.dart';
import '../widgets/phone_header.dart';
import '../widgets/terminal_widgets.dart';

/// Widest a tile may grow before another column is added, and the spacing
/// between tiles.
const double _kMaxTileWidth = 240;
const double _kTileGap = 16;

/// A tile's border and padding on each axis.
const double _kTileInset = 2 + 16;

/// Height of everything in a tile besides its square cover: the border and
/// padding, the gap, the three text lines underneath, and a little slack.
const double _kTileChrome = _kTileInset + 8 + 19.5 * 2 + 18 + 4;

class AlbumsPage extends StatelessWidget {
  final ValueChanged<Album> onOpenAlbum;

  const AlbumsPage({super.key, required this.onOpenAlbum});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final library = context.watch<LibraryModel>();
    final current = context.watch<PlayerModel>().currentTrack;
    final albums = library.albums;
    final phone = isPhoneLayout(context);

    final grid = library.isLoading
        ? const LoadingNote()
        : albums.isEmpty
        ? Center(
            child: Text('no albums found', style: TextStyle(color: c.textDim)),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth - (phone ? 32 : 0);
              final columns = ((width + _kTileGap) /
                      (_kMaxTileWidth + _kTileGap))
                  .ceil()
                  .clamp(1, 99);
              final tile = (width - _kTileGap * (columns - 1)) / columns;
              return GridView.builder(
                padding: phone
                    ? const EdgeInsets.fromLTRB(16, 12, 16, 16)
                    : const EdgeInsets.only(bottom: 8),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: _kTileGap,
                  crossAxisSpacing: _kTileGap,
                  // The cover is square at the tile's width; the text
                  // underneath is a fixed height.
                  mainAxisExtent: tile - _kTileInset + _kTileChrome,
                ),
                itemCount: albums.length,
                itemBuilder: (context, i) => _AlbumTile(
                  album: albums[i],
                  tint: c.albumTints[i % c.albumTints.length],
                  playing: current != null && albums[i].tracks.contains(current),
                  onTap: () => onOpenAlbum(albums[i]),
                ),
              );
            },
          );

    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PhoneTopLine(path: '~/albums'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: PhoneHeading(title: 'albums', count: '${albums.length}'),
          ),
          const DashedRule(),
          Expanded(child: grid),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The page title sits in the panel border; this is the subtitle.
        Text(
          '${albums.length} albums · sorted by name',
          style: TextStyle(color: c.textDim),
        ),
        const SizedBox(height: 16),
        Expanded(child: grid),
      ],
    );
  }
}

class _AlbumTile extends StatefulWidget {
  final Album album;
  final Color tint;
  final bool playing;
  final VoidCallback onTap;

  const _AlbumTile({
    required this.album,
    required this.tint,
    required this.playing,
    required this.onTap,
  });

  @override
  State<_AlbumTile> createState() => _AlbumTileState();
}

class _AlbumTileState extends State<_AlbumTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final album = widget.album;
    final count = album.tracks.length;
    final total = album.totalDuration;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: widget.playing
                ? c.playingRow
                : _hovered
                ? c.hover
                : Colors.transparent,
            border: Border.all(
              color: widget.playing
                  ? c.accent
                  : _hovered
                  ? c.borderStrong
                  : c.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) => AlbumArt(
                  size: constraints.maxWidth,
                  tint: widget.tint,
                  track: album.tracks.first,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                album.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                album.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.textDim),
              ),
              Text(
                [
                  '$count ${count == 1 ? 'track' : 'tracks'}',
                  if (total > Duration.zero) formatDuration(total),
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: c.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
