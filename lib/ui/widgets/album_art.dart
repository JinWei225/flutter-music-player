import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/models/track.dart';
import '../../platform/artwork_store.dart';
import '../theme.dart';

/// A track's embedded cover, square with a 1px outline, or a flat tinted
/// tile with a music note when it has none (or when no [track] is given, as
/// in an empty player bar).
class AlbumArt extends StatelessWidget {
  final double size;
  final Track? track;

  /// Placeholder colour: the tile is this at low alpha and the note is drawn
  /// in it at full strength. Defaults to the plain art-placeholder ground.
  final Color? tint;

  /// Outline colour; the panel border colour unless given.
  final Color? outline;

  const AlbumArt({
    super.key,
    required this.size,
    this.track,
    this.tint,
    this.outline,
  });

  @override
  Widget build(BuildContext context) {
    final t = track;
    final placeholder = _Placeholder(size: size, tint: tint, outline: outline);
    if (t == null) return placeholder;

    return FutureBuilder<Uint8List?>(
      future: ArtworkStore.instance.forTrack(t),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return placeholder;
        // Covers are stored at 1200px; decode at the size actually drawn so a
        // grid of tiles does not hold a grid of full-size bitmaps.
        final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
        return Container(
          width: size,
          height: size,
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: outline ?? TerminalColors.of(context).border,
            ),
          ),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: pixels > 0 ? pixels : null,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder,
          ),
        );
      },
    );
  }
}

class _Placeholder extends StatelessWidget {
  final double size;
  final Color? tint;
  final Color? outline;

  const _Placeholder({required this.size, this.tint, this.outline});

  @override
  Widget build(BuildContext context) {
    final c = TerminalColors.of(context);
    final t = tint;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t == null ? c.artPlaceholder : t.withValues(alpha: 0.14),
        border: Border.all(color: outline ?? c.border),
      ),
      // A thumbnail is too small for the note to read; it stays a plain tile.
      child: size < 48
          ? null
          : Icon(
              Icons.music_note_outlined,
              size: (size * 0.16).clamp(20.0, 48.0),
              color: t ?? c.textDim,
            ),
    );
  }
}
