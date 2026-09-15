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

  const QueueList({
    super.key,
    this.shrinkWrap = false,
    this.horizontalPadding = 16,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
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
          onTap: () => player.playQueuePosition(i),
          onPlayNext: i == current ? null : () => player.playNext(t),
        );
      },
    );
  }
}

class QueueRow extends StatelessWidget {
  final int index;
  final String title;
  final String artist;
  final Duration? duration;
  final bool isCurrent;
  final bool isPast;
  final double horizontalPadding;
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
  });

  Future<void> _showMenu(BuildContext context, Offset at) async {
    final choice = await showTrackMenu(context, at);
    if (choice == TrackAction.playNext) onPlayNext?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surfaces = AppSurfaces.of(context);

    // Already-played entries recede so the upcoming queue reads first.
    final titleColor = isCurrent
        ? scheme.primary
        : isPast
        ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
        : scheme.onSurface;
    final mutedColor = scheme.onSurfaceVariant.withValues(
      alpha: isPast ? 0.5 : 1,
    );

    return GestureDetector(
      onSecondaryTapUp: onPlayNext == null
          ? null
          : (d) => _showMenu(context, d.globalPosition),
      onLongPressStart: onPlayNext == null
          ? null
          : (d) => _showMenu(context, d.globalPosition),
      child: InkWell(
        onTap: onTap,
        hoverColor: surfaces.hover,
        child: Container(
          color: isCurrent ? scheme.primary.withValues(alpha: 0.10) : null,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 8,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: isCurrent
                    ? Icon(
                        Icons.equalizer_rounded,
                        size: 15,
                        color: scheme.primary,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(fontSize: 11, color: mutedColor),
                      ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: titleColor,
                      ),
                    ),
                    Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: mutedColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatDuration(duration),
                style: TextStyle(fontSize: 11, color: mutedColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
