import 'dart:io';

import 'package:mewsic_tagfix/mewsic_tagfix.dart';

import '../models/track.dart';

/// Turns a file's tags into a [Track], filling gaps in this order: the
/// file's own tags, then the filename (title, track number), then the
/// folder layout (artist, album), then "Unknown".
///
/// Parsing itself lives in `mewsic_tagfix`; this is the thin step from its
/// [RawTags] to the player's own model.
class TrackReader {
  /// Parses a single file. A library scan should call [TagReader.parse] and
  /// [toTrack] separately so [SiblingTags] can run over the batch between.
  static Future<Track> read(File file, {Directory? libraryRoot}) async =>
      toTrack(file.path, await TagReader.parse(file), libraryRoot: libraryRoot);

  /// [libraryRoot] is the scanned folder the file was found under. When given,
  /// a file with no artist or album tag borrows them from its folder names
  /// (see [TagReader.folderTagsFromPath]); without it those fall back to
  /// "Unknown".
  static Track toTrack(String path, RawTags tags, {Directory? libraryRoot}) {
    final folder = libraryRoot == null
        ? null
        : TagReader.folderTagsFromPath(path, libraryRoot);

    return Track(
      path: path,
      // Desktop plays straight from the file it parsed.
      filePath: path,
      title: _clean(tags.title) ?? TagReader.titleFromFileName(path),
      artist: _clean(tags.artist) ?? folder?.artist ?? 'Unknown Artist',
      album: _clean(tags.album) ?? folder?.album ?? 'Unknown Album',
      albumArtist: _clean(tags.albumArtist) ?? '',
      trackNumber: tags.trackNumber ?? TagReader.trackNumberFromFileName(path),
      discNumber: tags.discNumber,
      year: _clean(tags.year),
      genre: _clean(tags.genre),
      duration: tags.duration,
    );
  }

  static String? _clean(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
