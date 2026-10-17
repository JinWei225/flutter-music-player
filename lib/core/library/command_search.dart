import '../models/album.dart';
import '../models/track.dart';

/// What a prompt command does with the tracks it finds.
enum CommandVerb {
  /// Replace the queue and play in order.
  play,

  /// Replace the queue and play shuffled.
  shuffle,

  /// Queue behind the current track (Play Next).
  next,
}

/// A line typed into the prompt, split into its verb and search text.
///
/// Modelled on kew: `kew nayeon` plays everything matching "nayeon". The
/// `kew` prefix is optional, and a leading `shuffle` or `next` changes what
/// is done with the match.
class ParsedCommand {
  final CommandVerb verb;
  final String query;

  const ParsedCommand(this.verb, this.query);

  static ParsedCommand parse(String input) {
    var words = input.trim().split(RegExp(r'\s+'));
    if (words.isNotEmpty && words.first.toLowerCase() == 'kew') {
      words = words.sublist(1);
    }
    var verb = CommandVerb.play;
    if (words.length > 1) {
      final first = words.first.toLowerCase();
      for (final v in CommandVerb.values) {
        if (first == v.name) {
          verb = v;
          words = words.sublist(1);
          break;
        }
      }
    }
    return ParsedCommand(verb, words.join(' ').trim());
  }
}

enum MatchKind { artist, album, song }

/// One thing the prompt could play.
class CommandMatch {
  final MatchKind kind;

  /// The artist, album or song name as it appears in the library.
  final String label;

  /// The tracks to queue, in playback order.
  final List<Track> tracks;

  /// Where in [tracks] playback starts: the song itself for a song match,
  /// which is queued with the rest of its album so playback carries on.
  final int startIndex;

  /// Album for an album match; the song's album for a song match.
  final Album? album;

  final int score;

  const CommandMatch({
    required this.kind,
    required this.label,
    required this.tracks,
    required this.score,
    this.startIndex = 0,
    this.album,
  });

  Duration get totalDuration => tracks.fold(
    Duration.zero,
    (sum, t) => sum + (t.duration ?? Duration.zero),
  );
}

/// How well [query] matches [target], both already normalised; 0 for not at
/// all. Exact beats prefix beats a word start beats a substring beats the
/// query's letters merely appearing in order.
int matchScore(String query, String target) {
  if (query.isEmpty || target.isEmpty) return 0;
  if (target == query) return 100;
  if (target.startsWith(query)) return 80;
  if (target.split(' ').any((w) => w.startsWith(query))) return 60;
  if (target.contains(query)) return 40;
  if (query.length >= 3 && _isSubsequence(query.replaceAll(' ', ''), target)) {
    return 20;
  }
  return 0;
}

bool _isSubsequence(String needle, String haystack) {
  var i = 0;
  for (var j = 0; j < haystack.length && i < needle.length; j++) {
    if (haystack[j] == needle[i]) i++;
  }
  return i == needle.length;
}

/// Lowercases, folds common Latin accents, and reduces punctuation to single
/// spaces, so "Can’t Slow Me, No" and "cant slow me no" compare equal.
String normalizeForSearch(String s) {
  final lower = s.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_accentFold[ch] ?? ch);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r"['’`]"), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .trim();
}

const _accentFold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ñ': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ý': 'y', 'ÿ': 'y',
  'ß': 'ss',
};

/// Searches the library for artists, albums and songs matching [query],
/// best first, at most [limit] of them.
///
/// An artist is an album artist as the albums are grouped, and plays all of
/// their albums, oldest first. Ties go artist, then album, then song, since
/// the broader match is the more likely intent of a short query.
List<CommandMatch> searchLibrary(
  String query,
  List<Album> albums, {
  int limit = 8,
}) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return const [];
  final matches = <CommandMatch>[];

  final byArtist = <String, List<Album>>{};
  for (final a in albums) {
    byArtist.putIfAbsent(a.artist, () => []).add(a);
  }
  for (final MapEntry(key: artist, value: own) in byArtist.entries) {
    final score = matchScore(q, normalizeForSearch(artist));
    if (score == 0) continue;
    final ordered = [...own]..sort(_oldestFirst);
    matches.add(
      CommandMatch(
        kind: MatchKind.artist,
        label: artist,
        tracks: [for (final a in ordered) ...a.tracks],
        score: score,
      ),
    );
  }

  for (final a in albums) {
    final score = matchScore(q, normalizeForSearch(a.name));
    if (score == 0) continue;
    matches.add(
      CommandMatch(
        kind: MatchKind.album,
        label: a.name,
        tracks: a.tracks,
        album: a,
        score: score,
      ),
    );
  }

  for (final a in albums) {
    for (var i = 0; i < a.tracks.length; i++) {
      final t = a.tracks[i];
      final score = matchScore(q, normalizeForSearch(t.title));
      if (score == 0) continue;
      matches.add(
        CommandMatch(
          kind: MatchKind.song,
          label: t.title,
          tracks: a.tracks,
          startIndex: i,
          album: a,
          score: score,
        ),
      );
    }
  }

  matches.sort((x, y) {
    final s = y.score.compareTo(x.score);
    if (s != 0) return s;
    final k = x.kind.index.compareTo(y.kind.index);
    if (k != 0) return k;
    return x.label.toLowerCase().compareTo(y.label.toLowerCase());
  });
  return matches.take(limit).toList();
}

int _oldestFirst(Album a, Album b) {
  final ya = int.tryParse(a.year ?? '');
  final yb = int.tryParse(b.year ?? '');
  if (ya != null && yb != null && ya != yb) return ya.compareTo(yb);
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}
