import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mewsic_tagfix/mewsic_tagfix.dart';

import '../core/library/library_model.dart';
import '../core/models/album.dart';
import 'artwork_cache.dart';

/// A copy of the library's albums kept somewhere outside the app (Spotlight,
/// the file Raycast reads), brought up to date after every scan or edit.
///
/// Subclasses say how to update their copy in [syncOnce]; this class decides
/// when. It waits for the library to sit still for [settle], so a burst of
/// tag edits makes one update rather than one per edit, and never runs two
/// updates at once.
abstract class LibraryMirror {
  final LibraryModel library;

  /// How long the library must stay still before the copy is updated.
  final Duration settle;

  LibraryMirror(this.library, {this.settle = const Duration(seconds: 2)});

  Timer? _timer;
  Future<void>? _running;
  bool _again = false;

  /// What the copy is, for log lines: "Spotlight".
  String get name;

  void start() {
    library.addListener(_onLibrary);
    _onLibrary();
  }

  void dispose() {
    library.removeListener(_onLibrary);
    _timer?.cancel();
  }

  void _onLibrary() {
    // A failed scan leaves the library empty; that is not a reason to empty
    // the copy too.
    if (library.isLoading || !library.hasLoaded || library.error != null) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(settle, sync);
  }

  /// Brings the copy in line with the library. A call made while one is
  /// running waits for it and then runs again, so the last state wins.
  Future<void> sync() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() {
      _running = null;
    });
  }

  Future<void> _loop() async {
    do {
      _again = false;
      try {
        await syncOnce();
      } catch (e) {
        debugPrint('Could not update $name: $e');
      }
    } while (_again);
  }

  /// One update of the copy from [library]'s current albums.
  @protected
  Future<void> syncOnce();
}

/// Longest side of the covers handed out of the app. Spotlight's preview
/// and Raycast's grid both show them at most a little over 100 points across.
const int kMirrorCoverSide = 256;

/// What a copy of [album] would show, plus its cover file's modification
/// time: when this is unchanged, the copy is too. The cover counts as
/// changed when its file's time does, which is what `mewsic-tagfix`
/// embedding a cover looks like from here.
Future<String> albumSignature(Album album) async {
  final path = albumCoverPath(album);
  final modified = path == null
      ? 0
      : (await File(path).stat()).modified.millisecondsSinceEpoch;
  return [
    album.year ?? '',
    album.tracks.length,
    album.totalDuration.inSeconds,
    modified,
  ].join('|');
}

/// The file the album's cover is read from: its first track on disk.
String? albumCoverPath(Album album) {
  for (final t in album.tracks) {
    if (t.filePath != null) return t.filePath;
  }
  return null;
}

/// The album's cover as a PNG of at most [kMirrorCoverSide], or null when it
/// has none.
Future<Uint8List?> readAlbumCover(Album album) async {
  final path = albumCoverPath(album);
  if (path == null) return null;
  try {
    final bytes = await TagReader.readArtwork(File(path));
    if (bytes == null || bytes.isEmpty) return null;
    return await ArtworkCache.shrink(bytes, maxSide: kMirrorCoverSide);
  } catch (e) {
    debugPrint('Could not read the cover of ${album.name}: $e');
    return null;
  }
}
