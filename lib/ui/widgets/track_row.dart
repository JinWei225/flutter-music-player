import 'package:flutter/material.dart';

import '../theme.dart';

/// Width below which the album column is dropped, then the artist column.
/// Rows and their header both measure their own width against these, so the
/// two always agree without any flag being passed down.
const double kHideAlbumBelow = 640;
const double kHideArtistBelow = 460;

/// One row in a track listing. [leading] is the row's index or track number.
class TrackRow extends StatefulWidget {
  final String leading;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final bool isCurrent;
  final VoidCallback onPlay;

  final double artistWidth;
  final double albumWidth;

  const TrackRow({
    super.key,
    required this.leading,
    required this.title,
    required this.duration,
    required this.isCurrent,
    required this.onPlay,
    this.artist,
    this.album,
    this.artistWidth = 200,
    this.albumWidth = 200,
  });

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final showAlbum =
            widget.album != null && constraints.maxWidth >= kHideAlbumBelow;
        final showArtist =
            widget.artist != null && constraints.maxWidth >= kHideArtistBelow;
        // When the artist column is gone it moves under the title instead of
        // disappearing altogether.
        final artistAsSubtitle = widget.artist != null && !showArtist;

        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            // There is no selection concept in the list, so a single tap plays
            // rather than doing nothing.
            onTap: widget.onPlay,
            child: Container(
              height: artistAsSubtitle ? 58 : 44,
              color: widget.isCurrent
                  ? scheme.primary.withValues(alpha: 0.10)
                  : _hovered
                      ? surfaces.hover
                      : null,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    // Left-aligned so the play and now-playing icons line up
                    // with the track numbers instead of centring in the
                    // column. The icons are then nudged left by the blank
                    // margin inside their own glyph box (the triangle starts
                    // 8/24 of the way in, the equalizer bars 4/24), so it is
                    // the drawn shape, not the box, that meets the digits.
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _hovered
                          ? Transform.translate(
                              offset: const Offset(-18 * 8 / 24, 0),
                              child: IconButton(
                                onPressed: widget.onPlay,
                                icon: const Icon(Icons.play_arrow_rounded,
                                    size: 18),
                                color: scheme.onSurface,
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Play',
                              ),
                            )
                          : widget.isCurrent
                              ? Transform.translate(
                                  offset: const Offset(-16 * 4 / 24, 0),
                                  child: Icon(Icons.equalizer_rounded,
                                      size: 16, color: scheme.primary),
                                )
                              : Text(
                                  widget.leading,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: widget.isCurrent
                                ? scheme.primary
                                : scheme.onSurface,
                          ),
                        ),
                        if (artistAsSubtitle) ...[
                          const SizedBox(height: 3),
                          Text(
                            widget.artist!,
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
                  if (showArtist)
                    SizedBox(
                      width: widget.artistWidth,
                      child: Text(
                        widget.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  if (showAlbum)
                    SizedBox(
                      width: widget.albumWidth,
                      child: Text(
                        widget.album!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      formatDuration(widget.duration),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Column headings matching [TrackRow]'s layout, dropping the same columns at
/// the same widths.
class TrackListHeader extends StatelessWidget {
  final bool showArtist;
  final bool showAlbum;
  final double artistWidth;
  final double albumWidth;

  const TrackListHeader({
    super.key,
    this.showArtist = true,
    this.showAlbum = true,
    this.artistWidth = 200,
    this.albumWidth = 200,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: scheme.onSurfaceVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final album = showAlbum && constraints.maxWidth >= kHideAlbumBelow;
        final artist = showArtist && constraints.maxWidth >= kHideArtistBelow;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          height: 30,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outline)),
          ),
          child: Row(
            children: [
              SizedBox(width: 34, child: Text('#', style: style)),
              Expanded(child: Text('TITLE', style: style)),
              if (artist)
                SizedBox(width: artistWidth, child: Text('ARTIST', style: style)),
              if (album)
                SizedBox(width: albumWidth, child: Text('ALBUM', style: style)),
              SizedBox(
                width: 52,
                child: Text('TIME', style: style, textAlign: TextAlign.right),
              ),
            ],
          ),
        );
      },
    );
  }
}
