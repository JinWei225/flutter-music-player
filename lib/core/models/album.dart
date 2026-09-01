import 'track.dart';

class Album {
  final String name;
  final String artist;
  final String? year;
  final List<Track> tracks;

  const Album({
    required this.name,
    required this.artist,
    required this.year,
    required this.tracks,
  });

  String get key => '$name\u0001$artist';

  Duration get totalDuration => tracks.fold(
        Duration.zero,
        (sum, t) => sum + (t.duration ?? Duration.zero),
      );

  /// Groups tracks into albums. Within an album, tracks are ordered by disc
  /// then track number so "Play All" follows the album's intended running
  /// order rather than filename order; untagged tracks sort last by title.
  static List<Album> group(List<Track> tracks) {
    // Bucket by album name first, then decide each bucket's album artist. A
    // track whose artist carries a guest ("NAYEON & SAM KIM") must not split
    // off into an album of its own.
    final byName = <String, List<Track>>{};
    for (final t in tracks) {
      byName.putIfAbsent(t.album, () => <Track>[]).add(t);
    }

    final byKey = <String, List<Track>>{};
    final artistForKey = <String, String>{};

    for (final entry in byName.entries) {
      final roots = _artistRoots(entry.value);
      for (final t in entry.value) {
        final artist = roots[t.effectiveAlbumArtist] ?? t.effectiveAlbumArtist;
        final key = '${entry.key}$artist';
        byKey.putIfAbsent(key, () => <Track>[]).add(t);
        artistForKey[key] = artist;
      }
    }

    final albums = byKey.entries.map((entry) {
      final sorted = [...entry.value]..sort(_byDiscThenTrack);
      String? year;
      for (final t in sorted) {
        if (t.year != null && t.year!.isNotEmpty) {
          year = t.year;
          break;
        }
      }
      return Album(
        name: sorted.first.album,
        artist: artistForKey[entry.key]!,
        year: year,
        tracks: sorted,
      );
    }).toList();

    albums.sort((a, b) {
      final n = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return n != 0 ? n : a.artist.toLowerCase().compareTo(b.artist.toLowerCase());
    });
    return albums;
  }

  /// Maps every artist within one album-name bucket to its "root" artist.
  ///
  /// An artist folds into another only when the shorter name is a whole-word
  /// prefix of the longer one, so "NAYEON & SAM KIM" joins "NAYEON" while two
  /// genuinely different artists who happen to share an album title stay
  /// apart. A band whose own name contains a separator, like
  /// "Simon & Garfunkel", is untouched because no shorter name sits alongside
  /// it to fold into.
  static Map<String, String> _artistRoots(List<Track> tracks) {
    final distinct = <String>{for (final t in tracks) t.effectiveAlbumArtist}
        .toList()
      ..sort((a, b) => a.length.compareTo(b.length));

    final roots = <String, String>{};
    for (final artist in distinct) {
      var root = artist;
      for (final candidate in distinct) {
        if (candidate.length >= artist.length) break;
        if (_isLeadArtistOf(candidate, artist)) {
          root = roots[candidate] ?? candidate;
          break;
        }
      }
      roots[artist] = root;
    }
    return roots;
  }

  /// True when [short] names the lead artist that [long] extends, e.g.
  /// "NAYEON" within "NAYEON & SAM KIM". The character after the prefix must
  /// not be alphanumeric, so "NAY" cannot swallow "NAYEON".
  static bool _isLeadArtistOf(String short, String long) {
    if (short.isEmpty || long.length <= short.length) return false;
    if (!long.toLowerCase().startsWith(short.toLowerCase())) return false;
    return !RegExp(r'[A-Za-z0-9]').hasMatch(long[short.length]);
  }

  static int _byDiscThenTrack(Track a, Track b) {
    final d = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
    if (d != 0) return d;
    // Untagged tracks sort after numbered ones instead of pretending to be #0.
    const unnumbered = 1 << 30;
    final t = (a.trackNumber ?? unnumbered).compareTo(b.trackNumber ?? unnumbered);
    if (t != 0) return t;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  }
}
