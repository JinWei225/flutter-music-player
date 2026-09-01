import 'package:flutter/material.dart';

/// Placeholder artwork. None of the store-bought files carry embedded art, so
/// every album and track shows the same neutral music-note tile.
class AlbumArt extends StatelessWidget {
  final double size;
  final double radius;

  const AlbumArt({super.key, required this.size, this.radius = 6});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outline, width: 1),
      ),
      child: Icon(
        Icons.music_note_rounded,
        size: size * 0.38,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
    );
  }
}
