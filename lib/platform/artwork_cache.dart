import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../core/metadata/tag_reader.dart';
import '../core/models/track.dart';

/// Resolves a track to an image the media session can display.
///
/// The notification's large icon needs a URI, not bytes, so embedded artwork is
/// written to the cache directory once per album and reused. Tracks with no
/// artwork fall back to a neutral cover tile -- without it the session reuses
/// the app icon, which then appears twice in the same notification.
class ArtworkCache {
  static const _placeholderAsset = 'assets/album_placeholder.png';

  /// Keyed by album so the file is written once for a whole album, not per
  /// track. A null value records "already looked, found nothing".
  final Map<String, Uri?> _byAlbum = {};

  Directory? _dir;
  Uri? _placeholder;

  Future<Directory> _cacheDir() async =>
      _dir ??= Directory(
        '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}artwork',
      )..createSync(recursive: true);

  /// Artwork for [track], or the fallback tile. Never null, so the session
  /// always has something better than the app icon to show.
  Future<Uri> uriFor(Track track) async =>
      await embeddedUriFor(track) ?? await placeholder();

  /// The track's real cover, or null when it has none.
  Future<Uri?> embeddedUriFor(Track track) async {
    final key = track.albumKey;
    if (_byAlbum.containsKey(key)) return _byAlbum[key];

    Uri? result;
    try {
      // Only a real file can be parsed; a content:// source is read through
      // the path the platform reported alongside it, when there was one.
      final path = track.filePath;
      if (path != null) {
        final bytes = await TagReader.readArtwork(File(path));
        if (bytes != null && bytes.isNotEmpty) {
          final dir = await _cacheDir();
          final file = File(
            '${dir.path}${Platform.pathSeparator}${key.hashCode}.img',
          );
          await file.writeAsBytes(bytes, flush: true);
          result = file.uri;
        }
      }
    } catch (e) {
      debugPrint('Could not read artwork for ${track.title}: $e');
    }

    _byAlbum[key] = result;
    return result;
  }

  /// The shared fallback tile, unpacked from assets on first use.
  Future<Uri> placeholder() async {
    final existing = _placeholder;
    if (existing != null) return existing;

    final dir = await _cacheDir();
    final file =
        File('${dir.path}${Platform.pathSeparator}placeholder.png');
    if (!file.existsSync()) {
      final data = await rootBundle.load(_placeholderAsset);
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return _placeholder = file.uri;
  }
}
