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

  static Future<Track> read(File file) async {
    final path = file.path;
    final ext = _extension(path);

    RawTags? tags;
    try {
      switch (ext) {
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
    tags ??= RawTags();

    return Track(
      path: path,
      // Desktop plays straight from the file it parsed.
      filePath: path,
      title: _clean(tags.title) ?? _titleFromFileName(path),
      artist: _clean(tags.artist) ?? 'Unknown Artist',
      album: _clean(tags.album) ?? 'Unknown Album',
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

  /// Strips the extension and any leading track number ("04 Magic" -> "Magic").
  static String _titleFromFileName(String path) {
    var name = path.split(Platform.pathSeparator).last;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    name = name.replaceFirst(RegExp(r'^\s*\d{1,3}\s*[-._ ]\s*'), '');
    return name.trim().isEmpty ? 'Unknown Title' : name.trim();
  }
}
