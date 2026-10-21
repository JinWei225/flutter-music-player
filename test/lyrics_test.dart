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

/// The real lookup, with lrclib.net's two endpoints answering from a
/// script: a value, null for "404 not found", or [LrclibUnavailable].
class ScriptedLrclib extends LrclibClient {
  final Object? exact;
  final Object? search;
  final asked = <String>[];

  ScriptedLrclib({this.exact, this.search});

  @override
  Future<Object?> getJson(String path, Map<String, String> query) async {
    asked.add(path);
    final answer = path == '/api/get' ? exact : search;
    if (answer is LrclibUnavailable) throw answer;
    return answer;
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

    test('a timed .lrc beside the song wins without asking online', () async {
      final track = await song('BET ON ME');
      await File('${tmp.path}/BET ON ME.lrc')
          .writeAsString('﻿[00:01.00]From the file');

      final lyrics = await store().forTrack(track);

      expect(lyrics?.source, LyricsSource.file);
      expect(lyrics?.lines.single.text, 'From the file');
      expect(lrclib.lookups, 0);
    });

    test('plain embedded lyrics give way to timed ones online', () async {
      final track = await song('CAKE', bytes: m4aWithLyrics('Plain line'));
      lrclib.answer = const LrclibRecord(synced: '[00:02.00]Timed line');

      final lyrics = await store().forTrack(track);

      expect(lyrics?.source, LyricsSource.lrclib);
      expect(lyrics?.isSynced, isTrue);
    });

    test('plain embedded lyrics stay when nothing timed is online', () async {
      final track = await song('CAKE', bytes: m4aWithLyrics('Plain line'));
      lrclib.answer = const LrclibRecord(plain: 'Their plain line');

      final lyrics = await store().forTrack(track);

      expect(lyrics?.source, LyricsSource.embedded);
      expect(lyrics?.lines.single.text, 'Plain line');
    });

    test('online answers are kept on the device', () async {
      final track = await song('Bratty');
      lrclib.answer = const LrclibRecord(synced: '[00:02.00]Kept');

      await store().forTrack(track);
      lrclib.answer = null;
      // A fresh store, as after a restart: only the files remain.
      final again = await store().forTrack(track);

      expect(again?.lines.single.text, 'Kept');
      expect(lrclib.lookups, 1);
    });

    test('instrumental is remembered as such', () async {
      final track = await song('Intro');
      lrclib.answer = const LrclibRecord(instrumental: true);

      await store().forTrack(track);
      final again = await store().forTrack(track);

      expect(again?.instrumental, isTrue);
      expect(lrclib.lookups, 1);
    });

    test('a miss is asked again only after a few days', () async {
      final track = await song('Kill Shot');

      expect(await store().forTrack(track), isNull);
      now = now.add(const Duration(days: 1));
      expect(await store().forTrack(track), isNull);
      expect(lrclib.lookups, 1);

      now = now.add(const Duration(days: 3));
      lrclib.answer = const LrclibRecord(plain: 'Added since');
      expect((await store().forTrack(track))?.lines.single.text, 'Added since');
      expect(lrclib.lookups, 2);
    });

    test('a failed lookup is not remembered', () async {
      final track = await song('Psychic Lover');
      final shared = store();
      lrclib.unavailable = true;

      expect(await shared.forTrack(track), isNull);

      lrclib.unavailable = false;
      lrclib.answer = const LrclibRecord(synced: '[00:01.00]Back online');
      expect((await shared.forTrack(track))?.lines.single.text, 'Back online');
      expect(lrclib.lookups, 2);
    });

    test('the same track is looked up once per run', () async {
      final track = await song('None of My Business');
      final shared = store();
      lrclib.answer = const LrclibRecord(plain: 'Once');

      await Future.wait([shared.forTrack(track), shared.forTrack(track)]);
      await shared.forTrack(track);

      expect(lrclib.lookups, 1);
    });
  });
}
