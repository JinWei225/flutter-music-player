import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/track.dart';
import '../../core/player/player_model.dart';
import '../theme.dart';
import 'album_art.dart';
import 'lyrics_view.dart';
import 'player/queue_list.dart';
import 'terminal_panel.dart';

/// Now Playing for wide layouts, boxed as `┤ now playing ├` with a `×` on
/// its border: the current track's art and tags on top, the queue in
/// playback order underneath. Docked beside the library on desktop; slid
/// over it on a tablet held upright. Transport lives in the player bar,
/// which is always visible alongside, so it is not repeated here.
class NowPlayingPanel extends StatelessWidget {
  final double width;
  final VoidCallback onClose;

  const NowPlayingPanel({
    super.key,
    required this.width,
    required this.onClose,
  });

  static const _padding = EdgeInsets.fromLTRB(16, 11, 16, 8);

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    final track = player.currentTrack;
    final tracks = player.queueInPlayOrder;
    final position = player.currentQueuePosition;
    final inner = width - 2 - _padding.horizontal;
    final tabs = Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: UpNextTabs(trailing: '${position + 1}/${tracks.length}'),
    );

    return SizedBox(
      width: width,
      child: TerminalPanel(
        title: 'now playing',
        padding: _padding,
        trailing: _CloseButton(onClose: onClose),
        // Material so the queue rows have something to paint their ink on.
        child: Material(
          type: MaterialType.transparency,
          child: track == null
              ? Center(
                  child: Text(
                    'nothing playing',
                    style: TextStyle(color: c.textDim),
                  ),
                )
              : context.watch<LyricsToggle>().showLyrics
              ? _WithLyrics(
                  hero: _Hero(track: track, artSize: inner),
                  heroHeight: inner,
                  tabs: tabs,
                  lyrics: LyricsView(track: track),
                )
              // One list so the art scrolls away under a long queue rather
              // than pinning the queue into a short strip.
              : ListView.builder(
                  itemCount: tracks.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) return _Hero(track: track, artSize: inner);
                    if (i == 1) return tabs;
                    final index = i - 2;
                    final t = tracks[index];
                    return QueueRow(
                      index: index,
                      title: t.title,
                      artist: t.artist,
                      duration: t.duration,
                      isCurrent: index == position,
                      isPast: index < position,
                      horizontalPadding: 0,
                      onTap: () => player.playQueuePosition(index),
                      onPlayNext: index == position
                          ? null
                          : () => player.playNext(t),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// The cover and names with the lyrics below. The lyrics take whatever
/// height is left, so the line being sung stays in view without the panel
/// itself scrolling. In a window too short for that, everything scrolls as
/// one list again and the lyrics get a box of their own height.
class _WithLyrics extends StatelessWidget {
  final Widget hero;
  final Widget tabs;
  final Widget lyrics;

  /// The cover's side; the names and tabs below it add [_belowArt] at most.
  final double heroHeight;

  const _WithLyrics({
    required this.hero,
    required this.heroHeight,
    required this.tabs,
    required this.lyrics,
  });

  /// Names (a two-line title at most) plus the tabs.
  static const _belowArt = 140.0;
  static const _minLyrics = 200.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxHeight - heroHeight - _belowArt >= _minLyrics) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [hero, tabs, Expanded(child: lyrics)],
          );
        }
        return ListView(
          children: [
            hero,
            tabs,
            SizedBox(height: 300, child: lyrics),
          ],
        );
      },
    );
  }
}

/// The `×` set into the panel's top border.
class _CloseButton extends StatelessWidget {
  final VoidCallback onClose;

  const _CloseButton({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Hide Now Playing',
      child: InkWell(
        onTap: onClose,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '×',
            style: TextStyle(
              fontSize: 14,
              height: 1.2,
              color: TerminalColors.of(context).textDim,
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final Track track;
  final double artSize;

  const _Hero({required this.track, required this.artSize});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AlbumArt(size: artSize, track: track),
        const SizedBox(height: 14),
        Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.text2),
        ),
        Text(
          track.album,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: c.textDim),
        ),
      ],
    );
  }
}
