import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/player/player_model.dart';

/// Speaker icon, slider and percentage. With [sliderWidth] unset the slider
/// takes whatever width the row gives it.
class VolumeControl extends StatelessWidget {
  final double? sliderWidth;
  final bool dense;

  const VolumeControl({super.key, this.sliderWidth, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final player = context.watch<PlayerModel>();
    final v = player.volume;

    final icon = v == 0
        ? Icons.volume_off_rounded
        : v < 0.5
        ? Icons.volume_down_rounded
        : Icons.volume_up_rounded;

    Widget slider = Slider(
      min: 0,
      max: 1,
      value: v,
      onChanged: player.setVolume,
    );
    if (dense) {
      slider = SliderTheme(
        data: SliderTheme.of(context).copyWith(
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
          trackHeight: 3,
        ),
        child: slider,
      );
    }

    return Row(
      children: [
        Icon(icon, size: dense ? 18 : 20, color: scheme.onSurfaceVariant),
        if (sliderWidth != null)
          SizedBox(width: sliderWidth, child: slider)
        else
          Expanded(child: slider),
        SizedBox(
          width: 32,
          child: Text(
            '${(v * 100).round()}',
            textAlign: dense ? TextAlign.left : TextAlign.right,
            style: TextStyle(
              fontSize: dense ? 11 : 12,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
