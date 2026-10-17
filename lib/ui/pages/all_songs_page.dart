import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_model.dart';
import '../../core/models/track.dart';
import '../../core/player/player_model.dart';
import '../theme.dart';
import '../widgets/edit_track_info_dialog.dart';
import '../widgets/phone_header.dart';
import '../widgets/play_next.dart';
import '../widgets/terminal_widgets.dart';
import '../widgets/track_row.dart';

class AllSongsPage extends StatelessWidget {
  const AllSongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryModel>();
    final player = context.watch<PlayerModel>();
    final tracks = library.sortedTracks;
    final current = player.currentTrack;
    final phone = isPhoneLayout(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (phone)
          _PhoneHeader(tracks: tracks)
        else ...[
          // The page title sits in the panel border, so only the toolbar
          // is left up here.
          Row(
            children: [
              // The one flex child, so the buttons give way (ellipsising
              // their labels) when Now Playing squeezes the panel, and the
              // sort control keeps the right edge.
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: tracks.isEmpty
                      ? null
                      : _PlayAllButtons(tracks: tracks),
                ),
              ),
              const SizedBox(width: 10),
              const _SortControl(),
            ],
          ),
          const SizedBox(height: 14),
          TrackListHeader(
            sortField: library.sortField,
            sortDirection: library.sortDirection,
          ),
        ],
        Expanded(
          child: library.isLoading
              ? const LoadingNote()
              : tracks.isEmpty
                  ? _EmptyState(source: library.source.description, error: library.error)
                  : ListView.builder(
                      padding: EdgeInsets.only(top: phone ? 4 : 2, bottom: 8),
                      itemCount: tracks.length,
                      itemBuilder: (context, i) {
                        final t = tracks[i];
                        return TrackRow(
                          leading: '${i + 1}',
                          title: t.title,
                          artist: t.artist,
                          album: t.album,
                          duration: t.duration,
                          isCurrent: current == t,
                          // Playing from this page queues the list exactly as
                          // it is currently sorted.
                          onPlay: () => player.playTracks(tracks, startIndex: i),
                          onPlayNext: playNextAction(context, t),
                          onEdit: editTrackAction(context, t),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/// Phone header: `mewsic ~/songs` and the sort menu on the top line, then
/// the heading, then the two play buttons splitting the width. Everything
/// must fit the screen -- an earlier version scrolled horizontally, which
/// hid the sort control entirely.
class _PhoneHeader extends StatelessWidget {
  final List<Track> tracks;

  const _PhoneHeader({required this.tracks});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PhoneTopLine(path: '~/songs', trailing: _SortControl(phone: true)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhoneHeading(title: 'all songs', count: '${tracks.length}'),
              if (tracks.isNotEmpty) ...[
                const SizedBox(height: 10),
                _PlayAllButtons(tracks: tracks, fillWidth: true),
              ],
            ],
          ),
        ),
        const DashedRule(),
      ],
    );
  }
}

class _PlayAllButtons extends StatelessWidget {
  final List<Track> tracks;

  /// When true the pair splits the row evenly, for the phone layout.
  final bool fillWidth;

  const _PlayAllButtons({required this.tracks, this.fillWidth = false});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerModel>();

    final play = TermButton(
      primary: true,
      glyph: const Text('▶'),
      label: 'play all',
      minHeight: fillWidth ? 44 : 0,
      onPressed: () =>
          player.playTracks(tracks, startIndex: 0, shuffle: false),
    );
    final shuffle = TermButton(
      glyph: const ShuffleGlyph(),
      label: 'shuffle',
      minHeight: fillWidth ? 44 : 0,
      onPressed: () => player.playTracks(tracks, shuffle: true),
    );

    if (!fillWidth) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: play),
          const SizedBox(width: 10),
          Flexible(child: shuffle),
        ],
      );
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

/// Sort field and direction in one menu: `sort: title ↑ ▾`.
///
/// They used to be two side-by-side controls, which pushed the direction
/// button off-screen on a phone. Every combination is now a single tap.
class _SortControl extends StatelessWidget {
  /// Drops the `sort:` prefix and grows to a 44px tap target.
  final bool phone;

  const _SortControl({this.phone = false});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final library = context.watch<LibraryModel>();
    final field = library.sortField;
    final direction = library.sortDirection;
    final current = '${field.label.toLowerCase()} ${sortArrow(direction)}';

    return PopupMenuButton<(SortField, SortDirection)>(
      tooltip: 'Sort: ${field.label} ${_rangeFor(direction)}',
      initialValue: (field, direction),
      onSelected: (choice) => library.setSort(choice.$1, choice.$2),
      itemBuilder: (context) => [
        for (final f in SortField.values) ...[
          if (f != SortField.values.first) const PopupMenuDivider(height: 9),
          for (final d in SortDirection.values)
            PopupMenuItem(
              value: (f, d),
              height: phone ? 44 : 32,
              child: Row(
                children: [
                  Text(sortArrow(d), style: TextStyle(color: c.textDim)),
                  const SizedBox(width: 10),
                  Text(
                    '${f.label.toLowerCase()}  '
                    '${_rangeFor(d).toLowerCase()}',
                  ),
                ],
              ),
            ),
        ],
      ],
      child: Container(
        constraints: BoxConstraints(minHeight: phone ? 44 : 0),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: phone ? 10 : 12, vertical: 6),
        decoration: BoxDecoration(border: Border.all(color: c.borderStrong)),
        child: Text.rich(
          TextSpan(
            style: TextStyle(color: c.text2),
            children: [
              if (!phone) const TextSpan(text: 'sort: '),
              TextSpan(
                text: current,
                style: phone ? null : TextStyle(color: c.accent),
              ),
              const TextSpan(text: ' ▾'),
            ],
          ),
        ),
      ),
    );
  }

  static String _rangeFor(SortDirection d) =>
      d == SortDirection.ascending ? 'A-Z' : 'Z-A';
}

class _EmptyState extends StatelessWidget {
  final String source;
  final String? error;

  const _EmptyState({required this.source, this.error});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error == null ? 'no songs found' : 'could not read your library',
            style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
          ),
          const SizedBox(height: 6),
          Text(
            error ?? 'looked in $source',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.textDim),
          ),
        ],
      ),
    );
  }
}
