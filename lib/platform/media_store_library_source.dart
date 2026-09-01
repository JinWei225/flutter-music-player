import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/metadata/mp4_tags.dart';
import '../core/metadata/raw_tags.dart';
import '../core/metadata/tag_reader.dart';
import '../core/models/track.dart';
import 'library_source.dart';

/// Thrown when the user declines audio access, so the UI can say so plainly.
class LibraryPermissionException implements Exception {
  final String message;

  const LibraryPermissionException(this.message);

  @override
  String toString() => message;
}

/// Android library, read from MediaStore.
///
/// Scoped storage rules out walking a music folder the way the desktop build
/// does, so the system index is the starting point. It is not always right,
/// though: some store-bought files carry only the sort-name atoms, and
/// Android's scanner records those as `<unknown>` with the filename as title.
/// Rows that look like that are re-read with the app's own MP4 parser.
class MediaStoreLibrarySource implements LibrarySource {
  static const _channel =
      MethodChannel('com.jinwei.custom_music_player/library');

  @override
  String get description => 'your device music library';

  @override
  Future<List<Track>> loadTracks() async {
    // Surfaced through LibraryModel.error so the empty state can explain the
    // denial instead of claiming there is no music on the device.
    if (!await _ensurePermission()) {
      throw const LibraryPermissionException(
        'Permission to read audio files was denied. '
        'Grant it in Settings to see your music.',
      );
    }

    final List<dynamic>? rows =
        await _channel.invokeMethod<List<dynamic>>('queryAudio');
    if (rows == null) return const [];

    final tracks = <Track>[];
    for (final row in rows.cast<Map<dynamic, dynamic>>()) {
      tracks.add(await _toTrack(row));
    }
    return tracks;
  }

  static Future<Track> _toTrack(Map<dynamic, dynamic> row) async {
    final durationMs = row['durationMs'] as int?;
    final path = _text(row['path']);

    var title = _text(row['title']);
    var artist = _text(row['artist']);
    var album = _text(row['album']);
    var albumArtist = _text(row['albumArtist']);
    var trackNumber = row['trackNumber'] as int?;
    var discNumber = row['discNumber'] as int?;
    var year = _text(row['year']);

    if (_looksUnindexed(title: title, artist: artist, path: path)) {
      final parsed = await _reparse(path!);
      if (parsed != null) {
        // The scanner's values are the weaker source here, so parsed tags win.
        title = _text(parsed.title) ?? title;
        artist = _text(parsed.artist) ?? artist;
        album = _text(parsed.album) ?? album;
        albumArtist = _text(parsed.albumArtist) ?? albumArtist;
        trackNumber ??= parsed.trackNumber;
        discNumber ??= parsed.discNumber;
        year ??= _text(parsed.year);
      }
      // These files often carry no track number either; the filename's
      // leading digits are the only ordering hint left.
      trackNumber ??= TagReader.trackNumberFromFileName(path);
    }

    return Track(
      path: row['source'] as String,
      filePath: path,
      title: title ?? 'Unknown Title',
      artist: artist ?? 'Unknown Artist',
      album: album ?? 'Unknown Album',
      albumArtist: albumArtist ?? '',
      trackNumber: trackNumber,
      discNumber: discNumber,
      year: year,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
    );
  }

  /// True when the row carries scanner fallbacks rather than real tags: no
  /// artist, or a title that is just the file's name.
  static bool _looksUnindexed({
    required String? title,
    required String? artist,
    required String? path,
  }) {
    if (path == null || !path.toLowerCase().endsWith('.m4a')) return false;
    if (artist == null) return true;

    if (title == null) return true;
    var fileName = path.split(Platform.pathSeparator).last;
    final dot = fileName.lastIndexOf('.');
    if (dot > 0) fileName = fileName.substring(0, dot);
    return title == fileName;
  }

  /// Reads the file directly. Shared media stays readable by path with audio
  /// permission granted, but a failure here is never fatal -- the scanner's
  /// values are kept instead.
  static Future<RawTags?> _reparse(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return await Mp4TagParser.parse(file);
    } catch (e) {
      debugPrint('Could not re-read tags for $path: $e');
      return null;
    }
  }

  /// MediaStore uses the literal string `<unknown>` for missing artist/album.
  static String? _text(Object? value) {
    if (value is! String) return null;
    final t = value.trim();
    if (t.isEmpty || t == '<unknown>') return null;
    return t;
  }

  /// Asks the activity to check, and if needed request, audio access. Which
  /// permission that is depends on the OS version, so the decision lives on
  /// the Android side.
  Future<bool> _ensurePermission() async =>
      await _channel.invokeMethod<bool>('ensureAudioPermission') ?? false;
}
