import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:mewsic_tagfix/mewsic_tagfix.dart';
import 'package:path_provider/path_provider.dart';

import '../core/models/track.dart';

/// Resolves a track to an image the media session can display.
///
/// The notification's large icon needs a URI, not bytes, so embedded artwork is
/// written to the cache directory once per album and reused. Tracks with no
/// artwork fall back to a neutral cover tile -- without it the session reuses
/// the app icon, which then appears twice in the same notification.
class ArtworkCache {
  static const _placeholderAsset = 'assets/album_placeholder.png';

  /// Longest side of the cover handed to the session. The notification and
  /// the OEM overlays built on it (Xiaomi's dynamic island) read the bitmap
  /// out of the session metadata, and a full-size store cover can be too
  /// large for them to take; they then show no art at all.
  static const _maxSide = 512;

  /// Keyed by album so the file is written once for a whole album, not per
  /// track. Only covers that were found are kept: a fresh purchase has none
  /// until `mewsic-tagfix` embeds one, and remembering that miss would keep
  /// the placeholder up for as long as the app stays alive.
  final Map<String, Uri> _byAlbum = {};

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
    final known = _byAlbum[key];
    if (known != null) return known;

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
          await file.writeAsBytes(await _shrink(bytes), flush: true);
          result = file.uri;
        }
      }
    } catch (e) {
      debugPrint('Could not read artwork for ${track.title}: $e');
    }

    if (result != null) _byAlbum[key] = result;
    return result;
  }

  /// [bytes] scaled down to at most [_maxSide] on the longest side and
  /// re-encoded as PNG. Covers already that small, and any the engine cannot
  /// decode, are returned untouched.
  static Future<Uint8List> _shrink(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= _maxSide && descriptor.height <= _maxSide) {
        return bytes;
      }
      final landscape = descriptor.width >= descriptor.height;
      codec = await descriptor.instantiateCodec(
        targetWidth: landscape ? _maxSide : null,
        targetHeight: landscape ? null : _maxSide,
      );
      image = (await codec.getNextFrame()).image;
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      return png?.buffer.asUint8List() ?? bytes;
    } catch (e) {
      debugPrint('Could not shrink artwork: $e');
      return bytes;
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
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
