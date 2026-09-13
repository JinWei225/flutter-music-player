import 'dart:io';
import 'dart:typed_data';

import 'package:mewsic_tagfix/mewsic_tagfix.dart';

import '../core/models/track.dart';

/// Embedded cover art for the UI, read once per album and kept in memory.
///
/// Keyed by album rather than track: every track of an album carries the
/// same cover, and the Albums grid asks for dozens at once. A null entry
/// records "looked, found nothing" so a bare file is not re-read on every
/// scroll. Cleared on each library load so covers added to the files while
/// the app was running (by `mewsic-tagfix`) show up after a rescan.
class ArtworkStore {
  static final instance = ArtworkStore();

  /// Enough for a screenful of album tiles plus what is playing; older
  /// entries are dropped first.
  static const _maxEntries = 96;

  final _byAlbum = <String, Future<Uint8List?>>{};

  Future<Uint8List?> forTrack(Track track) {
    final key = track.albumKey;
    final cached = _byAlbum.remove(key);
    if (cached != null) {
      _byAlbum[key] = cached; // most recently used goes last
      return cached;
    }
    final future = _read(track);
    _byAlbum[key] = future;
    if (_byAlbum.length > _maxEntries) _byAlbum.remove(_byAlbum.keys.first);
    return future;
  }

  void clear() => _byAlbum.clear();

  static Future<Uint8List?> _read(Track track) async {
    final path = track.filePath;
    if (path == null) return null;
    final bytes = await TagReader.readArtwork(File(path));
    return bytes == null || bytes.isEmpty ? null : bytes;
  }
}
