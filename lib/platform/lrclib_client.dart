import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What lrclib.net holds for one recording.
class LrclibRecord {
  /// LRC text with `[mm:ss.xx]` timestamps, when someone has timed it.
  final String? synced;
  final String? plain;

  /// No vocals. Only ever set when there are no lyrics either: lrclib.net
  /// has many entries flagged instrumental that carry a song's full lyrics
  /// (DALLA DALLA has a dozen), and the lyrics are what is right.
  final bool instrumental;

  /// Not the whole answer: part of the lookup failed, so a better version
  /// may still be found. Shown, but not kept.
  final bool partial;

  const LrclibRecord({
    this.synced,
    this.plain,
    this.instrumental = false,
    this.partial = false,
  });

  bool get hasSynced => synced != null;

  LrclibRecord get asPartial => LrclibRecord(
    synced: synced,
    plain: plain,
    instrumental: instrumental,
    partial: true,
  );

  static LrclibRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    String? text(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    final synced = text(json['syncedLyrics']);
    final plain = text(json['plainLyrics']);
    final instrumental =
        json['instrumental'] == true && synced == null && plain == null;
    if (synced == null && plain == null && !instrumental) return null;
    return LrclibRecord(
      synced: synced,
      plain: plain,
      instrumental: instrumental,
    );
  }
}

/// Thrown when lrclib.net could not be asked at all -- offline, timed out,
/// or the server failing -- as opposed to answering "no lyrics", so the
/// caller knows not to remember the miss.
class LrclibUnavailable implements Exception {
  final String message;

  /// How long the server asked us to wait before trying again, when it said.
  final Duration? retryAfter;

  const LrclibUnavailable(this.message, {this.retryAfter});

  @override
  String toString() => 'lrclib.net unavailable: $message';
}

/// The public lrclib.net API: free, no account or key.
///
/// The exact lookup (`/api/get`) matches on title, artist, album and a
/// duration within two seconds. It misses whenever the store's names differ
/// from whoever uploaded the lyrics -- an album called "AIR - EP" here and
/// "Air EP" there -- and it answers 503 when it cannot reach the outside
/// sources it falls back on. A search by title and artist then catches most
/// of those, but returns near-misses too (another song of the same length
/// by the same artist), so its results are only taken when the title and
/// artist really match.
///
/// lrclib.net often answers 503 ("try again in a second") or 429 (too many
/// requests); asked again a moment later, it answers. So every request is
/// retried a few times, waiting as long as the server asks, and lookups go
/// out one at a time so skipping through songs does not pile them up.
class LrclibClient {
  static const _host = 'lrclib.net';

  /// lrclib.net asks every client to say who it is.
  static const _userAgent =
      'Mewsic (https://github.com/JinWei225/flutter-music-player)';

  /// How far a recording's length may differ and still be the same one.
  static const _durationSlack = 2;

  /// Opened on the first lookup, so a library that never shows lyrics
  /// never opens a connection.
  late final HttpClient _http =
      _injectedHttp ??
      (HttpClient()..connectionTimeout = const Duration(seconds: 10));
  final HttpClient? _injectedHttp;

  /// Tries per request, the first included.
  static const _attempts = 5;

  /// Waits between tries; replaced in tests so they need not sleep.
  final Future<void> Function(Duration) _pause;

  /// The lookup in progress; the next one starts when it is done.
  Future<void> _queue = Future.value();

  LrclibClient({HttpClient? http, Future<void> Function(Duration)? pause})
    : _injectedHttp = http,
      _pause = pause ?? Future<void>.delayed;

  /// The best lyrics for a track, preferring timed ones, or null when
  /// lrclib.net has none. Throws [LrclibUnavailable] when it could not be
  /// asked. A record marked [LrclibRecord.partial] is the best of an
  /// incomplete answer.
  Future<LrclibRecord?> lookup({
    required String title,
    required String artist,
    required String album,
    Duration? duration,
  }) {
    final done = _queue.then(
      (_) => _lookup(
        title: title,
        artist: artist,
        album: album,
        duration: duration,
      ),
    );
    _queue = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }

  Future<LrclibRecord?> _lookup({
    required String title,
    required String artist,
    required String album,
    Duration? duration,
  }) async {
    LrclibRecord? exact;
    var exactFailed = false;
    if (duration != null) {
      try {
        exact = LrclibRecord.fromJson(
          await _ask('/api/get', {
            'track_name': title,
            'artist_name': artist,
            'album_name': album,
            'duration': '${(duration.inMilliseconds / 1000).round()}',
          }),
        );
      } on LrclibUnavailable {
        // The search below may still answer.
        exactFailed = true;
      }
      if (exact != null && exact.hasSynced) return exact;
    }

    List<Object?> results;
    try {
      final json = await _ask('/api/search', {
        'track_name': title,
        'artist_name': artist,
      });
      results = json is List ? json : const [];
    } on LrclibUnavailable {
      // The exact lookup's lyrics still stand, for now. Its "none" does not:
      // songs whose names differ there are only ever found by the search,
      // so without it there is no answer yet, and the miss must not be kept.
      if (exact != null) return exact.asPartial;
      rethrow;
    }

    final match = bestMatch(
      results,
      title: title,
      artist: artist,
      duration: duration,
    );
    if (exactFailed) {
      // Timed lyrics are as good as the exact lookup could have done;
      // anything less might have been beaten by it.
      if (match != null && match.hasSynced) return match;
      if (match != null) return match.asPartial;
      throw const LrclibUnavailable('exact lookup failed, search found none');
    }
    if (match == null) return exact;
    // A timed version beats the exact match's plain one.
    return exact == null || match.hasSynced ? match : exact;
  }

