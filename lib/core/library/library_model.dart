import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../platform/artwork_store.dart';
import '../../platform/library_source.dart';
import '../metadata/tag_edit.dart';
import '../metadata/tag_writer.dart';
import '../models/album.dart';
import '../models/track.dart';

/// Writes [edit] into the file at [path]. Swapped out in tests.
typedef TagFileWriter = Future<void> Function(File file, TagEdit edit);

enum SortField { title, artist, album }

enum SortDirection { ascending, descending }

extension SortFieldLabel on SortField {
  String get label => switch (this) {
        SortField.title => 'Title',
        SortField.artist => 'Artist',
        SortField.album => 'Album',
      };
}

/// Holds the scanned library and the All Songs sort state.
class LibraryModel extends ChangeNotifier {
  final LibrarySource source;

  /// How edits reach disk. The default rewrites the audio file itself, so a
  /// correction made here shows up in every other player and on every device
  /// the file is copied to.
  final TagFileWriter writeTags;

  LibraryModel(this.source, {this.writeTags = TagWriter.write});

  List<Track> _tracks = const [];
  List<Album> _albums = const [];
  bool _loading = false;
  String? _error;

  SortField _sortField = SortField.title;
  SortDirection _sortDirection = SortDirection.ascending;

  bool get isLoading => _loading;
  String? get error => _error;
  List<Album> get albums => _albums;
  int get trackCount => _tracks.length;
  SortField get sortField => _sortField;
  SortDirection get sortDirection => _sortDirection;

  /// All songs in the user's chosen order.
  List<Track> get sortedTracks {
    final list = [..._tracks]..sort(_comparator);
    return list;
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _tracks = await source.loadTracks();
      _albums = Album.group(_tracks);
      // Covers may have been added to the files since they were last read.
      ArtworkStore.instance.clear();
    } catch (e) {
      _error = '$e';
      _tracks = const [];
      _albums = const [];
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void setSort(SortField field, SortDirection direction) {
    if (_sortField == field && _sortDirection == direction) return;
    _sortField = field;
    _sortDirection = direction;
    notifyListeners();
  }

  /// Toggles direction when the same field is picked again, otherwise switches
  /// field and starts ascending.
  void selectSortField(SortField field) {
    if (_sortField == field) {
      setSort(
        field,
        _sortDirection == SortDirection.ascending
            ? SortDirection.descending
            : SortDirection.ascending,
      );
    } else {
      setSort(field, SortDirection.ascending);
    }
  }

  /// Saves [edit] into [track]'s file and returns the track as it now reads.
  ///
  /// Throws [TagWriteException] when the file cannot be changed; the library
  /// is left as it was in that case.
  Future<Track> saveTags(Track track, TagEdit edit) async {
    final path = track.filePath;
    if (path == null || !TagWriter.canWrite(path)) {
      throw const TagWriteException('This file cannot be edited');
    }
    await writeTags(File(path), edit);

    final updated = track.copyWith(
      title: edit.titleOrNull ?? 'Unknown Title',
      artist: edit.artistOrNull ?? 'Unknown Artist',
      album: edit.albumOrNull ?? 'Unknown Album',
      albumArtist: edit.albumArtistOrNull ?? '',
      trackNumber: () => edit.trackNumber,
      discNumber: () => edit.discNumber,
      year: () => edit.yearOrNull,
      genre: () => edit.genreOrNull,
    );
    _tracks = [for (final t in _tracks) t == track ? updated : t];
    _albums = Album.group(_tracks);
    notifyListeners();
    return updated;
  }

  Album? albumFor(Track track) {
    for (final a in _albums) {
      if (a.key == track.albumKey) return a;
    }
    return null;
  }

  int _comparator(Track a, Track b) {
    final sign = _sortDirection == SortDirection.ascending ? 1 : -1;
    int cmp;
    switch (_sortField) {
      case SortField.title:
        cmp = _text(a.title, b.title);
        break;
      case SortField.artist:
        cmp = _text(a.artist, b.artist);
        // Within one artist, keep their albums together and in running order.
        if (cmp == 0) return _albumThenTrack(a, b) * sign;
        break;
      case SortField.album:
        cmp = _text(a.album, b.album);
        if (cmp == 0) return _discThenTrack(a, b) * sign;
        break;
    }
    if (cmp == 0) cmp = _text(a.title, b.title);
    return cmp * sign;
  }

  static int _albumThenTrack(Track a, Track b) {
    final c = _text(a.album, b.album);
    return c != 0 ? c : _discThenTrack(a, b);
  }

  static int _discThenTrack(Track a, Track b) {
    final d = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
    if (d != 0) return d;
    const unnumbered = 1 << 30;
    final t = (a.trackNumber ?? unnumbered).compareTo(b.trackNumber ?? unnumbered);
    return t != 0 ? t : _text(a.title, b.title);
  }

  /// Case-insensitive compare so "abba" and "ABBA" sort together.
  static int _text(String a, String b) =>
      a.toLowerCase().compareTo(b.toLowerCase());
}
