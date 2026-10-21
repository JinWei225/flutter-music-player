/// Where a track's lyrics were found, shown as a small credit under them.
enum LyricsSource {
  /// An `.lrc` file next to the song, sharing its name.
  file,

  /// The song file's own lyrics tag.
  embedded,

  /// Downloaded from lrclib.net.
  lrclib,
}

/// One line of lyrics. [time] is when it starts, for timed (LRC) lyrics;
/// plain lyrics carry none.
class LyricLine {
  final Duration? time;

  /// Empty for a stanza break in plain lyrics, or an instrumental gap in
  /// timed ones.
  final String text;

  const LyricLine(this.text, [this.time]);
}

/// A track's lyrics: timed lines when the source had timestamps, plain lines
/// otherwise.
class Lyrics {
  final List<LyricLine> lines;
  final LyricsSource source;

  /// The source says the track has no vocals; [lines] is then empty.
  final bool instrumental;

  const Lyrics(this.lines, {required this.source, this.instrumental = false});

  const Lyrics.instrumental({required this.source})
    : lines = const [],
      instrumental = true;

  bool get isSynced => lines.isNotEmpty && lines.first.time != null;

  /// Reads LRC (`[01:23.45] line`) when [text] has any timestamps, and plain
  /// text otherwise. Null when there is nothing but blank lines.
  static Lyrics? parse(String text, {required LyricsSource source}) {
    final rawLines = text
        .replaceFirst('﻿', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');

    var offset = Duration.zero;
    final timed = <LyricLine>[];
    for (final raw in rawLines) {
      final line = raw.trim();
      final tags = _timeTags.matchAsPrefix(line);
      if (tags == null) {
        final meta = _offsetTag.firstMatch(line);
        if (meta != null) {
          offset = Duration(milliseconds: int.parse(meta.group(1)!));
        }
        continue;
      }
      final words = line
          .substring(tags.end)
          .replaceAll(_wordTimes, '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      // `[00:12.00][00:48.00]chorus` repeats one line at several times.
      for (final t in _timeTag.allMatches(tags.group(0)!)) {
        timed.add(LyricLine(words, _time(t)));
      }
    }

    if (timed.isNotEmpty) {
      // A positive offset makes every line come in earlier.
      final shifted = [
        for (final l in timed) LyricLine(l.text, _clamp(l.time! - offset)),
      ]..sort((a, b) => a.time!.compareTo(b.time!));
      if (shifted.every((l) => l.text.isEmpty)) return null;
      return Lyrics(_trimGaps(shifted), source: source);
    }

    final plain = <LyricLine>[];
    for (final raw in rawLines) {
      final line = raw.trimRight();
      if (_metaTag.hasMatch(line.trim())) continue;
      // One blank line between stanzas is plenty.
      if (line.trim().isEmpty && (plain.isEmpty || plain.last.text.isEmpty)) {
        continue;
      }
      plain.add(LyricLine(line.trim().isEmpty ? '' : line));
    }
    while (plain.isNotEmpty && plain.last.text.isEmpty) {
      plain.removeLast();
    }
    return plain.isEmpty ? null : Lyrics(plain, source: source);
  }

  /// Index of the line being sung at [position]: the last one that has
  /// started, or -1 before the first. Always -1 for plain lyrics.
  int lineAt(Duration position) {
    if (!isSynced) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    var found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time! <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }

  /// Drops empty lines before the first words and collapses runs of them,
  /// which LRC files use to mark gaps but which would only show as holes.
  static List<LyricLine> _trimGaps(List<LyricLine> lines) {
    final out = <LyricLine>[];
    for (final l in lines) {
      if (l.text.isEmpty && (out.isEmpty || out.last.text.isEmpty)) continue;
      out.add(l);
    }
    return out;
  }

  static Duration _time(Match m) {
    final minutes = int.parse(m.group(1)!);
    final seconds = int.parse(m.group(2)!);
    // `.5`, `.50` and `.500` are all half a second.
    final fraction = m.group(3);
    final millis = fraction == null
        ? 0
        : int.parse(fraction.padRight(3, '0').substring(0, 3));
    return Duration(minutes: minutes, seconds: seconds, milliseconds: millis);
  }

  static Duration _clamp(Duration d) => d.isNegative ? Duration.zero : d;

  static final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
  static final _timeTags = RegExp(
    r'(?:\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]\s*)+',
  );

  /// Enhanced LRC's per-word timings, `<00:12.34>`, which are not shown.
  static final _wordTimes = RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>');
  static final _offsetTag = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]$');

  /// `[ar:Artist]`, `[ti:Title]` and the like at the head of an LRC file.
  static final _metaTag = RegExp(r'^\[[a-z#]+:[^\]]*\]$', caseSensitive: false);
}
