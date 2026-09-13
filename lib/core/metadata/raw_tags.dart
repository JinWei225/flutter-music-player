/// Mutable accumulator used by the format-specific tag parsers before the
/// result is normalised into a [Track].
class RawTags {
  String? title;
  String? artist;
  String? album;
  String? albumArtist;
  String? year;
  String? genre;
  int? trackNumber;
  int? discNumber;
  Duration? duration;

  /// iTunes Store catalogue IDs (`cnID`, `atID`, `plID`). Purchases always
  /// carry these even when -- as some do -- they ship with no names at all,
  /// so they are what lets a nameless track be matched to its album-mates.
  int? storeTrackId;
  int? storeArtistId;
  int? storeAlbumId;

  /// The release date exactly as the file spells it (`©day`, `TDRC`), so a
  /// rewrite can put it back verbatim; [year] is the four digits shown.
  String? rawDate;

  /// True when title, artist or album came from a sort-order atom because
  /// the real one was absent. Most players do not read those, so such a file
  /// still shows as unknown elsewhere and is worth repairing.
  bool namesFromSortAtoms = false;

  /// How many meaningful fields were recovered. Used to choose between
  /// competing tag blocks in a single file (see the MP4 parser's decoy `ilst`).
  int get fieldCount {
    var n = 0;
    for (final v in [title, artist, album, albumArtist, year, genre]) {
      if (v != null && v.trim().isNotEmpty) n++;
    }
    if (trackNumber != null) n++;
    if (discNumber != null) n++;
    return n;
  }

  bool get isEmpty => fieldCount == 0;

  /// Fills in anything this block is missing from [other], so a weak ID3v1
  /// trailer can complete an ID3v2 header without overwriting it.
  void backfillFrom(RawTags other) {
    // Names taken from a block that itself got them from sort atoms carry
    // that provenance with them.
    if (other.namesFromSortAtoms &&
        ((title == null && other.title != null) ||
            (artist == null && other.artist != null) ||
            (album == null && other.album != null))) {
      namesFromSortAtoms = true;
    }
    title ??= other.title;
    artist ??= other.artist;
    album ??= other.album;
    albumArtist ??= other.albumArtist;
    year ??= other.year;
    genre ??= other.genre;
    trackNumber ??= other.trackNumber;
    discNumber ??= other.discNumber;
    duration ??= other.duration;
    storeTrackId ??= other.storeTrackId;
    storeArtistId ??= other.storeArtistId;
    storeAlbumId ??= other.storeAlbumId;
    rawDate ??= other.rawDate;
  }
}
