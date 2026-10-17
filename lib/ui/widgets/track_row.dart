import 'package:flutter/material.dart';

import '../../core/library/library_model.dart';
import '../theme.dart';
import 'phone_header.dart';
import 'terminal_widgets.dart';

/// Width below which the album column is dropped, then the artist column.
/// Rows and their header both measure their own width against these, so the
/// two always agree without any flag being passed down. Below
/// [kHideArtistBelow] a row switches to the two-line phone layout.
const double kHideAlbumBelow = 640;
const double kHideArtistBelow = 460;

/// Relative widths of the text columns (2fr / 1.4fr / 1.4fr). They are flex
/// factors, not pixels, so title/artist/album keep the same proportions to
/// one another no matter how wide the window gets.
const int kTitleFlex = 20;
const int kArtistFlex = 14;
const int kAlbumFlex = 14;

/// Fixed columns either side of the text ones, and the gap between columns.
const double kNumberWidth = 40;
const double kTimeWidth = 56;
const double kActionsWidth = 32;
const double kColumnGap = 12;

/// Padding shared by [TrackRow] and [TrackListHeader] in the table layout.
const EdgeInsets kRowPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 4);

/// `↑` / `↓` for a sort direction, as shown in the sort button and the
/// column heading.
String sortArrow(SortDirection d) => d == SortDirection.ascending ? '↑' : '↓';

/// One row in a track listing. [leading] is the row's index or track number.
///
/// When [onPlayNext] or [onEdit] is given the row grows a menu -- reached by
/// right-click, a long press, or the `⋯` button that appears on hover --
/// with an entry for each: queue the track to play next, or open its tags
/// for editing.
class TrackRow extends StatefulWidget {
  final String leading;
  final String title;
  final String? artist;
  final String? album;
  final Duration? duration;
  final bool isCurrent;
  final VoidCallback onPlay;
  final VoidCallback? onPlayNext;
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
    this.onPlayNext,
    this.onEdit,
  });

  bool get hasMenu => onPlayNext != null || onEdit != null;

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  bool _hovered = false;

  /// Pops the row menu at [at] (global).
  Future<void> _showMenu(Offset at) async {
    final choice = await showTrackMenu(
      context,
      at,
      playNext: widget.onPlayNext != null,
      edit: widget.onEdit != null,
    );
    switch (choice) {
      case TrackAction.playNext:
        widget.onPlayNext?.call();
      case TrackAction.edit:
        widget.onEdit?.call();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final phone = constraints.maxWidth < kHideArtistBelow;
        final showAlbum =
            widget.album != null && constraints.maxWidth >= kHideAlbumBelow;
        final showArtist = widget.artist != null && !phone;
        // Columns that do not fit move under the title instead of
        // disappearing altogether: "artist · album" on a phone.
        final subtitle = [
          if (widget.artist != null && !showArtist) widget.artist!,
          if (widget.album != null && !showAlbum) widget.album!,
        ].join(' · ');

        final current = widget.isCurrent;
        final fg = current ? c.accent : c.text;
        final dim = current ? c.accent : c.textDim;

        final marker = current
            ? Text('▶', style: TextStyle(color: c.ok))
            : _hovered
            ? Tooltip(
                message: 'Play',
                child: Text('▶', style: TextStyle(color: c.text2)),
              )
            : Text(
                widget.leading.padLeft(2, '0'),
                style: TextStyle(color: c.textFaint),
              );

        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: current ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: dim),
              ),
          ],
        );

        final time = Text(
          formatDuration(widget.duration),
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: phone ? 12 : 13,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: dim,
          ),
        );

        final Widget row;
        if (phone) {
          row = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            child: Row(
              children: [
                SizedBox(width: 28, child: marker),
                const SizedBox(width: 10),
                Expanded(child: title),
                const SizedBox(width: 10),
                time,
              ],
            ),
          );
        } else {
          Widget column(String text, int flex) => Expanded(
            flex: flex,
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: dim),
            ),
          );
          row = Padding(
            padding: kRowPadding,
            child: Row(
              children: [
                SizedBox(width: kNumberWidth, child: marker),
                const SizedBox(width: kColumnGap),
                Expanded(flex: kTitleFlex, child: title),
                if (showArtist) ...[
                  const SizedBox(width: kColumnGap),
                  column(widget.artist!, kArtistFlex),
                ],
                if (showAlbum) ...[
                  const SizedBox(width: kColumnGap),
                  column(widget.album!, kAlbumFlex),
                ],
                const SizedBox(width: kColumnGap),
                SizedBox(width: kTimeWidth, child: time),
                const SizedBox(width: kColumnGap),
                SizedBox(
                  width: kActionsWidth,
                  child: _hovered && widget.hasMenu
                      ? Center(child: _MoreButton(onShowMenu: _showMenu))
                      : null,
                ),
              ],
            ),
          );
        }

        return MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            // There is no selection concept in the list, so a single tap plays
            // rather than doing nothing.
            onTap: widget.onPlay,
            onSecondaryTapUp: widget.hasMenu
                ? (d) => _showMenu(d.globalPosition)
                : null,
            onLongPressStart: widget.hasMenu
                ? (d) => _showMenu(d.globalPosition)
                : null,
            // Opaque so the gaps between columns and the padding count as the
            // row, not just the text.
            behavior: HitTestBehavior.opaque,
            child: ColoredBox(
              color: current
                  ? c.playingRow
                  : _hovered
                  ? c.hover
                  : Colors.transparent,
              child: row,
            ),
          ),
        );
      },
    );
  }
}

