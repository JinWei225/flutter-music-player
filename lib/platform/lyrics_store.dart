import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:mewsic_tagfix/mewsic_tagfix.dart';
import 'package:path_provider/path_provider.dart';

import '../core/lyrics/lyrics.dart';
import '../core/models/track.dart';
import 'lrclib_client.dart';

/// What looking a track's lyrics up came to.
class LyricsLookup {
  /// The best lyrics found, or null for none.
  final Lyrics? lyrics;

  /// lrclib.net could not be asked, or not fully, so a better answer may
  /// come on a later try. With no [lyrics], "none" is then not known.
  final bool unavailable;

  const LyricsLookup(this.lyrics, {this.unavailable = false});
}

/// Finds a track's lyrics, in this order: an `.lrc` file beside the song,
/// the song's own lyrics tag, then lrclib.net. Timed lyrics are preferred
/// wherever they come from, so a file with plain lyrics still gets the
/// timed version from lrclib.net when there is one; the plain lyrics only
/// show when nothing timed turns up.
///
/// lrclib.net's answers -- "none" included -- are kept on the device, so a
/// song is looked up once rather than on every play, and its lyrics still
/// show offline. Timed lyrics are kept for good; anything less (plain
/// lyrics, "instrumental", none) is asked again after [_recheckAfter], in
/// case someone has added or timed the song since, and stays in use while
/// that cannot be done. A lookup that failed (offline, server down), or
/// only half answered, is not remembered, so the next play tries again.
class LyricsStore {
  /// The app-wide store. Tests swap in one that never reaches the network.
  static LyricsStore instance = LyricsStore();

  /// The few tracks around what is playing; older entries are dropped first.
  static const _maxEntries = 32;

  static const _recheckAfter = Duration(days: 3);

  static const _failureHeldFor = Duration(seconds: 15);

  /// Bumped when the cache file layout changes, so old files are ignored.
  /// 2: version 1 could remember a miss when lrclib.net's search had
  /// failed, hiding lyrics it does have; every song is asked once more.
  /// 3: version 2 could keep half an answer (plain lyrics, or a bare
  /// "instrumental") from a failed search. Its timed lyrics are kept; the
  /// rest is asked about again at once.
  static const _cacheVersion = 3;

  final LrclibClient _lrclib;
  final Future<Directory> Function() _cacheRoot;
  final DateTime Function() _now;

  LyricsStore({
    LrclibClient? lrclib,
    Future<Directory> Function()? cacheRoot,
    DateTime Function()? now,
  }) : _lrclib = lrclib ?? LrclibClient(),
       _cacheRoot = cacheRoot ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  final _byTrack = <String, Future<LyricsLookup>>{};

  /// When each held failure in [_byTrack] came back.
  final _failedAt = <String, DateTime>{};
  Directory? _dir;

  /// Lyrics for [track], and whether lrclib.net could be asked.
  ///
  /// A lookup that could not reach lrclib.net is given back as it is for a
  /// little while ([_failureHeldFor]), so showing the lyrics again -- a tab
  /// switch, a rebuild -- does not set off another round of requests; after
  /// that, or with [retry], it is made afresh.
  Future<LyricsLookup> forTrack(Track track, {bool retry = false}) {
    // The names are part of the key: after Edit Info renames a track, its
    // lyrics are looked up afresh under the new names.
    final key =
        '${track.path}\u0001${track.title}\u0001${track.artist}'
        '\u0001${track.album}';
    final failedAt = _failedAt[key];
    if (failedAt != null &&
        (retry || _now().difference(failedAt) >= _failureHeldFor)) {
      _byTrack.remove(key);
      _failedAt.remove(key);
    }
    final cached = _byTrack.remove(key);
    if (cached != null) {
      _byTrack[key] = cached; // most recently used goes last
      return cached;
    }

    late final Future<LyricsLookup> future;
    future = _resolve(track).then((r) {
      // Marked so the next request after a while tries again.
      if (!r.settled && identical(_byTrack[key], future)) {
        _failedAt[key] = _now();
      }
      return LyricsLookup(r.lyrics, unavailable: !r.settled);
    });
    _byTrack[key] = future;
    if (_byTrack.length > _maxEntries) {
      _failedAt.remove(_byTrack.keys.first);
      _byTrack.remove(_byTrack.keys.first);
    }
    return future;
  }

  void clear() {
    _byTrack.clear();
    _failedAt.clear();
  }

  Future<({Lyrics? lyrics, bool settled})> _resolve(Track track) async {
    final local = await _local(track);
    if (local != null && local.isSynced) return (lyrics: local, settled: true);

    final online = await _online(track);
    final found = online.lyrics;
    if (found != null && (local == null || found.isSynced)) {
      return (lyrics: found, settled: online.settled);
    }
    return (lyrics: local ?? found, settled: online.settled);
  }

  // --- on disk next to the song ---------------------------------------------

  Future<Lyrics?> _local(Track track) async {
    final path = track.filePath;
    if (path == null) return null;

    final sidecar = await _readSidecar(path);
    final fromFile = sidecar == null
        ? null
        : Lyrics.parse(sidecar, source: LyricsSource.file);
    if (fromFile != null && fromFile.isSynced) return fromFile;

    final tag = await TagReader.readLyrics(File(path));
    final embedded = tag == null
        ? null
        : Lyrics.parse(tag, source: LyricsSource.embedded);
    if (embedded != null && embedded.isSynced) return embedded;
    return fromFile ?? embedded;
  }

