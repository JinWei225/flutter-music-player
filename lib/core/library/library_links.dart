import '../models/album.dart';
import '../models/track.dart';

/// A `mewsic://` link: something outside the app (Spotlight, Raycast,
/// Shortcuts, `open mewsic://…`) asking it to show part of the library.
///
///  * `mewsic://album?name=Na&artist=NAYEON` opens that album's page.
///    Adding `&action=play`, `shuffle` or `next` plays it, shuffles it or
///    queues it behind the current song instead, leaving the page as it is.
///  * `mewsic://song?path=/…/Air.m4a` plays that song, with the rest of its
///    album queued after it; `&action=next` queues just the song instead.
///  * `mewsic://control?do=play-pause` (or `next`, `previous`, `shuffle`,
///    `shuffle-all`) drives the player, like the media keys. An `&id=…`
///    is written back to `player.json` once the command has taken effect.
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
        final action = AlbumAction.values.asNameMap()[params['action']];
        if (params['action'] != null && action == null) return null;
        return AlbumLink(
          name: name,
          artist: params['artist'],
          action: action ?? AlbumAction.open,
        );
      case 'song':
        final path = params['path'];
        if (path == null || path.isEmpty) return null;
        final action = SongAction.values.asNameMap()[params['action']];
        if (params['action'] != null && action == null) return null;
        return SongLink(path, action: action ?? SongAction.play);
      case 'control':
        final action = ControlAction.byName(params['do']);
        return action == null ? null : ControlLink(action, id: params['id']);
      case 'search':
        return SearchLink(params['q'] ?? '');
    }
    return null;
  }

  /// Whether the library must have been scanned before this link can be
  /// carried out: it names, or plays from, something in it.
  bool get needsLibrary => switch (this) {
    AlbumLink() || SongLink() => true,
    ControlLink(:final action) => action == ControlAction.shuffleAll,
    SearchLink() => false,
  };

  Uri get uri;

  @override
  String toString() => uri.toString();
}

/// What an [AlbumLink] asks to be done with its album.
enum AlbumAction {
  /// Show the album's page.
  open,

  /// Replace the queue with the album and play it in order.
  play,

  /// Replace the queue with the album and play it shuffled.
  shuffle,

  /// Queue the album behind the current song (Play Next).
  next,
}

class AlbumLink extends LibraryLink {
  final String name;

  /// The album artist, as the app groups it. Optional: a hand-written link
  /// may give only the album name.
  final String? artist;

  final AlbumAction action;

  const AlbumLink({
    required this.name,
    this.artist,
    this.action = AlbumAction.open,
  });

  AlbumLink.of(Album album, {AlbumAction action = AlbumAction.open})
    : this(name: album.name, artist: album.artist, action: action);

  @override
  Uri get uri => Uri(
    scheme: LibraryLink.scheme,
    host: 'album',
    queryParameters: {
      'name': name,
      'artist': ?artist,
      if (action != AlbumAction.open) 'action': action.name,
    },
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
      other is AlbumLink &&
      other.name == name &&
      other.artist == artist &&
      other.action == action;

  @override
  int get hashCode => Object.hash(name, artist, action);
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

/// What a [SongLink] asks to be done with its song.
enum SongAction {
  /// Replace the queue with the song's album and play from the song.
  play,

  /// Queue just the song behind the current one (Play Next).
  next,
}

class SongLink extends LibraryLink {
  /// The song's file, which is what tells two same-named songs apart.
  final String path;
  final SongAction action;

  const SongLink(this.path, {this.action = SongAction.play});

  SongLink.of(Track track, {SongAction action = SongAction.play})
    : this(track.path, action: action);

  @override
  Uri get uri => Uri(
    scheme: LibraryLink.scheme,
    host: 'song',
    queryParameters: {
      'path': path,
      if (action != SongAction.play) 'action': action.name,
    },
  );

  /// The song in [albums] with this path, with its album; null when gone.
  (Album, int)? findIn(List<Album> albums) {
    for (final album in albums) {
      final i = album.tracks.indexWhere((t) => t.path == path);
      if (i >= 0) return (album, i);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SongLink && other.path == path && other.action == action;

  @override
  int get hashCode => Object.hash(path, action);
}

/// The player commands a [ControlLink] can give.
enum ControlAction {
  playPause('play-pause'),
  next('next'),
  previous('previous'),

  /// Turns shuffle on or off, as the player bar's button does.
  shuffle('shuffle'),

  /// Plays the whole library shuffled.
  shuffleAll('shuffle-all');

  /// How the action is spelled in a link.
  final String word;

  const ControlAction(this.word);

  static ControlAction? byName(String? word) {
    for (final a in values) {
      if (a.word == word) return a;
    }
    return null;
  }
}

class ControlLink extends LibraryLink {
  final ControlAction action;

  /// Chosen by whoever sent the link, and reported back once the command
  /// has taken effect, so they can tell its result from a change that
  /// happened to come first (a cold start's empty player, say).
  final String? id;

  const ControlLink(this.action, {this.id});

  @override
  Uri get uri => Uri(
    scheme: LibraryLink.scheme,
    host: 'control',
    queryParameters: {'do': action.word, 'id': ?id},
  );

  @override
  bool operator ==(Object other) =>
      other is ControlLink && other.action == action && other.id == id;

  @override
  int get hashCode => Object.hash(action, id);
}
