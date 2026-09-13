import 'dart:typed_data';

/// The fields a user can change from the Edit Info sheet.
///
/// Every text field is explicit: an empty string clears the tag from the
/// file, so a wrong value can be removed and not just replaced. [artwork] is
/// the one exception: null leaves whatever cover the file has, and bytes
/// (JPEG or PNG) replace it. Nothing else in the file -- store IDs, lyrics,
/// sort names -- is touched.
class TagEdit {
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final String genre;
  final String year;
  final int? trackNumber;
  final int? discNumber;
  final Uint8List? artwork;

  const TagEdit({
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    required this.genre,
    required this.year,
    required this.trackNumber,
    required this.discNumber,
    this.artwork,
  });

  /// 13 for JPEG, 14 for PNG (iTunes' well-known data types), by magic bytes.
  static int? artworkType(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
      return 13;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4e && bytes[3] == 0x47) {
      return 14;
    }
    return null;
  }

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
