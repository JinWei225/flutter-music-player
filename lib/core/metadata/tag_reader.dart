import 'dart:io';

import '../models/track.dart';
import 'mp3_tags.dart';
import 'mp4_tags.dart';
import 'raw_tags.dart';

/// Turns an audio file on disk into a [Track], dispatching to the right tag
/// parser and filling sensible fallbacks when a file is untagged.
class TagReader {
  /// Extensions we attempt to read and play.
  static const supportedExtensions = {'.m4a', '.mp4', '.m4b', '.mp3', '.aac'};

  static bool isSupported(String path) =>
      supportedExtensions.contains(_extension(path));

  /// Parses a single file. Convenience for [parse] followed by [toTrack];
  /// a library scan should call those separately so `SiblingTags` can run
  /// over the whole batch in between.
  static Future<Track> read(File file, {Directory? libraryRoot}) async =>
      toTrack(file.path, await parse(file), libraryRoot: libraryRoot);

  /// Reads whatever tags [file] carries. Never null: a malformed or untagged
  /// file yields an empty [RawTags] so the fallbacks in [toTrack] apply.
  static Future<RawTags> parse(File file) async {
    RawTags? tags;
    try {
      switch (_extension(file.path)) {
        case '.m4a':
        case '.mp4':
        case '.m4b':
          tags = await Mp4TagParser.parse(file);
          break;
        case '.mp3':
        case '.aac':
          tags = await Mp3TagParser.parse(file);
          break;
      }
    } catch (_) {
      // A malformed file should drop to filename fallbacks, not sink the scan.
      tags = null;
    }
    return tags ?? RawTags();
  }

  /// Turns parsed [tags] into a [Track], filling gaps in this order: the
  /// file's own tags, then the filename (title, track number), then the
  /// folder layout (artist, album), then "Unknown".
  ///
  /// [libraryRoot] is the scanned folder the file was found under. When given,
  /// a file with no artist or album tag borrows them from its folder names
  /// (see [folderTagsFromPath]); without it those fall back to "Unknown".
  static Track toTrack(String path, RawTags tags, {Directory? libraryRoot}) {
    final folder =
        libraryRoot == null ? null : folderTagsFromPath(path, libraryRoot);

    return Track(
      path: path,
      // Desktop plays straight from the file it parsed.
      filePath: path,
      title: _clean(tags.title) ?? _titleFromFileName(path),
      artist: _clean(tags.artist) ?? folder?.artist ?? 'Unknown Artist',
      album: _clean(tags.album) ?? folder?.album ?? 'Unknown Album',
      albumArtist: _clean(tags.albumArtist) ?? '',
      trackNumber: tags.trackNumber ?? trackNumberFromFileName(path),
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

  static String _extension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot).toLowerCase();
  }

  /// Recovers a track number from a "04 Magic.m4a" style filename.
  ///
  /// Only a fallback: some store downloads carry no `trkn` atom at all, and
  /// without this their album would list in alphabetical order instead of the
  /// running order the numbers in the filenames imply.
  static int? trackNumberFromFileName(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final match = RegExp(r'^\s*(\d{1,3})\s*[-._ ]').firstMatch(name);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!);
    return (value == null || value == 0) ? null : value;
  }

  /// Recovers artist and album from an `<Artist>/<Album>/<file>` layout.
  ///
  /// Only a fallback, and a last-resort one: some iTunes Store purchases
  /// arrive with *no* title, artist or album atoms at all -- just the store's
  /// numeric IDs -- and Apple's own Music app only shows them correctly
  /// because it reads its library database rather than the file. The folder
  /// layout it writes is the one place the names survive on disk.
  ///
  /// Requires the file to sit at least two folders below [root], so a loose
  /// `~/Music/song.mp3` never reports "Music" as its album and the home
  /// folder as its artist.
  static ({String artist, String album})? folderTagsFromPath(
      String path, Directory root) {
    final sep = Platform.pathSeparator;
    final rootPath = root.path.endsWith(sep) ? root.path : '${root.path}$sep';
    if (!path.startsWith(rootPath)) return null;

    final parts = path.substring(rootPath.length).split(sep);
    // Artist, album, file -- anything shallower is not a library layout.
    if (parts.length < 3) return null;
    final album = parts[parts.length - 2].trim();
    final artist = parts[parts.length - 3].trim();
    if (album.isEmpty || artist.isEmpty) return null;
    return (artist: artist, album: album);
  }

  /// Strips the extension and any leading track number ("04 Magic" -> "Magic").
  static String _titleFromFileName(String path) {
    var name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    name = name.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-._ ]\s*'), '');
    return name.trim().isEmpty ? 'Unknown Title' : name.trim();
  }
}
