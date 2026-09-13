import 'dart:io';

import 'raw_tags.dart';
import 'sibling_tags.dart';
import 'tag_edit.dart';
import 'tag_reader.dart';
import 'tag_writer.dart';

/// One file whose missing names can be filled in, and where each fill comes
/// from -- so a dry run can say exactly what it would do.
class TagRepair {
  final String path;
  final TagEdit edit;

  /// Human-readable notes, e.g. `artist ← album-mates` or `title ← filename`.
  final List<String> filled;

  const TagRepair({required this.path, required this.edit, required this.filled});

  String get fileName => path.split(Platform.pathSeparator).last;

  Future<void> apply() => TagWriter.write(File(path), edit);
}

/// Works out how to complete files that arrived without names.
///
/// This is the app's own recovery -- sort atoms, album-mates sharing store
/// IDs, the `Artist/Album/` folder layout, the filename -- turned around and
/// written *into* the files, so any player on any device reads them right.
/// A file is only ever completed, never changed: a field that is present
/// stays exactly as it is, and a file with nothing missing is left alone.
///
/// Repairs are planned per album folder because that is where a nameless
/// track's album-mates live.
class TagRepairer {
  /// Plans repairs for every audio file under [root].
  static Future<List<TagRepair>> planTree(Directory root) async {
    final byFolder = <String, List<File>>{};
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File || !TagReader.isSupported(e.path) || _isTemporary(e.path)) {
        continue;
      }
      byFolder.putIfAbsent(e.parent.path, () => []).add(e);
    }
    final repairs = <TagRepair>[];
    for (final files in byFolder.values) {
      repairs.addAll(await planFiles(files, root: root));
    }
    repairs.sort((a, b) => a.path.compareTo(b.path));
    return repairs;
  }

  /// Plans repairs for one album folder.
  static Future<List<TagRepair>> planFolder(Directory folder,
      {required Directory root}) async {
    final files = <File>[];
    await for (final e in folder.list(followLinks: false)) {
      if (e is File && TagReader.isSupported(e.path) && !_isTemporary(e.path)) {
        files.add(e);
      }
    }
    return planFiles(files, root: root);
  }

  /// Plans repairs for [files], which should be album-mates so they can
  /// complete one another.
  static Future<List<TagRepair>> planFiles(List<File> files,
      {required Directory root}) async {
    final parsed = <RawTags>[];
    for (final f in files) {
      parsed.add(await TagReader.parse(f));
    }

    // What each file said for itself, before album-mates weigh in.
    final own = [for (final t in parsed) _Names(t)];
    SiblingTags.complete(parsed);

    final repairs = <TagRepair>[];
    for (var i = 0; i < files.length; i++) {
      final repair = _plan(files[i].path, parsed[i], own[i], root);
      if (repair != null) repairs.add(repair);
    }
    return repairs;
  }

  static TagRepair? _plan(String path, RawTags t, _Names own, Directory root) {
    final incomplete = own.title == null || own.artist == null || own.album == null;
    if (!incomplete && !t.namesFromSortAtoms) return null;

    final filled = <String>[];
    final folder = TagReader.folderTagsFromPath(path, root);

    String? title = t.title;
    String? artist = t.artist;
    String? album = t.album;
    String? albumArtist = t.albumArtist;
    String? genre = t.genre;
    int? trackNumber = t.trackNumber;

    void note(String field, String? value, String source) {
      if (value != null) filled.add('$field ← $source');
    }

    if (t.namesFromSortAtoms) filled.add('names ← sort atoms');
    if (own.title == null && title == null) {
      title = TagReader.titleFromFileName(path);
      note('title', title, 'filename');
    }
    if (own.artist == null) {
      if (artist != null) {
        note('artist', artist, 'album-mates');
      } else {
        artist = folder?.artist;
        note('artist', artist, 'folder');
      }
    }
    if (own.album == null) {
      if (album != null) {
        note('album', album, 'album-mates');
      } else {
        album = folder?.album;
        note('album', album, 'folder');
      }
    }
    if (own.albumArtist == null && albumArtist != null) {
      note('album artist', albumArtist, 'album-mates');
    }
    if (own.genre == null && genre != null) note('genre', genre, 'album-mates');
    if (trackNumber == null) {
      trackNumber = TagReader.trackNumberFromFileName(path);
      if (trackNumber != null) filled.add('track ← filename');
    }

    // Nothing recoverable (a loose, untagged file): leave it be.
    if (filled.isEmpty) return null;

    return TagRepair(
      path: path,
      filled: filled,
      edit: TagEdit(
        title: title ?? '',
        artist: artist ?? '',
        album: album ?? '',
        albumArtist: albumArtist ?? '',
        genre: genre ?? '',
        // The full date as the file had it, so a repair never shortens it.
        year: t.rawDate ?? t.year ?? '',
        trackNumber: trackNumber,
        discNumber: t.discNumber,
      ),
    );
  }

  /// A download still in flight, or one of our own half-written files.
  static bool _isTemporary(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.startsWith('.') ||
        name.endsWith('.mewsic-tmp') ||
        name.endsWith('.tmp') ||
        name.endsWith('.download');
  }
}

class _Names {
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final String? genre;

  _Names(RawTags t)
      : title = t.title,
        artist = t.artist,
        album = t.album,
        albumArtist = t.albumArtist,
        genre = t.genre;
}
