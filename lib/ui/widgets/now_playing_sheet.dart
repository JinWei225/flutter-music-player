import 'dart:math' as math;

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';

import '../../core/player/player_model.dart';
import '../theme.dart';
import 'album_art.dart';
import 'edit_track_info_dialog.dart';
import 'lyrics_view.dart';
import 'player/queue_list.dart';
import 'player/seek_bar.dart';
import 'player/transport_buttons.dart';
import 'player/volume_control.dart';
import 'track_row.dart' show showTrackMenu, TrackAction;

/// Full-screen player for compact layouts, where the bottom bar only has room
/// for a mini player. Carries every control the desktop player bar has:
/// seek, transport, shuffle, repeat, volume and the queue.
class NowPlayingSheet extends StatelessWidget {
  const NowPlayingSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const NowPlayingSheet(),
  );

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    final track = player.currentTrack;
    final edit = track == null ? null : editTrackAction(context, track);

    // Material rather than a decorated Container: the queue rows paint their
    // ink on the nearest Material ancestor.
    return Material(
      color: c.background,
      child: SizedBox(
        height: double.infinity,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  _BarButton(
                    tooltip: 'Close Now Playing',
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(
                      '▾',
                      style: TextStyle(fontSize: 16, color: c.text2),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '┤ now playing ├',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: c.textDim),
                    ),
                  ),
                  if (edit != null)
                    Builder(
                      builder: (context) => _BarButton(
                        tooltip: 'Track options',
                        onPressed: () async {
                          final box = context.findRenderObject() as RenderBox;
                          final choice = await showTrackMenu(
                            context,
                            box.localToGlobal(Offset(0, box.size.height)),
                            playNext: false,
                            edit: true,
                          );
                          if (choice == TrackAction.edit) edit();
                        },
                        child: Text('⋯', style: TextStyle(color: c.text2)),
                      ),
                    )
                  else
                    const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(
              child: track == null
                  ? Center(
                      child: Text(
                        'nothing playing',
                        style: TextStyle(color: c.textDim),
                      ),
                    )
                  : _Body(player: player),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 44×44 glyph button for the sheet's top bar.
class _BarButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  const _BarButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onPressed,
      child: SizedBox(width: 44, height: 44, child: Center(child: child)),
    ),
  );
}

class _Body extends StatelessWidget {
  final PlayerModel player;

  const _Body({required this.player});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final track = player.currentTrack!;
    final artSize = math.min(300.0, MediaQuery.sizeOf(context).width - 32);
    final queueLength = player.queueInPlayOrder.length;
    final repeat = switch (player.repeat) {
      RepeatMode.off => 'off',
      RepeatMode.all => 'list',
      RepeatMode.one => 'one',
    };

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AlbumArt(size: artSize, track: track)),
          const SizedBox(height: 14),
          Text(
            track.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.3,
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
            style: TextStyle(fontSize: 12, color: c.textDim),
          ),
          const SizedBox(height: 10),
          const SeekBar(remaining: true),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShuffleButton(extent: 44, glyphSize: 20),
              SkipButton.previous(
                outlined: true,
                width: 56,
                height: 52,
                fontSize: 15,
              ),
              PlayPauseButton(width: 88, height: 52, glyphSize: 17),
              SkipButton.next(
                outlined: true,
                width: 56,
                height: 52,
                fontSize: 15,
              ),
              RepeatButton(extent: 44, glyphSize: 20),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Expanded(child: VolumeControl()),
              const SizedBox(width: 16),
              Text.rich(
                TextSpan(
                  text: 'repeat ',
                  style: TextStyle(fontSize: 12, color: c.textDim),
                  children: [
                    TextSpan(
                      text: repeat,
                      style: TextStyle(
                        color: player.repeat == RepeatMode.off
                            ? c.text
                            : c.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          UpNextTabs(
            trailing: '${player.currentQueuePosition + 1}/$queueLength',
            minHeight: 44,
          ),
          const SizedBox(height: 2),
          if (context.watch<LyricsToggle>().showLyrics)
            // A box of its own inside the scrolling sheet: tall enough to
            // read along, short enough that the controls stay a flick away.
            SizedBox(
              height: math.max(320.0, MediaQuery.sizeOf(context).height * 0.5),
              child: LyricsView(track: track),
            )
          else
            // Inside a scroll view already, so the list must size to its
            // content.
            const QueueList(
              shrinkWrap: true,
              horizontalPadding: 0,
              padding: EdgeInsets.zero,
              rowMinHeight: 44,
            ),
        ],
      ),
    );
  }
}
