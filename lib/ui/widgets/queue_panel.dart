import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/player/player_model.dart';
import '../theme.dart';

/// Slide-in panel listing the queue in playback order, so it reflects shuffle.
class QueuePanel extends StatelessWidget {
  final VoidCallback onClose;

  const QueuePanel({super.key, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final tracks = player.queueInPlayOrder;
    final current = player.currentQueuePosition;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(left: BorderSide(color: scheme.outline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Text(
                  'Queue',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                if (tracks.isNotEmpty)
                  Text(
                    '${tracks.length} songs',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Hide queue',
                  color: scheme.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outline),
          Expanded(
            child: tracks.isEmpty
                ? Center(
                    child: Text(
                      'The queue is empty.',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: tracks.length,
                    itemBuilder: (context, i) {
                      final t = tracks[i];
                      final isCurrent = i == current;
                      final isPast = i < current;
                      return _QueueRow(
                        index: i,
                        title: t.title,
                        artist: t.artist,
                        duration: t.duration,
                        isCurrent: isCurrent,
                        isPast: isPast,
                        onTap: () => player.playQueuePosition(i),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  final int index;
  final String title;
  final String artist;
  final Duration? duration;
  final bool isCurrent;
  final bool isPast;
  final VoidCallback onTap;

  const _QueueRow({
    required this.index,
    required this.title,
    required this.artist,
    required this.duration,
    required this.isCurrent,
    required this.isPast,
    required this.onTap,
  });

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

    return InkWell(
      onTap: onTap,
      hoverColor: surfaces.hover,
      child: Container(
        color: isCurrent ? scheme.primary.withValues(alpha: 0.10) : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: isCurrent
                  ? Icon(Icons.equalizer_rounded,
                      size: 15, color: scheme.primary)
                  : Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant
                            .withValues(alpha: isPast ? 0.5 : 1),
                      ),
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
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
                      color: titleColor,
                    ),
                  ),
                  Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant
                          .withValues(alpha: isPast ? 0.5 : 1),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatDuration(duration),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant
                    .withValues(alpha: isPast ? 0.5 : 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
