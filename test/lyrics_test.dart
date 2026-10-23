import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:custom_music_player/core/lyrics/lyrics.dart';
import 'package:custom_music_player/core/models/track.dart';
import 'package:custom_music_player/platform/lrclib_client.dart';
import 'package:custom_music_player/platform/lyrics_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers from a script instead of lrclib.net, counting the lookups.
class FakeLrclib extends LrclibClient {
  LrclibRecord? answer;
  bool unavailable = false;
  int lookups = 0;

  @override
  Future<LrclibRecord?> lookup({
    required String title,
    required String artist,
    required String album,
    Duration? duration,
  }) async {
    lookups++;
    if (unavailable) throw const LrclibUnavailable('offline');
    return answer;
  }
}

/// Answers given in turn, one per request, the last one repeating.
class Answers {
  final List<Object?> inTurn;

  const Answers(this.inTurn);
}

/// The real lookup, with lrclib.net's two endpoints answering from a
/// script: a value, null for "404 not found", [LrclibUnavailable], or
/// [Answers] for a sequence of those. Retries do not wait.
class ScriptedLrclib extends LrclibClient {
  final Object? exact;
  final Object? search;
  final asked = <String>[];
  final waits = <Duration>[];

  /// Requests in flight now, and the most there ever were at once.
  var _inFlight = 0;
  var mostAtOnce = 0;

  ScriptedLrclib({this.exact, this.search}) : super(pause: (_) async {});

  @override
  Future<Object?> getJson(String path, Map<String, String> query) async {
    final turn = asked.where((p) => p == path).length;
    asked.add(path);
    _inFlight++;
    if (_inFlight > mostAtOnce) mostAtOnce = _inFlight;
    try {
      // Long enough that overlapping lookups would be seen to overlap.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      var answer = path == '/api/get' ? exact : search;
      if (answer is Answers) {
        answer = answer.inTurn[turn.clamp(0, answer.inTurn.length - 1)];
      }
      if (answer is LrclibUnavailable) throw answer;
      return answer;
    } finally {
      _inFlight--;
    }
  }
}

/// A minimal m4a whose only tag is `©lyr`, which is all the lyrics reader
/// looks at.
Uint8List m4aWithLyrics(String lyrics) {
  List<int> u32(int v) => [
    v >> 24 & 0xff,
    v >> 16 & 0xff,
    v >> 8 & 0xff,
    v & 0xff,
  ];
  List<int> box(String type, List<int> payload) => [
    ...u32(8 + payload.length),
    ...latin1.encode(type),
    ...payload,
  ];
  final data = box('data', [...u32(1), ...u32(0), ...utf8.encode(lyrics)]);
  final ilst = box('ilst', box('©lyr', data));
  final meta = box('meta', [
    0,
    0,
    0,
    0,
    ...box('hdlr', List.filled(25, 0)),
    ...ilst,
  ]);
  return Uint8List.fromList([
    ...box('ftyp', ascii.encode('M4A mp42isom')),
    ...box('moov', box('udta', meta)),
    ...box('mdat', List.filled(16, 0)),
  ]);
}