/// The outlined `⋯` that opens a row's menu, shown while the row is hovered.
class _MoreButton extends StatelessWidget {
  final ValueChanged<Offset> onShowMenu;

  const _MoreButton({required this.onShowMenu});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return Tooltip(
      message: 'More',
      child: Material(
        type: MaterialType.transparency,
        shape: RoundedRectangleBorder(side: BorderSide(color: c.borderStrong)),
        child: InkWell(
          onTap: () {
            final box = context.findRenderObject() as RenderBox;
            onShowMenu(box.localToGlobal(Offset(0, box.size.height)));
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('⋯', style: TextStyle(color: c.text, height: 1.4)),
          ),
        ),
      ),
    );
  }
}

enum TrackAction { playNext, edit }

/// The context menu shared by the library rows and the queue rows, popped at
/// [at] (global). Only the actions asked for are listed; the result is null
/// when the menu is dismissed.
Future<TrackAction?> showTrackMenu(
  BuildContext context,
  Offset at, {
  bool playNext = true,
  bool edit = false,
}) {
  final c = TerminalColors.of(context);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final height = isPhoneLayout(context) ? 44.0 : 32.0;

  // ↳ and ✎ are missing from JetBrains Mono, so square icons stand in.
  PopupMenuItem<TrackAction> item(
    TrackAction value,
    IconData icon,
    String label,
  ) => PopupMenuItem(
    value: value,
    height: height,
    child: Row(
      children: [
        Icon(icon, size: 15, color: c.textDim),
        const SizedBox(width: 10),
        Text(label),
      ],
    ),
  );

  return showMenu<TrackAction>(
    context: context,
    position: RelativeRect.fromRect(
      at & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    constraints: const BoxConstraints(minWidth: 200),
    items: [
      if (playNext)
        item(
          TrackAction.playNext,
          Icons.subdirectory_arrow_right_sharp,
          'play next',
        ),
      if (edit) item(TrackAction.edit, Icons.edit_sharp, 'edit info…'),
    ],
  );
}

/// Column headings matching [TrackRow]'s table layout, dropping the same
/// columns at the same widths, over a dashed rule. When [sortField] is given
/// that column carries the sort arrow: `TITLE ↑`.
class TrackListHeader extends StatelessWidget {
  final bool showArtist;
  final bool showAlbum;
  final SortField? sortField;
  final SortDirection sortDirection;

  const TrackListHeader({
    super.key,
    this.showArtist = true,
    this.showAlbum = true,
    this.sortField,
    this.sortDirection = SortDirection.ascending,
  });

  @override
  Widget build(BuildContext context) {
    final style = columnHeadingStyle(context);
    String heading(String name, SortField field) => sortField == field
        ? '$name ${sortArrow(sortDirection)}'
        : name;

    return LayoutBuilder(
      builder: (context, constraints) {
        final album = showAlbum && constraints.maxWidth >= kHideAlbumBelow;
        final artist = showArtist && constraints.maxWidth >= kHideArtistBelow;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: kRowPadding,
              child: DefaultTextStyle.merge(
                style: style,
                child: Row(
                  children: [
                    const SizedBox(width: kNumberWidth, child: Text('#')),
                    const SizedBox(width: kColumnGap),
                    Expanded(
                      flex: kTitleFlex,
                      child: Text(heading('TITLE', SortField.title)),
                    ),
                    if (artist) ...[
                      const SizedBox(width: kColumnGap),
                      Expanded(
                        flex: kArtistFlex,
                        child: Text(heading('ARTIST', SortField.artist)),
                      ),
                    ],
                    if (album) ...[
                      const SizedBox(width: kColumnGap),
                      Expanded(
                        flex: kAlbumFlex,
                        child: Text(heading('ALBUM', SortField.album)),
                      ),
                    ],
                    const SizedBox(width: kColumnGap),
                    const SizedBox(
                      width: kTimeWidth,
                      child: Text('TIME', textAlign: TextAlign.right),
                    ),
                    const SizedBox(width: kColumnGap + kActionsWidth),
                  ],
                ),
              ),
            ),
            const DashedRule(),
          ],
        );
      },
    );
  }
}
