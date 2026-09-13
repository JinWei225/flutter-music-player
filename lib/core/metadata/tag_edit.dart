/// The fields a user can change from the Edit Info sheet.
///
/// Every text field is explicit: an empty string clears the tag from the
/// file, so a wrong value can be removed and not just replaced. Nothing else
/// in the file -- artwork, store IDs, lyrics, sort names -- is touched.
class TagEdit {
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final String year;
  final int? trackNumber;
  final int? discNumber;

  const TagEdit({
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.genre,
    required this.year,
    required this.trackNumber,
    required this.discNumber,
  });

  String? get titleOrNull => _orNull(title);
  String? get artistOrNull => _orNull(artist);
  String? get albumOrNull => _orNull(album);
  String? get albumArtistOrNull => _orNull(albumArtist);
  String? get genreOrNull => _orNull(genre);
  String? get yearOrNull => _orNull(year);

  static String? _orNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }
}
