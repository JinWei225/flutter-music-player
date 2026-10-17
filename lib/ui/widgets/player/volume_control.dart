import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/player/player_model.dart';
import '../../theme.dart';

/// `vol ━━━━━━━━── 80%`. With [sliderWidth] unset the line takes whatever
/// width the row gives it.
class VolumeControl extends StatelessWidget {
  final double? sliderWidth;

  const VolumeControl({super.key, this.sliderWidth});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final player = context.watch<PlayerModel>();
    final v = player.volume;

    // The filled part is in the text colour, not the accent, so the volume
    // does not compete with the playback position.
    final slider = SliderTheme(
      data: SliderTheme.of(context).copyWith(activeTrackColor: c.text),
      child: SizedBox(
        height: 24,
        child: Slider(min: 0, max: 1, value: v, onChanged: player.setVolume),
      ),
    );

    return Row(
      mainAxisSize: sliderWidth == null ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Text('vol', style: TextStyle(color: c.textDim)),
        const SizedBox(width: 8),
        if (sliderWidth != null)
          SizedBox(width: sliderWidth, child: slider)
        else
          Expanded(child: slider),
        SizedBox(
          width: 44,
          child: Text(
            '${(v * 100).round()}%',
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFeatures: const [FontFeature.tabularFigures()],
              color: c.textDim,
            ),
          ),
        ),
      ],
    );
  }
}
