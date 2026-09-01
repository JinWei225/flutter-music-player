import 'dart:io';

import '../core/metadata/tag_reader.dart';
import '../core/models/track.dart';

/// Where the app finds music. Desktop walks a folder; Android will later back
/// this with MediaStore and iOS with the media library, without the UI or the
/// player needing to change.
abstract class LibrarySource {
  /// Human-readable description of where music is being read from.
  String get description;

  Future<List<Track>> loadTracks();
}

/// Recursively scans a directory for supported audio files.
class DirectoryLibrarySource implements LibrarySource {
  final Directory root;

  /// Depth cap so a stray symlink loop cannot walk forever.
  static const _maxDepth = 8;

  DirectoryLibrarySource(this.root);

  /// The platform's default music folder.
  factory DirectoryLibrarySource.defaultLocation() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return DirectoryLibrarySource(Directory('$home${Platform.pathSeparator}Music'));
  }

  @override
  String get description => root.path;

  @override
  Future<List<Track>> loadTracks() async {
    if (!await root.exists()) return const [];

    final files = <File>[];
    await _collect(root, 0, files);

    // Tags are read concurrently; each parser only reads the handful of byte
    // ranges it needs, so this stays fast on a large library.
    final tracks = await Future.wait(files.map(TagReader.read));
    return tracks;
  }

  Future<void> _collect(Directory dir, int depth, List<File> out) async {
    if (depth > _maxDepth) return;
    late final List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return; // unreadable directory: skip rather than abort the scan
    }

    for (final e in entries) {
      final name = e.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        await _collect(e, depth + 1, out);
      } else if (e is File && TagReader.isSupported(e.path)) {
        out.add(e);
      }
    }
  }
}
