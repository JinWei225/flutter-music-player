import 'raw_tags.dart';

/// Fills in names a file lacks from other files that share its iTunes Store
/// IDs.
///
/// Some store purchases arrive with no `©nam`/`©ART`/`©alb` atoms at all --
/// only the catalogue IDs, a release date and a copyright line. Apple's Music
/// app still shows them correctly because it reads its library database
/// rather than the file, but any other player sees "Unknown Artist". The IDs
/// do travel with the file, though, so as long as one properly tagged track
/// from the same album is in the library, the names can be recovered from it.
/// Nothing here depends on folder layout, so it holds up after the files are
/// copied to another device.
class SiblingTags {
  /// Completes every entry in [all] in place. Only fields that are missing
  /// are filled; a file's own tags are never overwritten.
  static void complete(Iterable<RawTags> all) {
    final tags = all.toList();

    // Album ID -> the names its tagged tracks agree on.
    final albums = <int, _Votes>{};
    // Artist ID -> the credited artist names. An album's tracks can credit a
    // guest ("NAYEON & SAM KIM") under the same artist ID, so the most common
    // spelling wins rather than the first seen.
    final artists = <int, _Votes>{};

    for (final t in tags) {
      final albumId = t.storeAlbumId;
      if (albumId != null && _has(t.album)) {
        final v = albums.putIfAbsent(albumId, _Votes.new);
        v.album.add(t.album!);
        if (_has(t.albumArtist)) v.albumArtist.add(t.albumArtist!);
        if (_has(t.genre)) v.genre.add(t.genre!);
      }
      final artistId = t.storeArtistId;
      if (artistId != null && _has(t.artist)) {
        artists.putIfAbsent(artistId, _Votes.new).artist.add(t.artist!);
      }
    }
    if (albums.isEmpty && artists.isEmpty) return;

    for (final t in tags) {
      final album = t.storeAlbumId == null ? null : albums[t.storeAlbumId!];
      if (album != null) {
        if (!_has(t.album)) t.album = album.album.winner;
        if (!_has(t.albumArtist)) t.albumArtist = album.albumArtist.winner;
        if (!_has(t.genre)) t.genre = album.genre.winner;
      }
      if (!_has(t.artist)) {
        final artist =
            t.storeArtistId == null ? null : artists[t.storeArtistId!];
        // The album artist is the right credit for a track whose own artist
        // line is missing; failing that, whoever the artist ID usually names.
        t.artist = album?.albumArtist.winner ?? artist?.artist.winner;
      }
    }
  }

  static bool _has(String? s) => s != null && s.trim().isNotEmpty;
}

class _Votes {
  final album = _Tally();
  final albumArtist = _Tally();
  final artist = _Tally();
  final genre = _Tally();
}

/// Counts spellings and reports the most common; ties go to the first seen.
class _Tally {
  final _counts = <String, int>{};

  void add(String value) => _counts.update(value, (n) => n + 1, ifAbsent: () => 1);

  String? get winner {
    String? best;
    var bestCount = 0;
    for (final e in _counts.entries) {
      if (e.value > bestCount) {
        best = e.key;
        bestCount = e.value;
      }
    }
    return best;
  }
}
