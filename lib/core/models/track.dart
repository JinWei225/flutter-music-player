import 'dart:io';

/// A single playable audio file together with its parsed tags.
class Track {
  /// What the audio engine plays: an absolute file path on desktop, or a
  /// `content://` URI on Android.
  final String path;

  /// The on-disk path when one is known. On Android this differs from [path]:
  /// playback goes through the content URI, but the file itself stays readable
  /// for tag and artwork parsing.
  final String? filePath;
  final String title;
  final String artist;
  final String album;
  final String albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final String? year;
  final String? genre;
  final Duration? duration;

  const Track({
    required this.path,
    this.filePath,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.year,
    this.genre,
    this.duration,
  });

  /// The same file with edited tags, as the Edit Info sheet leaves it.
  Track copyWith({
    String? title,
    String? artist,
    String? album,
    String? albumArtist,
    int? Function()? trackNumber,
    int? Function()? discNumber,
    String? Function()? year,
    String? Function()? genre,
  }) =>
      Track(
        path: path,
        filePath: filePath,
        title: title ?? this.title,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        albumArtist: albumArtist ?? this.albumArtist,
        trackNumber: trackNumber == null ? this.trackNumber : trackNumber(),
        discNumber: discNumber == null ? this.discNumber : discNumber(),
        year: year == null ? this.year : year(),
        genre: genre == null ? this.genre : genre(),
        duration: duration,
      );

  /// Files usually only carry a per-track artist; falling back to it keeps a
  /// normal single-artist album together, while a real album-artist tag lets a
  /// compilation with differing track artists still collapse into one album.
  String get effectiveAlbumArtist =>
      albumArtist.isNotEmpty ? albumArtist : artist;

  /// Albums are keyed by name *and* artist: two artists can both release an
  /// album called "Air", and they must not merge into one tile.
  String get albumKey => '$album\u0001$effectiveAlbumArtist';

  /// The file's own name. On Android [path] is a `content://` URI whose last
  /// segment is a row id, so the on-disk path is preferred when known.
  String get fileName => (filePath ?? path).split(Platform.pathSeparator).last;

  @override
  bool operator ==(Object other) => other is Track && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
