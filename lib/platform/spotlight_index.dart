import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mewsic_tagfix/mewsic_tagfix.dart';
import 'package:path_provider/path_provider.dart';

import '../core/library/library_links.dart';
import '../core/library/library_model.dart';
import '../core/models/album.dart';
import 'artwork_cache.dart';

/// Keeps the library's albums in macOS Spotlight, so typing an album's name
/// there offers it, with its cover, and picking it opens the album here.
///
/// Each item's identifier is the album's `mewsic://` link, which the app
/// opens when the result is chosen. After every scan the albums are compared
/// with what was sent last time (remembered in a small file), and only new
/// or changed albums are sent; albums no longer in the library are removed.
/// A cover counts as changed when its file's modification time does, which
/// is what `mewsic-tagfix` embedding a cover looks like from here.
class SpotlightIndex {
  final LibraryModel library;

  /// How long the library must stay still before it is indexed, so a burst
  /// of tag edits sends one update rather than one per edit.
  final Duration settle;

  final Future<File> Function() _stateFile;
  final Future<Uint8List?> Function(Album album) _coverFor;

  SpotlightIndex(
    this.library, {
    this.settle = const Duration(seconds: 2),
    Future<File> Function()? stateFile,
    Future<Uint8List?> Function(Album album)? coverFor,
  }) : _stateFile = stateFile ?? _defaultStateFile,
       _coverFor = coverFor ?? _readCover;

  static const _channel = MethodChannel(
    'com.jinwei.custom_music_player/spotlight',
  );

  /// Bump when what an item carries changes, so every album is sent again.
  static const _format = 1;

  /// Albums per message: covers make each one a few tens of kilobytes.
  static const _batchSize = 20;

  /// Longest side of the cover Spotlight is given. Its preview shows the
  /// thumbnail at most a little over 100 points across.
  static const coverSide = 256;

  Timer? _timer;
  Future<void>? _running;
  bool _again = false;

  void start() {
    library.addListener(_onLibrary);
    _onLibrary();
  }

  void dispose() {
    library.removeListener(_onLibrary);
    _timer?.cancel();
  }

  void _onLibrary() {
    // A failed scan leaves the library empty; that is not a reason to take
    // every album out of Spotlight.
    if (library.isLoading || !library.hasLoaded || library.error != null) {
      return;
    }
    _timer?.cancel();
    _timer = Timer(settle, sync);
  }

  /// Brings Spotlight in line with the library. A call made while one is
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
        await _syncOnce();
      } catch (e) {
        debugPrint('Could not update Spotlight: $e');
      }
    } while (_again);
  }

  Future<void> _syncOnce() async {
    if (await _channel.invokeMethod<bool>('isAvailable') != true) return;

    final file = await _stateFile();
    var sent = await _readState(file);
    if (sent == null) {
      // First run, or items from an older format: start clean.
      await _channel.invokeMethod<void>('deleteAll');
      sent = {};
      await _writeState(file, sent);
    }

    final albums = {
      for (final a in library.albums) AlbumLink.of(a).toString(): a,
    };

    final gone = [
      for (final id in sent.keys)
        if (!albums.containsKey(id)) id,
    ];
    if (gone.isNotEmpty) {
      await _channel.invokeMethod<void>('delete', gone);
      gone.forEach(sent.remove);
      await _writeState(file, sent);
    }

    final batch = <Map<String, Object>>[];
    final signatures = <String, String>{};
    Future<void> flush() async {
      if (batch.isEmpty) return;
      await _channel.invokeMethod<void>('index', batch);
      sent!.addAll(signatures);
      batch.clear();
      signatures.clear();
      await _writeState(file, sent);
    }

    for (final MapEntry(key: id, value: album) in albums.entries) {
      final signature = await _signature(album);
      if (sent[id] == signature) continue;
      final cover = await _coverFor(album);
      batch.add({
        'id': id,
        'title': album.name,
        'artist': album.artist,
        'year': ?album.year,
        'songs': album.tracks.length,
        'seconds': album.totalDuration.inSeconds,
        'cover': ?cover,
      });
      signatures[id] = signature;
      if (batch.length >= _batchSize) await flush();
    }
    await flush();
  }

  /// Everything an item shows, plus the cover file's modification time.
  static Future<String> _signature(Album album) async {
    final path = _coverPath(album);
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
  static String? _coverPath(Album album) {
    for (final t in album.tracks) {
      if (t.filePath != null) return t.filePath;
    }
    return null;
  }

  static Future<Uint8List?> _readCover(Album album) async {
    final path = _coverPath(album);
    if (path == null) return null;
    try {
      final bytes = await TagReader.readArtwork(File(path));
      if (bytes == null || bytes.isEmpty) return null;
      return await ArtworkCache.shrink(bytes, maxSide: coverSide);
    } catch (e) {
      debugPrint('Could not read the cover of ${album.name}: $e');
      return null;
    }
  }

  static Future<File> _defaultStateFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}spotlight.json');
  }

  /// What was last sent, by item identifier; null when there is no record
  /// or it was written in another format.
  static Future<Map<String, String>?> _readState(File file) async {
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['format'] != _format) return null;
      final albums = json['albums'];
      if (albums is! Map) return null;
      return {
        for (final MapEntry(:key, :value) in albums.entries)
          if (key is String && value is String) key: value,
      };
    } catch (e) {
      debugPrint('Could not read the Spotlight record: $e');
      return null;
    }
  }

  /// Written aside and renamed into place, so a crash mid-write leaves the
  /// old record rather than half a file.
  static Future<void> _writeState(File file, Map<String, String> sent) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode({'format': _format, 'albums': sent}));
    await temp.rename(file.path);
  }
}
