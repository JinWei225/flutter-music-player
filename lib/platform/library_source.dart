import 'dart:io';

import '../core/metadata/tag_reader.dart';
import '../core/models/track.dart';

/// Thrown when the system refuses access to the library, so the UI can say so
/// plainly instead of claiming there is no music.
class LibraryPermissionException implements Exception {
  final String message;

  const LibraryPermissionException(this.message);

  @override
  String toString() => message;
}

/// Where the app finds music. Desktop walks a folder; Android will later back
/// this with MediaStore and iOS with the media library, without the UI or the
/// player needing to change.
abstract class LibrarySource {
  /// Human-readable description of where music is being read from.
  String get description;

  Future<List<Track>> loadTracks();
}

/// The folders a desktop build scans.
///
/// `~/Music` (`%USERPROFILE%\Music` on Windows) is the default everywhere.
/// macOS is the one platform that needs more: Apple Music keeps its library a
/// level deeper, in `~/Music/Music/Media.localized`, and the system guards
/// that subtree behind its own *Media & Apple Music* privacy permission. A
/// plain walk of `~/Music` reaches it only once that permission is granted,
/// and is silently turned away until then -- so the folder is named as a root
/// in its own right, which is what lets the scan tell "no music here" apart
/// from "macOS said no".
class MusicFolders {
  /// Points the app at a library somewhere else entirely. One path, or several
  /// separated by the platform's path-list separator.
  static const envVariable = 'MEWSIC_MUSIC_DIR';

  /// The Apple Music library, relative to the user's `Music` folder.
  static const _macOSMediaFolder = 'Music/Media.localized';

  /// The roots to scan, outermost first. They are allowed to overlap; the scan
  /// visits each file once.
  static List<Directory> resolve() {
    final override = Platform.environment[envVariable];
    if (override != null && override.trim().isNotEmpty) {
      return override
          .split(Platform.isWindows ? ';' : ':')
          .map((p) => p.trim())
          .where((p) => p.isNotEmpty)
          .map(Directory.new)
          .toList();
    }

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    final music = Directory('$home${Platform.pathSeparator}Music');
    if (!Platform.isMacOS) return [music];

    // Only reached on macOS, so the separator is known to be '/'.
    return [music, Directory('${music.path}/$_macOSMediaFolder')];
  }
}

/// Recursively scans one or more directories for supported audio files.
class DirectoryLibrarySource implements LibrarySource {
  final List<Directory> roots;

  /// Depth cap so a stray symlink loop cannot walk forever.
  static const _maxDepth = 8;

  DirectoryLibrarySource(Directory root) : roots = [root];

  DirectoryLibrarySource.roots(this.roots);

  /// The platform's default music folders.
  factory DirectoryLibrarySource.defaultLocation() =>
      DirectoryLibrarySource.roots(MusicFolders.resolve());

  @override
  String get description => roots.map((r) => r.path).join('\nand ');

  @override
  Future<List<Track>> loadTracks() async {
    // Keyed by path so overlapping roots -- ~/Music and the Apple Music folder
    // nested inside it -- cannot yield the same file twice.
    final files = <String, File>{};
    final denied = <Directory>[];

    for (final root in roots) {
      if (!await root.exists()) continue;
      if (!await _collect(root, 0, files)) denied.add(root);
    }

    // A denial only matters when it left us with nothing to show: with tracks
    // in hand, an unreadable corner of the library is not worth an error page.
    if (files.isEmpty && denied.isNotEmpty) {
      throw LibraryPermissionException(_deniedMessage(denied));
    }

    // Tags are read concurrently; each parser only reads the handful of byte
    // ranges it needs, so this stays fast on a large library.
    return Future.wait(files.values.map(TagReader.read));
  }

  static String _deniedMessage(List<Directory> denied) {
    final where = denied.map((d) => d.path).join(', ');
    if (!Platform.isMacOS) {
      return 'Mewsic is not allowed to read $where.';
    }
    return 'macOS is blocking access to $where.\n'
        'Grant Mewsic access under System Settings > Privacy & Security > '
        'Media & Apple Music, then reopen the app.';
  }

  /// Walks [dir], adding audio files to [out]. Returns false when the
  /// directory itself could not be read.
  Future<bool> _collect(Directory dir, int depth, Map<String, File> out) async {
    if (depth > _maxDepth) return true;
    late final List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return false; // unreadable directory: skip rather than abort the scan
    }

    for (final e in entries) {
      final name = e.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        await _collect(e, depth + 1, out);
      } else if (e is File && TagReader.isSupported(e.path)) {
        out[e.path] = e;
      }
    }
    return true;
  }
}
