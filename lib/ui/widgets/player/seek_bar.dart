import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/player/player_model.dart';
import '../../theme.dart';

/// Draggable position line shared by every player surface, drawn as
/// `━━━━━───` by the theme's slider track. Dragging is tracked locally so the
/// line does not snap back to the stream's value mid-gesture.
class SeekBar extends StatefulWidget {
  /// Puts the times either side of the line (the player bar) instead of
  /// underneath it (the phone sheet).
  final bool inline;

  /// Shows the time left, `-2:16`, in place of the total.
  final bool remaining;

  const SeekBar({super.key, this.inline = false, this.remaining = false});

  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    final timeStyle = TextStyle(
      fontSize: widget.inline ? 13 : 12,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: c.textDim,
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

            // The slider has no thumb or overlay, so give it a band of
            // height to grab instead of just the 3px line.
            final slider = SizedBox(
              height: widget.inline ? 18 : 28,
              child: Slider(
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
              ),
            );

            final elapsed = Text(
              formatDuration(Duration(milliseconds: value.round())),
              style: timeStyle,
            );
            final end = Text(
              widget.remaining
                  ? '-${formatDuration(Duration(milliseconds: (totalMs - value).round()))}'
                  : formatDuration(duration),
              style: timeStyle,
            );

            if (widget.inline) {
              return Row(
                children: [
                  elapsed,
                  const SizedBox(width: 12),
                  Expanded(child: slider),
                  const SizedBox(width: 12),
                  end,
                ],
              );
            }
            return Column(
              children: [
                slider,
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [elapsed, end],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
