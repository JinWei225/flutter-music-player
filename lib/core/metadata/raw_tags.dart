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
    title ??= other.title;
    artist ??= other.artist;
    album ??= other.album;
    albumArtist ??= other.albumArtist;
    year ??= other.year;
    genre ??= other.genre;
    trackNumber ??= other.trackNumber;
    discNumber ??= other.discNumber;
    duration ??= other.duration;
  }
}
