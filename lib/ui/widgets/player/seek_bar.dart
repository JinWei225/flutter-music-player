import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/player/player_model.dart';
import '../../theme.dart';

/// Draggable position bar shared by every player surface. Dragging is tracked
/// locally so the thumb does not snap back to the stream's value mid-gesture.
class SeekBar extends StatefulWidget {
  /// Puts the times either side of the slider (the player bar) instead of
  /// underneath it (the phone sheet and the Now Playing panel).
  final bool inline;

  /// Thin track and small thumb, for surfaces where the bar is not the main
  /// control.
  final bool dense;

  const SeekBar({super.key, this.inline = false, this.dense = false});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final timeStyle = TextStyle(
      fontSize: widget.dense ? 11 : 12,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: scheme.onSurfaceVariant,
    );

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      builder: (context, positionSnap) {
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          builder: (context, durationSnap) {
            final duration =
                durationSnap.data ??
                player.currentTrack?.duration ??
                Duration.zero;
            final totalMs = duration.inMilliseconds.toDouble();
            final positionMs =
                positionSnap.data?.inMilliseconds.toDouble() ?? 0;
            final value = _dragValue ?? positionMs.clamp(0, totalMs);

            Widget slider = Slider(
              min: 0,
              max: totalMs > 0 ? totalMs : 1,
              value: totalMs > 0 ? value.clamp(0, totalMs) : 0,
              onChanged: totalMs > 0
                  ? (v) => setState(() => _dragValue = v)
                  : null,
              onChangeEnd: (v) {
                player.seek(Duration(milliseconds: v.round()));
                setState(() => _dragValue = null);
              },
            );
            if (widget.dense) {
              slider = SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  trackHeight: 3,
                ),
                child: slider,
              );
            }

            final elapsed = Text(
              formatDuration(Duration(milliseconds: value.round())),
              textAlign: widget.inline ? TextAlign.right : null,
              style: timeStyle,
            );
            final total = Text(formatDuration(duration), style: timeStyle);

            if (widget.inline) {
              return Row(
                children: [
                  SizedBox(width: 44, child: elapsed),
                  Expanded(child: slider),
                  SizedBox(width: 44, child: total),
                ],
              );
            }
            return Column(
              children: [
                slider,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [elapsed, total],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
