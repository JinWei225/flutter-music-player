import 'package:flutter/material.dart';

import '../theme.dart';

/// Width below which the album column is dropped, then the artist column.
/// Rows and their header both measure their own width against these, so the
/// two always agree without any flag being passed down.
const double kHideAlbumBelow = 640;
const double kHideArtistBelow = 460;

/// Relative widths of the text columns. They are flex factors, not pixels, so
/// title/artist/album keep the same proportions to one another no matter how
/// wide the window gets -- a fixed pixel width for artist/album left title to
/// soak up every extra pixel on a maximized window, stretching it far past
/// its text while the other columns stayed pinned together on the right.
const int kTitleFlex = 5;
const int kArtistFlex = 3;
const int kAlbumFlex = 3;

/// Horizontal gap between adjacent text columns.
const double kColumnGap = 24;

/// Padding shared by [TrackRow] and [TrackListHeader]. The trailing edge gets
/// much more than the leading one -- at 16 either side the TIME column sat
/// right on the window edge, which read as clipped rather than intentional.
const EdgeInsets kRowPadding = EdgeInsets.fromLTRB(16, 0, 48, 0);

/// One row in a track listing. [leading] is the row's index or track number.
///
/// When [onEdit] is given the row grows a menu -- reached by right-click, a
/// long press, or the "more" button that appears on hover -- whose one entry
/// opens the track's tags for editing.
class TrackRow extends StatefulWidget {
  final String leading;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final bool isCurrent;
  final VoidCallback onPlay;
  final VoidCallback? onEdit;

  const TrackRow({
    super.key,
    required this.leading,
    required this.title,
    required this.duration,
    required this.isCurrent,
    required this.onPlay,
    this.artist,
    this.album,
    this.onEdit,
  });

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  bool _hovered = false;

  /// Pops the row menu at [at] (global). One item for now; a place for
  /// "Add to queue" and friends later.
  Future<void> _showMenu(Offset at) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final choice = await showMenu<_RowAction>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(
          value: _RowAction.edit,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined, size: 18),
            title: Text('Edit Info…'),
          ),
        ),
      ],
    );
    if (choice == _RowAction.edit) widget.onEdit?.call();
  }

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
        // Columns that do not fit move under the title instead of
        // disappearing altogether: "artist · album" on a phone.
        final subtitle = [
          if (widget.artist != null && !showArtist) widget.artist!,
          if (widget.album != null && !showAlbum) widget.album!,
        ].join('  ·  ');
        final hasSubtitle = subtitle.isNotEmpty;

        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            // There is no selection concept in the list, so a single tap plays
            // rather than doing nothing.
            onTap: widget.onPlay,
            onSecondaryTapUp: widget.onEdit == null
                ? null
                : (d) => _showMenu(d.globalPosition),
            onLongPressStart: widget.onEdit == null
                ? null
                : (d) => _showMenu(d.globalPosition),
            // Opaque so the gaps between columns and the padding count as the
            // row. The container below only paints (and so only hit-tests)
            // when hovered or current, which a finger never is.
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                _buildRow(
                  context,
                  scheme,
                  surfaces,
                  hasSubtitle,
                  subtitle,
                  showArtist,
                  showAlbum,
                ),
                // Sits in the row's trailing padding, so the columns keep
                // their alignment with the header whether or not it shows.
                if (_hovered && widget.onEdit != null)
                  Positioned(
                    right: 10,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Builder(
                        builder: (context) => IconButton(
                          onPressed: () {
                            final box = context.findRenderObject() as RenderBox;
                            _showMenu(
                              box.localToGlobal(Offset(0, box.size.height)),
                            );
                          },
                          icon: const Icon(Icons.more_horiz_rounded, size: 18),
                          color: scheme.onSurfaceVariant,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          tooltip: 'More',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(
    BuildContext context,
    ColorScheme scheme,
    AppSurfaces surfaces,
    bool hasSubtitle,
    String subtitle,
    bool showArtist,
    bool showAlbum,
  ) {
    return Container(
      height: hasSubtitle ? 58 : 44,
      color: widget.isCurrent
          ? scheme.primary.withValues(alpha: 0.10)
          : _hovered
          ? surfaces.hover
          : null,
      padding: kRowPadding,
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
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
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
                      child: Icon(
                        Icons.equalizer_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                    )
                  : Text(
                      widget.leading,
                      style: TextStyle(
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
            ),
          ),
          Expanded(
            flex: kTitleFlex,
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
                    color: widget.isCurrent ? scheme.primary : scheme.onSurface,
                  ),
                ),
                if (hasSubtitle) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
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
          if (showArtist) ...[
            const SizedBox(width: kColumnGap),
            Expanded(
              flex: kArtistFlex,
              child: Text(
                widget.artist!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          if (showAlbum) ...[
            const SizedBox(width: kColumnGap),
            Expanded(
              flex: kAlbumFlex,
              child: Text(
                widget.album!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(width: kColumnGap),
          SizedBox(
            width: 52,
            child: Text(
              formatDuration(widget.duration),
              style: TextStyle(
                fontSize: 12,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _RowAction { edit }

/// Column headings matching [TrackRow]'s layout, dropping the same columns at
/// the same widths.
class TrackListHeader extends StatelessWidget {
  final bool showArtist;
  final bool showAlbum;

  const TrackListHeader({
    super.key,
    this.showArtist = true,
    this.showAlbum = true,
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
          padding: kRowPadding,
          height: 30,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outline)),
          ),
          child: Row(
            children: [
              SizedBox(width: 34, child: Text('#', style: style)),
              Expanded(
                flex: kTitleFlex,
                child: Text('TITLE', style: style),
              ),
              if (artist) ...[
                const SizedBox(width: kColumnGap),
                Expanded(
                  flex: kArtistFlex,
                  child: Text('ARTIST', style: style),
                ),
              ],
              if (album) ...[
                const SizedBox(width: kColumnGap),
                Expanded(
                  flex: kAlbumFlex,
                  child: Text('ALBUM', style: style),
                ),
              ],
              const SizedBox(width: kColumnGap),
              SizedBox(width: 52, child: Text('TIME', style: style)),
            ],
          ),
        );
      },
    );
  }
}
