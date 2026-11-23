import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/library/library_links.dart';
import '../core/models/album.dart';
import 'library_mirror.dart';

/// Writes the library's albums, and their songs, to a file other apps can
/// read, for the Mewsic Raycast extension (`raycast/` in this repository).
///
/// The app is sandboxed, so it cannot be asked for its library; instead it
/// keeps `albums.json` and a `covers` folder in
/// `~/Library/Application Support/Mewsic/`, the one place outside its
/// container its entitlements let it write. Each album carries the
/// `mewsic://` links that open, play, shuffle or queue it, and each song the
/// links that play or queue it, so the extension never builds links itself.
///
/// Covers are written once per album and kept while its signature (see
/// [albumSignature]) stays the same. A cover's file name changes with its
/// contents, so Raycast never shows a cached old one; covers no longer
/// referenced are deleted.
class AlbumCatalog extends LibraryMirror {
  final Future<Directory?> Function() _directory;
  final Future<Uint8List?> Function(Album album) _coverFor;

  AlbumCatalog(
    super.library, {
    super.settle,
    Future<Directory?> Function()? directory,
    Future<Uint8List?> Function(Album album)? coverFor,
  }) : _directory = directory ?? sharedFolder,
       _coverFor = coverFor ?? readAlbumCover;

  /// Bump when the file's shape changes in a way the extension must know.
  static const format = 1;

  static const fileName = 'albums.json';
  static const coversFolder = 'covers';

  @override
  String get name => 'the album catalog';

  @override
  Future<void> syncOnce() async {
    final dir = await _directory();
    if (dir == null) return;
    final file = File('${dir.path}/$fileName');
    final covers = Directory('${dir.path}/$coversFolder');
    await covers.create(recursive: true);

    final previous = await _readPrevious(file);
    final albums = <Map<String, Object?>>[];
    final kept = <String>{};

    for (final album in library.albums) {
      final id = AlbumLink.of(album).toString();
      final signature = await albumSignature(album);
      final before = previous[id];

      String? cover;
      if (before != null &&
          before.signature == signature &&
          (before.cover == null || File(before.cover!).existsSync())) {
        cover = before.cover;
      } else {
        final bytes = await _coverFor(album);
        if (bytes != null) {
          final path = '${covers.path}/${_hex(id)}-${_hex(signature)}.png';
          await _writeAtomically(File(path), (f) => f.writeAsBytes(bytes));
          cover = path;
        }
      }
      if (cover != null) kept.add(_fileName(cover));

      albums.add({
        'id': id,
        'name': album.name,
        'artist': album.artist,
        'year': album.year,
        'songs': album.tracks.length,
        'seconds': album.totalDuration.inSeconds,
        'cover': cover,
        'signature': signature,
        'links': {
          for (final action in AlbumAction.values)
            action.name: AlbumLink.of(album, action: action).toString(),
        },
        'tracks': [
          for (final t in album.tracks)
            {
              'title': t.title,
              'artist': t.artist,
              'number': t.trackNumber,
              'disc': t.discNumber,
              'seconds': t.duration?.inSeconds,
              'links': {
                for (final action in SongAction.values)
                  action.name: SongLink.of(t, action: action).toString(),
              },
            },
        ],
      });
    }

    final text = const JsonEncoder.withIndent(' ')
        .convert({'format': format, 'albums': albums});
    // Left alone when nothing changed, so Raycast is not told to reload.
    final old = await file.exists() ? await file.readAsString() : null;
    if (old != text) {
      await _writeAtomically(file, (f) => f.writeAsString(text));
    }

    await for (final entry in covers.list()) {
      // By name: Windows lists '\' where the paths above were joined with '/'.
      if (entry is File && !kept.contains(_fileName(entry.path))) {
        await entry.delete();
      }
    }
  }

  /// The covers and signatures written last time, by album id.
  static Future<Map<String, ({String signature, String? cover})>> _readPrevious(
    File file,
  ) async {
    try {
      if (!await file.exists()) return {};
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['format'] != format) return {};
      return {
        for (final a in json['albums'] as List)
          if (a is Map && a['id'] is String && a['signature'] is String)
            a['id'] as String: (
              signature: a['signature'] as String,
              cover: a['cover'] as String?,
            ),
      };
    } catch (e) {
      debugPrint('Could not read the album catalog: $e');
      return {};
    }
  }

  /// Written aside and renamed into place, so Raycast never reads half a
  /// file.
  static Future<void> _writeAtomically(
    File file,
    Future<void> Function(File temp) write,
  ) async {
    final temp = File('${file.path}.tmp');
    await write(temp);
    await temp.rename(file.path);
  }

  static String _fileName(String path) =>
      path.substring(path.lastIndexOf(RegExp(r'[/\\]')) + 1);

  /// FNV-1a of [text], as eight hex digits: short, stable file names.
  static String _hex(String text) {
    var hash = 0x811c9dc5;
    for (final b in utf8.encode(text)) {
      hash = ((hash ^ b) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static const _channel = MethodChannel(
    'com.jinwei.custom_music_player/catalog',
  );

  /// `~/Library/Application Support/Mewsic` in the real home folder, which
  /// only the native side can name: inside the sandbox, HOME is the app's
  /// container.
  ///
  /// On Windows there is no sandbox: it is `%USERPROFILE%\.mewsic`. Not
  /// `%LOCALAPPDATA%`: Raycast is a packaged app, and the extensions it runs
  /// cannot see files there (they read as missing).
  static Future<Directory?> sharedFolder() async {
    if (Platform.isWindows) {
      final home = Platform.environment['USERPROFILE'];
      return home == null || home.isEmpty ? null : Directory('$home\\.mewsic');
    }
    try {
      final path = await _channel.invokeMethod<String>('directory');
      return path == null ? null : Directory(path);
    } on MissingPluginException {
      return null;
    }
  }
}
