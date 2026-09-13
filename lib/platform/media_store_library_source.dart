import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mewsic_tagfix/mewsic_tagfix.dart';

import '../core/models/track.dart';
import 'library_source.dart';

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

    final entries = <_Entry>[];
    for (final row in rows.cast<Map<dynamic, dynamic>>()) {
      entries.add(await _toEntry(row));
    }

    // A nameless store purchase can borrow its names from album-mates that
    // share its store IDs -- but MediaStore does not surface those IDs, so
    // the well-indexed siblings are read once more to fetch them. Only done
    // when there is a track that could benefit.
    if (entries.any((e) => e.needsSiblings)) {
      await Future.wait(entries
          .where((e) => !e.reparsed && e.path != null && _isM4a(e.path!))
          .map((e) async {
        final parsed = await _reparse(e.path!);
        if (parsed != null) {
          e.tags
            ..storeTrackId = parsed.storeTrackId
            ..storeArtistId = parsed.storeArtistId
            ..storeAlbumId = parsed.storeAlbumId;
        }
      }));
      SiblingTags.complete(entries.map((e) => e.tags));
    }

    return [for (final e in entries) e.toTrack()];
  }

  static Future<_Entry> _toEntry(Map<dynamic, dynamic> row) async {
    final durationMs = row['durationMs'] as int?;
    final path = _text(row['path']);

    final tags = RawTags()
      ..title = _text(row['title'])
      ..artist = _text(row['artist'])
      ..album = _text(row['album'])
      ..albumArtist = _text(row['albumArtist'])
      ..trackNumber = row['trackNumber'] as int?
      ..discNumber = row['discNumber'] as int?
      ..year = _text(row['year'])
      ..duration =
          durationMs == null ? null : Duration(milliseconds: durationMs);

    var reparsed = false;
    if (_looksUnindexed(title: tags.title, artist: tags.artist, path: path)) {
      final parsed = await _reparse(path!);
      if (parsed != null) {
        reparsed = true;
        // The scanner's values are the weaker source here, so parsed tags win.
        tags
          ..title = _text(parsed.title) ?? tags.title
          ..artist = _text(parsed.artist) ?? tags.artist
          ..album = _text(parsed.album) ?? tags.album
          ..albumArtist = _text(parsed.albumArtist) ?? tags.albumArtist
          ..trackNumber ??= parsed.trackNumber
          ..discNumber ??= parsed.discNumber
          ..year ??= _text(parsed.year)
          ..genre ??= _text(parsed.genre)
          ..storeTrackId = parsed.storeTrackId
          ..storeArtistId = parsed.storeArtistId
          ..storeAlbumId = parsed.storeAlbumId;
      }
      // These files often carry no track number either; the filename's
      // leading digits are the only ordering hint left.
      tags.trackNumber ??= TagReader.trackNumberFromFileName(path);
    }

    return _Entry(
      source: row['source'] as String,
      path: path,
      tags: tags,
      reparsed: reparsed,
    );
  }

  static bool _isM4a(String path) => path.toLowerCase().endsWith('.m4a');

  /// True when the row carries scanner fallbacks rather than real tags: no
  /// artist, or a title that is just the file's name.
  static bool _looksUnindexed({
    required String? title,
    required String? artist,
    required String? path,
  }) {
    if (path == null || !_isM4a(path)) return false;
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

/// One MediaStore row on its way to becoming a [Track].
class _Entry {
  final String source;
  final String? path;
  final RawTags tags;

  /// Whether the file itself has already been read (so its store IDs are
  /// known) rather than only the scanner's row.
  final bool reparsed;

  _Entry({
    required this.source,
    required this.path,
    required this.tags,
    required this.reparsed,
  });

  /// A track still missing a name that a store ID could recover.
  bool get needsSiblings =>
      (tags.storeAlbumId != null || tags.storeArtistId != null) &&
      (tags.artist == null || tags.album == null);

  Track toTrack() => Track(
        path: source,
        filePath: path,
        title: tags.title ?? 'Unknown Title',
        artist: tags.artist ?? 'Unknown Artist',
        album: tags.album ?? 'Unknown Album',
        albumArtist: tags.albumArtist ?? '',
        trackNumber: tags.trackNumber,
        discNumber: tags.discNumber,
        year: tags.year,
        genre: tags.genre,
        duration: tags.duration,
      );
}
