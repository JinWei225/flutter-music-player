import 'dart:io';
import 'dart:typed_data';

import 'raw_tags.dart';
import 'sibling_tags.dart';
import 'store_catalogue.dart';
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
/// With a [StoreCatalogue] the store itself is asked first, which is the only
/// source that knows a title's real punctuation, a track's own artist credit,
/// and the album's cover. A file is only ever completed, never changed: a
/// field that is present stays exactly as it is.
///
/// Repairs are planned per album folder because that is where a nameless
/// track's album-mates live.
class TagRepairer {
  final StoreCatalogue? catalogue;

  /// Called when the catalogue cannot be reached; the repair continues with
  /// local sources only.
  final void Function(String message)? onWarning;

  const TagRepairer({this.catalogue, this.onWarning});

  /// Plans repairs for every audio file under [root].
  Future<List<TagRepair>> planTree(Directory root) async {
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
  Future<List<TagRepair>> planFolder(Directory folder, {required Directory root}) async {
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
  Future<List<TagRepair>> planFiles(List<File> files, {required Directory root}) async {
    final parsed = <RawTags>[];
    for (final f in files) {
      parsed.add(await TagReader.parse(f));
    }

    // What each file said for itself, before album-mates weigh in.
    final own = [for (final t in parsed) _Names(t)];
    SiblingTags.complete(parsed);

    // Album-mates share an album, so the store is asked once per folder.
    final albums = <int, StoreAlbum?>{};
    final art = <int, Uint8List?>{};

    final repairs = <TagRepair>[];
    for (var i = 0; i < files.length; i++) {
      final t = parsed[i];
      final albumId = t.storeAlbumId;
      StoreAlbum? album;
      if (albumId != null && catalogue != null) {
        album = albums.containsKey(albumId)
            ? albums[albumId]
            : albums[albumId] = await _lookup(albumId, t.storefrontId);
      }
      final track = album == null || t.storeTrackId == null
          ? null
          : album.tracks[t.storeTrackId!];
      Uint8List? cover;
      if (album != null && !t.hasArtwork) {
        cover = art.containsKey(album.id)
            ? art[album.id]
            : art[album.id] = await _artwork(album);
      }
      final repair = _plan(files[i].path, t, own[i], root, album, track, cover);
      if (repair != null) repairs.add(repair);
    }
    return repairs;
  }

  Future<StoreAlbum?> _lookup(int albumId, int? storefrontId) async {
    try {
      return await catalogue!.album(albumId, storefrontId: storefrontId);
    } on CatalogueException catch (e) {
      onWarning?.call('$e');
      return null;
    }
  }

  Future<Uint8List?> _artwork(StoreAlbum album) async {
    try {
      return await catalogue!.artwork(album);
    } on CatalogueException catch (e) {
      onWarning?.call('$e');
      return null;
    }
  }

  static TagRepair? _plan(
    String path,
    RawTags t,
    _Names own,
    Directory root,
    StoreAlbum? album,
    StoreTrack? track,
    Uint8List? art,
  ) {
    final filled = <String>[];
    final folder = TagReader.folderTagsFromPath(path, root);

    String? title = t.title;
    String? artist = t.artist;
    String? albumName = t.album;
    String? albumArtist = t.albumArtist;
    String? genre = t.genre;
    int? trackNumber = t.trackNumber;
    int? discNumber = t.discNumber;
    String? date = t.rawDate;

    void note(String field, String? value, String source) {
      if (value != null) filled.add('$field ← $source');
    }

    if (t.namesFromSortAtoms) filled.add('names ← sort atoms');

    // Order of trust: the file's own atoms, the store, album-mates, the
    // folder layout, and lastly the filename.
    if (own.title == null) {
      title = track?.title;
      note('title', title, 'store');
      if (title == null) {
        title = TagReader.titleFromFileName(path);
        note('title', title, 'filename');
      }
    }
    if (own.artist == null) {
      artist = track?.artist;
      note('artist', artist, 'store');
      if (artist == null) {
        artist = t.artist;
        note('artist', artist, 'album-mates');
      }
      if (artist == null) {
        artist = folder?.artist;
        note('artist', artist, 'folder');
      }
    }
    if (own.album == null) {
      albumName = album?.name;
      note('album', albumName, 'store');
      if (albumName == null) {
        albumName = t.album;
        note('album', albumName, 'album-mates');
      }
      if (albumName == null) {
        albumName = folder?.album;
        note('album', albumName, 'folder');
      }
    }
    if (own.albumArtist == null) {
      albumArtist = album?.artist;
      note('album artist', albumArtist, 'store');
      if (albumArtist == null) {
        albumArtist = t.albumArtist;
        note('album artist', albumArtist, 'album-mates');
      }
    }
    if (own.genre == null) {
      genre = track?.genre ?? album?.genre;
      note('genre', genre, 'store');
      if (genre == null) {
        genre = t.genre;
        note('genre', genre, 'album-mates');
      }
    }
    if (trackNumber == null) {
      trackNumber = track?.trackNumber;
      if (trackNumber != null) filled.add('track ← store');
      if (trackNumber == null) {
        trackNumber = TagReader.trackNumberFromFileName(path);
        if (trackNumber != null) filled.add('track ← filename');
      }
    }
    if (discNumber == null && track?.discNumber != null) {
      discNumber = track!.discNumber;
      filled.add('disc ← store');
    }
    if (date == null) {
      date = track?.releaseDate ?? album?.releaseDate;
      note('date', date, 'store');
    }
    if (art != null) filled.add('artwork ← store');

    // Nothing missing, or nothing recoverable: leave the file be.
    if (filled.isEmpty) return null;

    return TagRepair(
      path: path,
      filled: filled,
      edit: TagEdit(
        title: title ?? '',
        artist: artist ?? '',
        album: albumName ?? '',
        albumArtist: albumArtist ?? '',
        genre: genre ?? '',
        // The full date as the file had it, so a repair never shortens it.
        year: date ?? t.year ?? '',
        trackNumber: trackNumber,
        discNumber: discNumber,
        artwork: art,
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