  /// [getJson], tried again while lrclib.net is busy or unreachable.
  Future<Object?> _ask(String path, Map<String, String> query) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await getJson(path, query);
      } on LrclibUnavailable catch (e) {
        if (attempt == _attempts) rethrow;
        // A second by default, as the server itself usually asks; its own
        // figure is honoured within reason.
        final wait = e.retryAfter ?? const Duration(seconds: 1);
        await _pause(
          wait > const Duration(seconds: 5) ? const Duration(seconds: 5) : wait,
        );
      }
    }
  }

  /// The search result that is really [title] by [artist], preferring timed
  /// lyrics and then the closest length.
  static LrclibRecord? bestMatch(
    List<Object?> results, {
    required String title,
    required String artist,
    Duration? duration,
  }) {
    final wantArtist = _key(_leadArtist(artist));
    final seconds = duration == null ? null : duration.inMilliseconds / 1000;

    LrclibRecord? best;
    var bestScore = double.infinity;
    for (final r in results) {
      if (r is! Map) continue;
      final record = LrclibRecord.fromJson(r);
      if (record == null) continue;

      if (!_sameTitle('${r['trackName'] ?? ''}', title)) continue;
      if (!_key('${r['artistName'] ?? ''}').contains(wantArtist)) continue;

      final length = r['duration'];
      final off = seconds == null || length is! num
          ? 0.0
          : (length - seconds).abs();
      if (off > _durationSlack) continue;

      // Timed lyrics win, then plain, then "instrumental"; among them,
      // lyrics the uploader also flagged instrumental come last, and the
      // length breaks ties.
      final flagged = r['instrumental'] == true && !record.instrumental;
      final score =
          off +
          (record.hasSynced
              ? 0
              : record.plain != null
              ? 100
              : 200) +
          (flagged ? 10 : 0);
      if (score < bestScore) {
        best = record;
        bestScore = score;
      }
    }
    return best;
  }

  /// Equal once case, spacing, punctuation, a leading article and any
  /// featuring or producer credit are set aside: "Magic" matches "Magic
  /// (feat. JULIE)", but "Air" does not match "Air (English Ver.)". The
  /// article goes because a purchase that only carries its sort-order title
  /// is named that way: "Feels" for TWICE's "The Feels".
  static bool _sameTitle(String a, String b) {
    String bare(String s) =>
        _key(s.replaceAll(_credit, '').replaceFirst(_article, ''));
    final x = bare(a);
    return x.isNotEmpty && x == bare(b);
  }

  static final _article = RegExp(r'^\s*(?:the|an?)\s+', caseSensitive: false);

  static final _credit = RegExp(
    r'\s*(?:[(\[]\s*(?:feat|ft|prod|with|from)\b[^)\]]*[)\]]'
    r'|[-–]\s*(?:feat|ft|prod)\b.*$)',
    caseSensitive: false,
  );

  /// The first name of a credit like "NAYEON & SAM KIM", which uploaders
  /// write in every way ("NAYEON, SAM KIM", "NAYEON feat. ...").
  static String _leadArtist(String artist) => artist
      .split(
        RegExp(
          r'\s*(?:&|,|;|/|\bfeat\.?|\bft\.|\bwith\b|\bx\b)\s*',
          caseSensitive: false,
        ),
      )
      .firstWhere((s) => s.trim().isNotEmpty, orElse: () => artist);

  static String _key(String s) => s
      .toLowerCase()
      .replaceAll('’', "'")
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

  /// The decoded JSON body, or null for a 404. Anything else that is not a
  /// 200 counts as the server being unavailable.
  @protected
  @visibleForTesting
  Future<Object?> getJson(String path, Map<String, String> query) async {
    final uri = Uri.https(_host, path, query);
    try {
      final request = await _http.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode == 404) {
        await response.drain<void>();
        return null;
      }
      if (response.statusCode != 200) {
        final seconds = int.tryParse(
          response.headers.value(HttpHeaders.retryAfterHeader) ?? '',
        );
        await response.drain<void>();
        throw LrclibUnavailable(
          'HTTP ${response.statusCode}',
          retryAfter: seconds == null ? null : Duration(seconds: seconds),
        );
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      return jsonDecode(body);
    } on LrclibUnavailable {
      rethrow;
    } on Exception catch (e) {
      // SocketException, TimeoutException, HandshakeException,
      // FormatException from a garbled body...
      throw LrclibUnavailable('$e');
    }
  }
}