  /// `Song.lrc` beside `Song.m4a`. On Android the system usually will not
  /// let the app read a file that is not audio, so this then finds nothing.
  static Future<String?> _readSidecar(String audioPath) async {
    final dot = audioPath.lastIndexOf('.');
    final slash = audioPath.lastIndexOf(Platform.pathSeparator);
    final stem = dot > slash ? audioPath.substring(0, dot) : audioPath;
    for (final ext in const ['.lrc', '.LRC']) {
      try {
        final file = File('$stem$ext');
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        return utf8.decode(bytes, allowMalformed: true);
      } on FileSystemException {
        // Not readable here; try the next spelling, then give up.
      }
    }
    return null;
  }

  // --- lrclib.net, through the on-device cache ------------------------------

  Future<({Lyrics? lyrics, bool settled})> _online(Track track) async {
    final key = _cacheKey(track);
    final file = await _cacheFile(key);

    final remembered = await _readCache(file, key);
    if (remembered != null && !remembered.stale) {
      return (lyrics: remembered.lyrics, settled: true);
    }

    final LrclibRecord? record;
    try {
      record = await _lrclib.lookup(
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
      );
    } on LrclibUnavailable catch (e) {
      debugPrint('No lyrics lookup for ${track.title}: $e');
      // What was found before still beats nothing.
      return (lyrics: remembered?.lyrics, settled: false);
    }

    if (record != null && record.partial) {
      // Shown, but kept out of the cache so the next play asks again.
      return (
        lyrics: _fromRecord(record) ?? remembered?.lyrics,
        settled: false,
      );
    }
    await _writeCache(file, key, record);
    return (lyrics: _fromRecord(record), settled: true);
  }

  static Lyrics? _fromRecord(LrclibRecord? record) {
    if (record == null) return null;
    if (record.instrumental) {
      return const Lyrics.instrumental(source: LyricsSource.lrclib);
    }
    final synced = record.synced == null
        ? null
        : Lyrics.parse(record.synced!, source: LyricsSource.lrclib);
    if (synced != null && synced.isSynced) return synced;
    return record.plain == null
        ? null
        : Lyrics.parse(record.plain!, source: LyricsSource.lrclib);
  }

  /// What identifies a recording to lrclib.net. Kept inside the cache file
  /// as well, so two tracks whose keys hash alike cannot swap lyrics.
  static String _cacheKey(Track track) {
    final seconds = track.duration == null
        ? ''
        : '${(track.duration!.inMilliseconds / 1000).round()}';
    return '${track.artist}\u0001${track.title}\u0001${track.album}'
        '\u0001$seconds';
  }

  Future<File> _cacheFile(String key) async {
    final dir = _dir ??= Directory(
      '${(await _cacheRoot()).path}${Platform.pathSeparator}lyrics',
    );
    return File('${dir.path}${Platform.pathSeparator}${_hash(key)}.json');
  }

  /// The remembered answer, or null when there is none worth trusting: no
  /// file, a different track's file or an unreadable one. [stale] marks an
  /// answer short of timed lyrics that is old enough to ask about again.
  Future<({Lyrics? lyrics, bool stale})?> _readCache(
    File file,
    String key,
  ) async {
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      final version = json is Map ? json['version'] : null;
      if (json is! Map ||
          (version != _cacheVersion && version != 2) ||
          json['key'] != key) {
        return null;
      }
      final lyrics = json['found'] == true
          ? _fromRecord(LrclibRecord.fromJson(json))
          : null;
      if (lyrics != null && lyrics.isSynced) {
        return (lyrics: lyrics, stale: false);
      }
      final checked = json['checked'];
      if (checked is! int) return null;
      final age = _now().difference(
        DateTime.fromMillisecondsSinceEpoch(checked),
      );
      return (lyrics: lyrics, stale: version == 2 || age > _recheckAfter);
    } catch (e) {
      debugPrint('Ignoring unreadable lyrics cache ${file.path}: $e');
      return null;
    }
  }

  /// Written under a temporary name and renamed into place, so a crash
  /// mid-write cannot leave a half file to be read next time.
  Future<void> _writeCache(File file, String key, LrclibRecord? record) async {
    try {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'version': _cacheVersion,
          'key': key,
          'checked': _now().millisecondsSinceEpoch,
          'found': record != null,
          if (record != null) ...{
            'syncedLyrics': record.synced,
            'plainLyrics': record.plain,
            'instrumental': record.instrumental,
          },
        }),
        flush: true,
      );
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('Could not save lyrics to ${file.path}: $e');
    }
  }

  /// FNV-1a, 64-bit, over the key's UTF-8 bytes: a stable file name.
  static String _hash(String key) {
    var hash = 0xcbf29ce484222325;
    for (final b in utf8.encode(key)) {
      hash ^= b;
      hash *= 0x100000001b3; // wraps at 64 bits, as FNV intends
    }
    return hash.toUnsigned(64).toRadixString(16).padLeft(16, '0');
  }
}
