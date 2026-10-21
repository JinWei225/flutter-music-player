import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// What lrclib.net holds for one recording.
class LrclibRecord {
  /// LRC text with `[mm:ss.xx]` timestamps, when someone has timed it.
  final String? synced;
  final String? plain;
  final bool instrumental;

  const LrclibRecord({this.synced, this.plain, this.instrumental = false});

  bool get hasSynced => synced != null;

  static LrclibRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    String? text(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    final record = LrclibRecord(
      synced: text(json['syncedLyrics']),
      plain: text(json['plainLyrics']),
      instrumental: json['instrumental'] == true,
    );
    final empty =
        record.synced == null && record.plain == null && !record.instrumental;
    return empty ? null : record;
  }
}

/// Thrown when lrclib.net could not be asked at all -- offline, timed out,
/// or the server failing -- as opposed to answering "no lyrics", so the
/// caller knows not to remember the miss.
class LrclibUnavailable implements Exception {
  final String message;

  const LrclibUnavailable(this.message);

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

  LrclibClient({HttpClient? http}) : _injectedHttp = http;

  /// The best lyrics for a track, preferring timed ones, or null when
  /// lrclib.net has none. Throws [LrclibUnavailable] when it could not be
  /// asked.
  Future<LrclibRecord?> lookup({
    required String title,
    required String artist,
    required String album,
    Duration? duration,
  }) async {
    LrclibRecord? exact;
    if (duration != null) {
      try {
        exact = LrclibRecord.fromJson(
          await getJson('/api/get', {
            'track_name': title,
            'artist_name': artist,
            'album_name': album,
            'duration': '${(duration.inMilliseconds / 1000).round()}',
          }),
        );
      } on LrclibUnavailable {
        // The search below may still answer.
      }
      if (exact != null && exact.hasSynced) return exact;
    }

    List<Object?> results;
    try {
      final json = await getJson('/api/search', {
        'track_name': title,
        'artist_name': artist,
      });
      results = json is List ? json : const [];
    } on LrclibUnavailable {
      // The exact lookup's lyrics still stand. Its "none" does not: songs
      // whose names differ there are only ever found by the search, so
      // without it there is no answer yet, and the miss must not be kept.
      if (exact != null) return exact;
      rethrow;
    }

    final match = bestMatch(
      results,
      title: title,
      artist: artist,
      duration: duration,
    );
    if (match == null) return exact;
    // A timed version beats the exact match's plain one.
    return exact == null || match.hasSynced ? match : exact;
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

      // Timed lyrics win outright; the length breaks ties.
      final score = off + (record.hasSynced ? 0 : 100);
      if (score < bestScore) {
        best = record;
        bestScore = score;
      }
    }
    return best;
  }

  /// Equal once case, spacing, punctuation and any featuring or producer
  /// credit are set aside: "Magic" matches "Magic (feat. JULIE)", but "Air"
  /// does not match "Air (English Ver.)".
  static bool _sameTitle(String a, String b) {
    final x = _key(a.replaceAll(_credit, ''));
    return x.isNotEmpty && x == _key(b.replaceAll(_credit, ''));
  }

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
        await response.drain<void>();
        throw LrclibUnavailable('HTTP ${response.statusCode}');
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
