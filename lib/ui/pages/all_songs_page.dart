import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/library/library_model.dart';
import '../../core/models/track.dart';
import '../../core/player/player_model.dart';
import '../breakpoints.dart';
import '../theme.dart';
import '../widgets/edit_track_info_dialog.dart';
import '../widgets/play_next.dart';
import '../widgets/track_row.dart';

class AllSongsPage extends StatelessWidget {
  const AllSongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryModel>();
    final player = context.watch<PlayerModel>();
    final tracks = library.sortedTracks;
    final current = player.currentTrack;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(tracks: tracks),
        const TrackListHeader(),
        Expanded(
          child: library.isLoading
              ? const Center(child: CircularProgressIndicator())
              : tracks.isEmpty
                  ? _EmptyState(source: library.source.description, error: library.error)
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 12),
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

/// Page header.
///
/// On a phone the sort menu sits beside the title, where there is room, and
/// the two play buttons take the full width on their own row. Everything must
/// fit the screen -- an earlier version scrolled horizontally, which hid the
/// sort control entirely.
class _Header extends StatelessWidget {
  final List<Track> tracks;

  const _Header({required this.tracks});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = context.watch<ThemeController>();

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        // The sidebar carries the theme toggle everywhere but on a phone, so
        // only put it in the header when there is no sidebar.
        final showThemeToggle =
            MediaQuery.sizeOf(context).width < kCompactBreakpoint;

        final heading = Text(
          'All Songs',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 21 : 24,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        );

        if (compact) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Sort sits up here where there is slack; giving it a share of
                // the button row below squeezed both labels onto two lines.
                Row(
                  children: [
                    // Expanded, not Flexible-plus-Spacer: those two compete
                    // for the same free space and the heading ends up with
                    // only half of it, truncating to "All S...".
                    Expanded(child: heading),
                    const _SortControl(),
                    if (showThemeToggle)
                      IconButton(
                        onPressed: theme.toggle,
                        icon: Icon(
                          theme.isDark
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          size: 20,
                        ),
                        color: scheme.onSurfaceVariant,
                        tooltip: theme.isDark ? 'Light mode' : 'Dark mode',
                      ),
                  ],
                ),
                if (tracks.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _PlayAllButtons(tracks: tracks, fillWidth: true),
                  ),
                ],
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
          child: Row(
            children: [
              // The one flex widget in the row, so it reliably claims exactly
              // the space the trailing controls don't need -- pairing a
              // Flexible heading directly with a Spacer split that space
              // between them instead, based on how much room each was
              // handed rather than how much the heading actually used, which
              // left the controls stranded well short of the right edge
              // whenever the heading text was short.
              Expanded(
                child: Row(
                  children: [
                    // Flexible so the heading yields to the controls, not
                    // the other way round, when the body is only just wide
                    // enough.
                    Flexible(child: heading),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        '${tracks.length} songs',
                        style:
                            TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              if (tracks.isNotEmpty) ...[
                _PlayAllButtons(tracks: tracks),
                const SizedBox(width: 12),
              ],
              const _SortControl(),
            ],
          ),
        );
      },
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
    final scheme = Theme.of(context).colorScheme;

    final play = FilledButton.icon(
      onPressed: () =>
          player.playTracks(tracks, startIndex: 0, shuffle: false),
      icon: const Icon(Icons.play_arrow_rounded, size: 18),
      label: const Text('Play All', maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        visualDensity: fillWidth ? null : VisualDensity.compact,
        padding: EdgeInsets.symmetric(
            horizontal: 14, vertical: fillWidth ? 12 : 0),
      ),
    );

    final shuffle = OutlinedButton.icon(
      onPressed: () => player.playTracks(tracks, shuffle: true),
      icon: const Icon(Icons.shuffle_rounded, size: 16),
      label: const Text('Shuffle', maxLines: 1, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        visualDensity: fillWidth ? null : VisualDensity.compact,
        padding: EdgeInsets.symmetric(
            horizontal: 14, vertical: fillWidth ? 12 : 0),
        foregroundColor: scheme.onSurface,
        side: BorderSide(color: scheme.outline),
      ),
    );

    if (!fillWidth) {
      return Row(children: [play, const SizedBox(width: 8), shuffle]);
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

/// Sort field + direction. Picking the active field again flips the direction.
/// Sort field and direction in one menu.
///
/// They used to be two side-by-side controls, which pushed the direction
/// button off-screen on a phone. Every combination is now a single tap.
class _SortControl extends StatelessWidget {
  const _SortControl();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final library = context.watch<LibraryModel>();
    final field = library.sortField;
    final direction = library.sortDirection;

    return PopupMenuButton<(SortField, SortDirection)>(
      tooltip: 'Sort: ${field.label} ${_rangeFor(direction)}',
      initialValue: (field, direction),
      onSelected: (choice) => library.setSort(choice.$1, choice.$2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outline),
      ),
      itemBuilder: (context) => [
        for (final f in SortField.values) ...[
          if (f != SortField.values.first) const PopupMenuDivider(),
          for (final d in SortDirection.values)
            PopupMenuItem(
              value: (f, d),
              child: Row(
                children: [
                  Icon(_arrowFor(d), size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Text('${f.label}  ${_rangeFor(d)}'),
                ],
              ),
            ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_arrowFor(direction), size: 15, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              field.label,
              style: TextStyle(fontSize: 12.5, color: scheme.onSurface),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded,
                size: 16, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  static IconData _arrowFor(SortDirection d) => d == SortDirection.ascending
      ? Icons.arrow_upward_rounded
      : Icons.arrow_downward_rounded;

  static String _rangeFor(SortDirection d) =>
      d == SortDirection.ascending ? 'A-Z' : 'Z-A';
}

class _EmptyState extends StatelessWidget {
  final String source;
  final String? error;

  const _EmptyState({required this.source, this.error});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.library_music_outlined,
              size: 44, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            error == null ? 'No songs found' : 'Could not read your library',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            error ?? 'Looked in $source',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
