import 'dart:async';
import 'dart:io';

import 'package:custom_music_player/core/library/library_model.dart';
import 'package:custom_music_player/core/models/track.dart';
import 'package:custom_music_player/platform/library_source.dart';
import 'package:custom_music_player/platform/spotlight_index.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSource implements LibrarySource {
  List<Track> tracks;
  FakeSource(this.tracks);

  @override
  String get description => 'fake';

  @override
  Future<List<Track>> loadTracks() async => tracks;
}

Track t(String title, String album, String artist, {int? n}) => Track(
  path: '/m/$album/$title.m4a',
  title: title,
  artist: artist,
  album: album,
  albumArtist: artist,
  trackNumber: n,
  duration: const Duration(minutes: 3),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jinwei.custom_music_player/spotlight');

  late Directory dir;
  late List<MethodCall> calls;
  late FakeSource source;
  late LibraryModel library;
  late SpotlightIndex index;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('spotlight_test');
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return call.method == 'isAvailable' ? true : null;
        });
    source = FakeSource([
      t('One', 'NA', 'NAYEON', n: 1),
      t('Two', 'NA', 'NAYEON', n: 2),
      t('Ready', 'Ready to Be', 'TWICE', n: 1),
    ]);
    library = LibraryModel(source);
    index = SpotlightIndex(
      library,
      stateFile: () async => File('${dir.path}/spotlight.json'),
      coverFor: (album) async =>
          album.name == 'NA' ? Uint8List.fromList([1, 2, 3]) : null,
    );
    await library.load();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await dir.delete(recursive: true);
  });

  List<Map> indexed() => [
    for (final c in calls)
      if (c.method == 'index') ...(c.arguments as List).cast<Map>(),
  ];
  List<String> deleted() => [
    for (final c in calls)
      if (c.method == 'delete') ...(c.arguments as List).cast<String>(),
  ];

  test('the first run clears old items and sends every album', () async {
    await index.sync();

    expect(
      calls.map((c) => c.method),
      containsAllInOrder(['deleteAll', 'index']),
    );
    final items = indexed();
    expect(
      items.map((i) => i['title']),
      unorderedEquals(['NA', 'Ready to Be']),
    );

    final na = items.firstWhere((i) => i['title'] == 'NA');
    expect(na['id'], 'mewsic://album?name=NA&artist=NAYEON');
    expect(na['artist'], 'NAYEON');
    expect(na['songs'], 2);
    expect(na['seconds'], 360);
    expect(na['cover'], [1, 2, 3]);
    expect(na.containsKey('year'), isFalse);

    final ready = items.firstWhere((i) => i['title'] == 'Ready to Be');
    expect(ready.containsKey('cover'), isFalse);
  });

  test('an unchanged library sends nothing the second time', () async {
    await index.sync();
    calls.clear();

    await index.sync();

    expect(calls.map((c) => c.method), ['isAvailable']);
  });

  test('a changed album is sent again and a removed one deleted', () async {
    await index.sync();
    calls.clear();

    source.tracks = [
      t('One', 'NA', 'NAYEON', n: 1),
      t('Two', 'NA', 'NAYEON', n: 2),
      t('Three', 'NA', 'NAYEON', n: 3),
    ];
    await library.load();
    await index.sync();

    expect(deleted(), ['mewsic://album?name=Ready+to+Be&artist=TWICE']);
    expect(indexed().single['songs'], 3);
    expect(calls.map((c) => c.method), isNot(contains('deleteAll')));
  });

  test('nothing is deleted while the library has not been scanned', () async {
    final unscanned = LibraryModel(source);
    final early = SpotlightIndex(
      unscanned,
      settle: Duration.zero,
      stateFile: () async => File('${dir.path}/early.json'),
      coverFor: (_) async => null,
    )..start();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(calls, isEmpty);
    early.dispose();
  });

  test('a call made mid-sync runs again once it finishes', () async {
    // Hold the first pass at its first step, as a slow cover read would.
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method != 'isAvailable') return null;
          await gate.future;
          return true;
        });

    final first = index.sync();
    await Future<void>.delayed(Duration.zero);
    final second = index.sync();
    gate.complete();
    await Future.wait([first, second]);

    // Two passes, the second finding nothing left to send.
    expect(calls.where((c) => c.method == 'isAvailable'), hasLength(2));
    expect(indexed().map((i) => i['title']), ['NA', 'Ready to Be']);
  });
}