void main() {
  group('Lyrics.parse', () {
    test('reads timed LRC lines in time order', () {
      final lyrics = Lyrics.parse(
        '[ar:NAYEON]\n'
        '[ti:ABCD]\n'
        '[00:20.50] Second\n'
        '[00:05.10]First\n'
        '[01:02.003] Third\n',
        source: LyricsSource.lrclib,
      )!;

      expect(lyrics.isSynced, isTrue);
      expect(lyrics.lines.map((l) => l.text), ['First', 'Second', 'Third']);
      expect(lyrics.lines.map((l) => l.time), [
        const Duration(seconds: 5, milliseconds: 100),
        const Duration(seconds: 20, milliseconds: 500),
        const Duration(minutes: 1, seconds: 2, milliseconds: 3),
      ]);
    });

    test('a line with several timestamps repeats at each', () {
      final lyrics = Lyrics.parse(
        '[00:10.00][00:30.00]Chorus\n[00:20.00]Verse',
        source: LyricsSource.file,
      )!;

      expect(lyrics.lines.map((l) => l.text), ['Chorus', 'Verse', 'Chorus']);
    });

    test('applies the offset tag and drops per-word timings', () {
      final lyrics = Lyrics.parse(
        '[offset:+500]\n[00:10.00]<00:10.00>Hello <00:10.50>world',
        source: LyricsSource.file,
      )!;

      expect(lyrics.lines.single.text, 'Hello world');
      expect(lyrics.lines.single.time, const Duration(milliseconds: 9500));
    });

    test('keeps one gap between verses, none at the start', () {
      final lyrics = Lyrics.parse(
        '[00:00.00]\n[00:05.00]One\n[00:09.00]\n[00:10.00]\n[00:12.00]Two',
        source: LyricsSource.lrclib,
      )!;

      expect(lyrics.lines.map((l) => l.text), ['One', '', 'Two']);
    });

    test('plain text keeps single stanza breaks', () {
      final lyrics = Lyrics.parse(
        '\r\nLine one\r\nLine two\r\n\r\n\r\nLine three\r\n\r\n',
        source: LyricsSource.embedded,
      )!;

      expect(lyrics.isSynced, isFalse);
      expect(lyrics.lines.map((l) => l.text), [
        'Line one',
        'Line two',
        '',
        'Line three',
      ]);
      expect(lyrics.lineAt(const Duration(seconds: 30)), -1);
    });

    test('nothing but blank lines is no lyrics', () {
      expect(Lyrics.parse(' \n\n ', source: LyricsSource.file), isNull);
      expect(Lyrics.parse('[00:01.00]\n', source: LyricsSource.file), isNull);
    });

    test('lineAt finds the line being sung', () {
      final lyrics = Lyrics.parse(
        '[00:05.00]a\n[00:10.00]b\n[00:15.00]c',
        source: LyricsSource.lrclib,
      )!;

      expect(lyrics.lineAt(const Duration(seconds: 2)), -1);
      expect(lyrics.lineAt(const Duration(seconds: 5)), 0);
      expect(lyrics.lineAt(const Duration(seconds: 12)), 1);
      expect(lyrics.lineAt(const Duration(minutes: 3)), 2);
    });
  });

  group('LrclibClient.lookup', () {
    const down = LrclibUnavailable('HTTP 503');
    final synced = {
      'trackName': 'Psychic Lover',
      'artistName': 'ITZY',
      'duration': 164.0,
      'plainLyrics': 'I can be your psychic lover',
      'syncedLyrics': '[00:10.00]I can be your psychic lover',
    };

    Future<LrclibRecord?> lookup(LrclibClient client) => client.lookup(
      title: 'Psychic Lover',
      artist: 'ITZY',
      album: 'KILL MY DOUBT - EP',
      duration: const Duration(milliseconds: 164513),
    );

    test('timed lyrics from the exact lookup need no search', () async {
      final client = ScriptedLrclib(exact: synced);

      expect((await lookup(client))?.hasSynced, isTrue);
      expect(client.asked, ['/api/get']);
    });

    test('the search finds what the exact lookup misses', () async {
      final client = ScriptedLrclib(exact: null, search: [synced]);

      expect((await lookup(client))?.hasSynced, isTrue);
    });

    test('nothing in either answer is a real miss', () async {
      final client = ScriptedLrclib(exact: null, search: const []);

      expect(await lookup(client), isNull);
    });

    test(
      'a failed search is no answer, even after the exact lookup missed',
      () async {
        // What hid Psychic Lover's lyrics on the Mac: the exact lookup never
        // finds it, and one failed search was taken as "it has none".
        final client = ScriptedLrclib(exact: null, search: down);

        await expectLater(lookup(client), throwsA(isA<LrclibUnavailable>()));
      },
    );

    test('a failed search keeps what the exact lookup found', () async {
      final client = ScriptedLrclib(
        exact: {...synced, 'syncedLyrics': null},
        search: down,
      );

      expect((await lookup(client))?.plain, 'I can be your psychic lover');
    });

    test('both failing is no answer', () async {
      final client = ScriptedLrclib(exact: down, search: down);

      await expectLater(lookup(client), throwsA(isA<LrclibUnavailable>()));
    });

    test('a busy server is asked again until it answers', () async {
      // What lrclib.net does: a few 503s, each asking for a second's wait.
      const busy = LrclibUnavailable(
        'HTTP 503',
        retryAfter: Duration(seconds: 1),
      );
      final client = ScriptedLrclib(
        exact: const Answers([busy, busy, busy, null]),
        search: Answers([
          busy,
          [synced],
        ]),
      );

      expect((await lookup(client))?.hasSynced, isTrue);
      expect(client.asked.where((p) => p == '/api/get'), hasLength(4));
    });

    test('gives up after a few tries', () async {
      final client = ScriptedLrclib(exact: down, search: down);

      await expectLater(lookup(client), throwsA(isA<LrclibUnavailable>()));
      expect(client.asked, hasLength(10));
    });

    test(
      'plain lyrics while the search failed are only part of the answer',
      () async {
        final client = ScriptedLrclib(
          exact: {...synced, 'syncedLyrics': null},
          search: down,
        );

        expect((await lookup(client))?.partial, isTrue);
      },
    );

    test(
      'timed lyrics from the search stand even if the exact one failed',
      () async {
        final client = ScriptedLrclib(exact: down, search: [synced]);

        final record = await lookup(client);
        expect(record?.hasSynced, isTrue);
        expect(record?.partial, isFalse);
      },
    );

    test('a failed exact lookup and an empty search is no answer', () async {
      // The exact lookup finds songs the search's strict matching skips.
      final client = ScriptedLrclib(exact: down, search: const []);

      await expectLater(lookup(client), throwsA(isA<LrclibUnavailable>()));
    });

    test('lookups go out one at a time', () async {
      final client = ScriptedLrclib(exact: null, search: [synced]);

      await Future.wait([lookup(client), lookup(client), lookup(client)]);
      expect(client.mostAtOnce, 1);
    });
  });

  group('LrclibRecord.fromJson', () {
    test('lyrics flagged instrumental are still lyrics', () {
      // How a dozen of lrclib.net's DALLA DALLA entries look.
      final record = LrclibRecord.fromJson({
        'instrumental': true,
        'plainLyrics': 'DALLA DALLA',
        'syncedLyrics': '[00:01.00]DALLA DALLA',
      });

      expect(record?.instrumental, isFalse);
      expect(record?.hasSynced, isTrue);
    });

    test('instrumental with no lyrics is instrumental', () {
      final record = LrclibRecord.fromJson({'instrumental': true});

      expect(record?.instrumental, isTrue);
    });
  });

  group('LrclibClient.bestMatch', () {
    Map<String, Object?> result(
      String title,
      String artist,
      num duration, {
      bool synced = true,
    }) => {
      'trackName': title,
      'artistName': artist,
      'duration': duration,
      'plainLyrics': 'plain $title',
      'syncedLyrics': synced ? '[00:01.00]$title' : null,
    };

    test('never takes another song of the same length', () {
      // What a search for YEJI's "258" really returns.
      final match = LrclibClient.bestMatch(
        [
          result('Dirty Work', 'YEJI', 180),
          result('Air (English Ver.)', 'YEJI', 194),
        ],
        title: '258',
        artist: 'YEJI',
        duration: const Duration(milliseconds: 193097),
      );

      expect(match, isNull);
    });

    test('a different version is not the same song', () {
      final match = LrclibClient.bestMatch(
        [result('Air (English Ver.)', 'YEJI', 194)],
        title: 'Air',
        artist: 'YEJI',
        duration: const Duration(seconds: 194),
      );

      expect(match, isNull);
    });

    test('ignores featuring and producer credits', () {
      final match = LrclibClient.bestMatch(
        [result('HalliGalli', 'NAYEON', 187)],
        title: 'HalliGalli (Prod. by LEE CHANHYUK of AKMU)',
        artist: 'NAYEON',
        duration: const Duration(milliseconds: 187431),
      );

      expect(match?.synced, '[00:01.00]HalliGalli');
    });

    test('matches the lead artist of a shared credit', () {
      final match = LrclibClient.bestMatch(
        [result('Heaven', 'NAYEON, SAM KIM', 187)],
        title: 'Heaven',
        artist: 'NAYEON & SAM KIM',
        duration: const Duration(milliseconds: 186827),
      );

      expect(match, isNotNull);
    });

    test('prefers timed lyrics, then the closest length', () {
      final match = LrclibClient.bestMatch(
        [
          result('CAKE', 'ITZY', 199, synced: false),
          result('Cake', 'ITZY', 200.5),
          result('CAKE', 'ITZY', 199.4),
          result('CAKE', 'ITZY', 210),
        ],
        title: 'CAKE',
        artist: 'ITZY',
        duration: const Duration(milliseconds: 198948),
      );

      expect(match?.synced, '[00:01.00]CAKE');
      expect(match?.plain, 'plain CAKE');
    });

    test('prefers lyrics nobody flagged instrumental', () {
      final match = LrclibClient.bestMatch(
        [
          {...result('DALLA DALLA', 'ITZY', 200), 'instrumental': true},
          {...result('DALLA DALLA', 'ITZY', 201), 'syncedLyrics': '[00:01]ok'},
        ],
        title: 'DALLA DALLA',
        artist: 'ITZY',
        duration: const Duration(milliseconds: 199923),
      );

      expect(match?.synced, '[00:01]ok');
    });

    test('takes lyrics over a bare instrumental flag', () {
      final match = LrclibClient.bestMatch(
        [
          {
            'trackName': 'DALLA DALLA',
            'artistName': 'ITZY',
            'duration': 200,
            'instrumental': true,
          },
          result('DALLA DALLA', 'ITZY', 200, synced: false),
        ],
        title: 'DALLA DALLA',
        artist: 'ITZY',
        duration: const Duration(seconds: 200),
      );

      expect(match?.plain, 'plain DALLA DALLA');
    });

    test('a title without its leading "The" still matches', () {
      final match = LrclibClient.bestMatch(
        [result('The Feels', 'TWICE', 198.07)],
        title: 'Feels',
        artist: 'TWICE',
        duration: const Duration(milliseconds: 198112),
      );

      expect(match, isNotNull);
    });

    test('curly and straight apostrophes match', () {
      final match = LrclibClient.bestMatch(
        [result("Can't Slow Me, No", 'YEJI', 179)],
        title: 'Can’t Slow Me, No',
        artist: 'YEJI',
        duration: const Duration(milliseconds: 178631),
      );

      expect(match, isNotNull);
    });
  });

  group('LyricsStore', () {
    late Directory tmp;
    late Directory support;
    late FakeLrclib lrclib;
    var now = DateTime(2026, 10, 21);

    LyricsStore store() => LyricsStore(
      lrclib: lrclib,
      cacheRoot: () async => support,
      now: () => now,
    );

    Future<Track> song(String name, {Uint8List? bytes}) async {
      final file = File('${tmp.path}/$name.m4a');
      await file.writeAsBytes(bytes ?? Uint8List(0));
      return Track(
        path: file.path,
        filePath: file.path,
        title: name,
        artist: 'ITZY',
        album: 'KILL MY DOUBT - EP',
        albumArtist: 'ITZY',
        duration: const Duration(seconds: 199),
      );
    }

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('lyrics');
      support = await Directory('${tmp.path}/support').create();
      lrclib = FakeLrclib();
      now = DateTime(2026, 10, 21);
    });

    tearDown(() => tmp.delete(recursive: true));

    Future<Lyrics?> lyricsOf(LyricsStore s, Track t) async =>
        (await s.forTrack(t)).lyrics;

    test('a timed .lrc beside the song wins without asking online', () async {
      final track = await song('BET ON ME');
      await File('${tmp.path}/BET ON ME.lrc')
          .writeAsString('﻿[00:01.00]From the file');

      final lyrics = await lyricsOf(store(), track);

      expect(lyrics?.source, LyricsSource.file);
      expect(lyrics?.lines.single.text, 'From the file');
      expect(lrclib.lookups, 0);
    });

    test('plain embedded lyrics give way to timed ones online', () async {
      final track = await song('CAKE', bytes: m4aWithLyrics('Plain line'));
      lrclib.answer = const LrclibRecord(synced: '[00:02.00]Timed line');

      final lyrics = await lyricsOf(store(), track);

      expect(lyrics?.source, LyricsSource.lrclib);
      expect(lyrics?.isSynced, isTrue);
    });

    test('plain embedded lyrics stay when nothing timed is online', () async {
      final track = await song('CAKE', bytes: m4aWithLyrics('Plain line'));
      lrclib.answer = const LrclibRecord(plain: 'Their plain line');

      final lyrics = await lyricsOf(store(), track);

      expect(lyrics?.source, LyricsSource.embedded);
      expect(lyrics?.lines.single.text, 'Plain line');
    });

    test('online answers are kept on the device', () async {
      final track = await song('Bratty');
      lrclib.answer = const LrclibRecord(synced: '[00:02.00]Kept');

      await lyricsOf(store(), track);
      lrclib.answer = null;
      // A fresh store, as after a restart: only the files remain.
      final again = await lyricsOf(store(), track);

      expect(again?.lines.single.text, 'Kept');
      expect(lrclib.lookups, 1);
    });

    test('instrumental is remembered as such', () async {
      final track = await song('Intro');
      lrclib.answer = const LrclibRecord(instrumental: true);

      await lyricsOf(store(), track);
      final again = await lyricsOf(store(), track);

      expect(again?.instrumental, isTrue);
      expect(lrclib.lookups, 1);
    });

    test('a miss is asked again only after a few days', () async {
      final track = await song('Kill Shot');

      expect(await lyricsOf(store(), track), isNull);
      now = now.add(const Duration(days: 1));
      expect(await lyricsOf(store(), track), isNull);
      expect(lrclib.lookups, 1);

      now = now.add(const Duration(days: 3));
      lrclib.answer = const LrclibRecord(plain: 'Added since');
      expect(
        (await lyricsOf(store(), track))?.lines.single.text,
        'Added since',
      );
      expect(lrclib.lookups, 2);
    });

    test('a failed lookup is held briefly, then asked again', () async {
      final track = await song('Psychic Lover');
      final shared = store();
      lrclib.unavailable = true;

      expect(await lyricsOf(shared, track), isNull);
      lrclib.unavailable = false;
      lrclib.answer = const LrclibRecord(synced: '[00:01.00]Back online');

      // Showing the lyrics again at once does not ask again...
      expect(await lyricsOf(shared, track), isNull);
      expect(lrclib.lookups, 1);

      // ...a little later it does.
      now = now.add(const Duration(seconds: 20));
      expect((await lyricsOf(shared, track))?.lines.single.text, 'Back online');
      expect(lrclib.lookups, 2);
    });

    test('a retry asks again at once', () async {
      final track = await song('Psychic Lover');
      final shared = store();
      lrclib.unavailable = true;
      await shared.forTrack(track);

      lrclib.unavailable = false;
      lrclib.answer = const LrclibRecord(synced: '[00:01.00]Back online');
      final again = await shared.forTrack(track, retry: true);
      expect(again.lyrics?.lines.single.text, 'Back online');

      // A retry of a lookup that worked gives back what it found.
      await shared.forTrack(track, retry: true);
      expect(lrclib.lookups, 2);
    });

    test('the same track is looked up once per run', () async {
      final track = await song('None of My Business');
      final shared = store();
      lrclib.answer = const LrclibRecord(plain: 'Once');

      await Future.wait([shared.forTrack(track), shared.forTrack(track)]);
      await lyricsOf(shared, track);

      expect(lrclib.lookups, 1);
    });

    test('says when lrclib.net could not be asked', () async {
      final track = await song('Feels');
      lrclib.unavailable = true;

      final lookup = await store().forTrack(track);

      expect(lookup.lyrics, isNull);
      expect(lookup.unavailable, isTrue);
    });

    test('a real miss is not "unavailable"', () async {
      final track = await song('Kill Shot');

      expect((await store().forTrack(track)).unavailable, isFalse);
    });

    test('part of an answer is shown but not kept', () async {
      final track = await song('Bad Girls R Us');
      lrclib.answer = const LrclibRecord(plain: 'For now', partial: true);

      final first = await store().forTrack(track);
      expect(first.lyrics?.lines.single.text, 'For now');
      expect(first.unavailable, isTrue);

      lrclib.answer = const LrclibRecord(synced: '[00:01.00]Timed at last');
      final again = await lyricsOf(store(), track);
      expect(again?.isSynced, isTrue);
      expect(lrclib.lookups, 2);
    });

    test('kept plain lyrics are checked again for a timed version', () async {
      final track = await song('UNTOUCHABLE');
      lrclib.answer = const LrclibRecord(plain: 'Plain');
      await lyricsOf(store(), track);

      now = now.add(const Duration(days: 1));
      expect((await lyricsOf(store(), track))?.isSynced, isFalse);
      expect(lrclib.lookups, 1);

      now = now.add(const Duration(days: 3));
      lrclib.answer = const LrclibRecord(synced: '[00:01.00]Timed');
      expect((await lyricsOf(store(), track))?.isSynced, isTrue);
      expect(lrclib.lookups, 2);
    });

    test('kept plain lyrics stay when the check cannot be made', () async {
      final track = await song('UNTOUCHABLE');
      lrclib.answer = const LrclibRecord(plain: 'Plain');
      await lyricsOf(store(), track);

      now = now.add(const Duration(days: 4));
      lrclib.unavailable = true;
      expect((await lyricsOf(store(), track))?.lines.single.text, 'Plain');
    });

    test('kept timed lyrics are never asked about again', () async {
      final track = await song('CAKE');
      lrclib.answer = const LrclibRecord(synced: '[00:01.00]Timed');
      await lyricsOf(store(), track);

      now = now.add(const Duration(days: 365));
      await lyricsOf(store(), track);
      expect(lrclib.lookups, 1);
    });

    test('1.4.x answers keep timed lyrics and re-check the rest', () async {
      final timed = await song('CAKE');
      final bare = await song('DALLA DALLA');
      lrclib.answer = const LrclibRecord(synced: '[00:01.00]Timed');
      await lyricsOf(store(), timed);
      lrclib.answer = const LrclibRecord(instrumental: true);
      await lyricsOf(store(), bare);
      // Rewrite both as version 2 left them.
      await for (final f in Directory('${support.path}/lyrics').list()) {
        final file = f as File;
        final json = jsonDecode(await file.readAsString()) as Map;
        await file.writeAsString(jsonEncode({...json, 'version': 2}));
      }

      lrclib.answer = const LrclibRecord(synced: '[00:01.00]DALLA DALLA');
      expect((await lyricsOf(store(), timed))?.lines.single.text, 'Timed');
      expect((await lyricsOf(store(), bare))?.lines.single.text, 'DALLA DALLA');
      expect(lrclib.lookups, 3);
    });

    test('a kept answer flagged instrumental with lyrics shows them', () async {
      // How 1.4.1 saved DALLA DALLA: the flag and the lyrics side by side.
      final track = await song('DALLA DALLA');
      lrclib.answer = LrclibRecord.fromJson({
        'syncedLyrics': '[00:01.00]DALLA DALLA',
      });
      await lyricsOf(store(), track);
      final file =
          (await Directory('${support.path}/lyrics').list().first) as File;
      final json = jsonDecode(await file.readAsString()) as Map;
      await file.writeAsString(jsonEncode({...json, 'instrumental': true}));

      final again = await lyricsOf(store(), track);
      expect(again?.instrumental, isFalse);
      expect(again?.lines.single.text, 'DALLA DALLA');
    });
  });
}
