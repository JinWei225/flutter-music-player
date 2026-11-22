import '../models/album.dart';

/// A `mewsic://` link: something outside the app (Spotlight, Raycast,
/// Shortcuts, `open mewsic://…`) asking it to show part of the library.
///
///  * `mewsic://album?name=Na&artist=NAYEON` opens that album's page.
///  * `mewsic://search?q=nayeon` opens the prompt with "nayeon" typed in.
sealed class LibraryLink {
  const LibraryLink();

  static const scheme = 'mewsic';

  /// The link [text] spells, or null when it is not one the app knows.
  static LibraryLink? parse(String text) {
    final Uri uri;
    try {
      uri = Uri.parse(text.trim());
    } on FormatException {
      return null;
    }
    if (uri.scheme.toLowerCase() != scheme) return null;
    final params = uri.queryParameters;
    switch (uri.host.toLowerCase()) {
      case 'album':
        final name = params['name'];
        if (name == null || name.isEmpty) return null;
        return AlbumLink(name: name, artist: params['artist']);
      case 'search':
        return SearchLink(params['q'] ?? '');
    }
    return null;
  }

  Uri get uri;

  @override
  String toString() => uri.toString();
}

class AlbumLink extends LibraryLink {
  final String name;

  /// The album artist, as the app groups it. Optional: a hand-written link
  /// may give only the album name.
  final String? artist;

  const AlbumLink({required this.name, this.artist});

  AlbumLink.of(Album album) : this(name: album.name, artist: album.artist);

  @override
  Uri get uri => Uri(
    scheme: LibraryLink.scheme,
    host: 'album',
    queryParameters: {'name': name, if (artist != null) 'artist': artist},
  );

  /// The album in [albums] this link names, or null when there is none.
  ///
  /// Exact names win. Failing that, case is ignored, so a link typed by
  /// hand still lands; and with no artist given, the name alone must pick
  /// out a single album rather than guess between two.
  Album? findIn(List<Album> albums) {
    final artist = this.artist;
    if (artist != null) {
      for (final a in albums) {
        if (a.name == name && a.artist == artist) return a;
      }
    }
    final lowerName = name.toLowerCase();
    final lowerArtist = artist?.toLowerCase();
    final candidates = [
      for (final a in albums)
        if (a.name.toLowerCase() == lowerName &&
            (lowerArtist == null || a.artist.toLowerCase() == lowerArtist))
          a,
    ];
    return candidates.length == 1 ? candidates.single : null;
  }

  @override
  bool operator ==(Object other) =>
      other is AlbumLink && other.name == name && other.artist == artist;

  @override
  int get hashCode => Object.hash(name, artist);
}

class SearchLink extends LibraryLink {
  final String query;

  const SearchLink(this.query);

  @override
  Uri get uri => Uri(
    scheme: LibraryLink.scheme,
    host: 'search',
    queryParameters: {'q': query},
  );

  @override
  bool operator ==(Object other) => other is SearchLink && other.query == query;

  @override
  int get hashCode => query.hashCode;
}
