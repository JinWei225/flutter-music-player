import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../platform/artwork_store.dart';

/// A track's embedded cover, or a neutral music-note tile when it has none
/// (or when no [track] is given, as in an empty player bar).
class AlbumArt extends StatelessWidget {
  final double size;
  final double radius;
  final Track? track;

  const AlbumArt({super.key, required this.size, this.radius = 6, this.track});

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return _Placeholder(size: size, radius: radius);

    return FutureBuilder<Uint8List?>(
      future: ArtworkStore.instance.forTrack(t),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return _Placeholder(size: size, radius: radius);
        // Covers are stored at 1200px; decode at the size actually drawn so a
        // grid of tiles does not hold a grid of full-size bitmaps.
        final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: pixels > 0 ? pixels : null,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _Placeholder(size: size, radius: radius),
          ),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  final double size;
  final double radius;

  const _Placeholder({required this.size, required this.radius});

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
