import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/player/player_model.dart';
import '../../theme.dart';
import '../track_row.dart' show showTrackMenu, TrackAction;

/// The queue in playback order, so it reflects shuffle. Tapping a row jumps
/// to it; right-click or long-press offers "Play Next", which pulls the row
/// up behind the current track.
class QueueList extends StatelessWidget {
  /// Size to the content instead of scrolling, for use inside another scroll
  /// view.
  final bool shrinkWrap;
  final double horizontalPadding;
  final EdgeInsets padding;

  /// 44 on a phone, where each row is a tap target.
  final double rowMinHeight;

  const QueueList({
    super.key,
    this.shrinkWrap = false,
    this.horizontalPadding = 16,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
    this.rowMinHeight = 0,
  });

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerModel>();
    final tracks = player.queueInPlayOrder;
    final current = player.currentQueuePosition;

    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: padding,
      itemCount: tracks.length,
      itemBuilder: (context, i) {
        final t = tracks[i];
        return QueueRow(
          index: i,
          title: t.title,
          artist: t.artist,
          duration: t.duration,
          isCurrent: i == current,
          isPast: i < current,
          horizontalPadding: horizontalPadding,
          minHeight: rowMinHeight,
          onTap: () => player.playQueuePosition(i),
          onPlayNext: i == current ? null : () => player.playNext(t),
        );
      },
    );
  }
}

/// `01  title            3:58` over a dim artist line. The playing entry is
/// marked `▶` on the playing-row ground, like the library lists.
class QueueRow extends StatelessWidget {
  final int index;
  final String title;
  final String artist;
  final Duration? duration;
  final bool isCurrent;
  final bool isPast;
  final double horizontalPadding;
  final double minHeight;
  final VoidCallback onTap;

  /// Null for the row that is playing: it is already "next" as far as the
  /// queue is concerned, so the menu is left out.
  final VoidCallback? onPlayNext;

  const QueueRow({
    super.key,
    required this.index,
    required this.title,
    required this.artist,
    required this.duration,
    required this.isCurrent,
    required this.isPast,
    required this.onTap,
    this.onPlayNext,
    this.horizontalPadding = 16,
    this.minHeight = 0,
  });

  Future<void> _showMenu(BuildContext context, Offset at) async {
    final choice = await showTrackMenu(context, at);
    if (choice == TrackAction.playNext) onPlayNext?.call();
  }

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);

    // Already-played entries recede so the upcoming queue reads first.
    final fade = isPast ? 0.55 : 1.0;
    final titleColor = isCurrent
        ? c.accent
        : c.text.withValues(alpha: fade);
    final mutedColor = isCurrent
        ? c.accent
        : c.textDim.withValues(alpha: fade);

    return GestureDetector(
      onSecondaryTapUp: onPlayNext == null
          ? null
          : (d) => _showMenu(context, d.globalPosition),
      onLongPressStart: onPlayNext == null
          ? null
          : (d) => _showMenu(context, d.globalPosition),
      child: Material(
        color: isCurrent ? c.playingRow : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: BoxConstraints(minHeight: minHeight),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: 3,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: Text(
                    isCurrent ? '▶' : '${index + 1}'.padLeft(2, '0'),
                    style: TextStyle(
                      color: isCurrent
                          ? c.ok
                          : c.textFaint.withValues(alpha: fade),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: titleColor,
                        ),
                      ),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: mutedColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatDuration(duration),
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
