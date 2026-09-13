import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:custom_music_player/core/metadata/mp4_tags.dart';
import 'package:custom_music_player/core/metadata/tag_repair.dart';
import 'package:flutter_test/flutter_test.dart';

List<int> u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

Uint8List box(String type, List<int> payload) => Uint8List.fromList(
    [...u32(8 + payload.length), ...latin1.encode(type), ...payload]);

Uint8List textAtom(String key, String value) =>
    box(key, box('data', [...u32(1), ...u32(0), ...utf8.encode(value)]));

Uint8List intAtom(String key, int value) =>
    box(key, box('data', [...u32(21), ...u32(0), ...u32(value)]));

Uint8List m4a(List<Uint8List> atoms) {
  final ilst = box('ilst', atoms.expand((a) => a).toList());
  final meta = box('meta', [0, 0, 0, 0, ...box('hdlr', List.filled(25, 0)), ...ilst]);
  final mvhd = box('mvhd', [
    0, 0, 0, 0, ...List.filled(8, 0), ...u32(1000), ...u32(9000),
    ...List.filled(80, 0),
  ]);
  return Uint8List.fromList([
    ...box('ftyp', ascii.encode('M4A mp42isom')),
    ...box('moov', [...mvhd, ...box('udta', meta)]),
    ...box('mdat', List.filled(64, 0xaa)),
  ]);
}

/// The store IDs the broken purchases carry.
final storeIds = [intAtom('atID', 77), intAtom('plID', 500)];
final date = textAtom('©day', '2023-07-31T07:00:00Z');

void main() {
  late Directory root;
  final sep = Platform.pathSeparator;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('tagrepair');
  });

  tearDown(() => root.delete(recursive: true));

  Future<File> put(String relative, Uint8List bytes) async {
    final f = File('${root.path}$sep${relative.replaceAll('/', sep)}');
    await f.create(recursive: true);
    await f.writeAsBytes(bytes);
    return f;
  }

  test('a nameless track is completed from its album-mates and filename',
      () async {
    final cake = await put('ITZY/KILL MY DOUBT - EP/02 CAKE.m4a',
        m4a([...storeIds, date]));
    await put(
      'ITZY/KILL MY DOUBT - EP/04 Bratty.m4a',
      m4a([
        textAtom('©nam', 'Bratty'),
        textAtom('©ART', 'ITZY'),
        textAtom('©alb', 'KILL MY DOUBT - EP'),
        textAtom('aART', 'ITZY'),
        textAtom('©gen', 'K-Pop'),
        ...storeIds,
      ]),
    );

    final repairs = await TagRepairer.planTree(root);
    expect(repairs.map((r) => r.fileName), ['02 CAKE.m4a']);
    final r = repairs.single;
    expect(r.filled, [
      'title ← filename',
      'artist ← album-mates',
      'album ← album-mates',
      'album artist ← album-mates',
      'genre ← album-mates',
      'track ← filename',
    ]);

    await r.apply();
    final tags = (await Mp4TagParser.parse(cake))!;
    expect(tags.title, 'CAKE');
    expect(tags.artist, 'ITZY');
    expect(tags.album, 'KILL MY DOUBT - EP');
    expect(tags.albumArtist, 'ITZY');
    expect(tags.genre, 'K-Pop');
    expect(tags.trackNumber, 2);
    expect(tags.rawDate, '2023-07-31T07:00:00Z', reason: 'date kept verbatim');
    expect(tags.storeAlbumId, 500);
    expect(tags.namesFromSortAtoms, isFalse);

    // Second pass: nothing left to do.
    expect(await TagRepairer.planTree(root), isEmpty);
  });

  test('falls back to the folder names with no album-mate to ask', () async {
    await put('ITZY/KILL MY DOUBT - EP/03 None of My Business.m4a',
        m4a([...storeIds, date]));

    final r = (await TagRepairer.planTree(root)).single;
    expect(r.edit.title, 'None of My Business');
    expect(r.edit.artist, 'ITZY');
    expect(r.edit.album, 'KILL MY DOUBT - EP');
    expect(r.edit.trackNumber, 3);
    expect(r.filled, contains('artist ← folder'));
    expect(r.filled, contains('album ← folder'));
  });

  test('a sort-atoms-only file gets real name atoms', () async {
    final f = await put(
      'NAYEON/NA/01 ABCD.m4a',
      m4a([
        textAtom('sonm', 'ABCD'),
        textAtom('soar', 'NAYEON'),
        textAtom('soal', 'NA'),
      ]),
    );

    final r = (await TagRepairer.planTree(root)).single;
    expect(r.filled, ['names ← sort atoms', 'track ← filename']);
    await r.apply();

    final tags = (await Mp4TagParser.parse(f))!;
    expect(tags.namesFromSortAtoms, isFalse);
    expect(tags.title, 'ABCD');
    expect(tags.artist, 'NAYEON');
    expect(tags.trackNumber, 1);
  });

  test('never touches a file that has its names', () async {
    await put(
      'X/Y/01 Fine.m4a',
      m4a([
        textAtom('©nam', 'Fine'),
        textAtom('©ART', 'Someone'),
        textAtom('©alb', 'Something'),
      ]),
    );
    expect(await TagRepairer.planTree(root), isEmpty);
  });

  test('never overwrites a field that is present', () async {
    await put(
      'Folder Artist/Folder Album/01 Song.m4a',
      m4a([textAtom('©ART', 'Real Artist'), ...storeIds]),
    );
    final r = (await TagRepairer.planTree(root)).single;
    expect(r.edit.artist, 'Real Artist');
    expect(r.edit.album, 'Folder Album');
    expect(r.filled, isNot(contains('artist ← folder')));
  });

  test('skips downloads still in flight', () async {
    await put('A/B/01 Partial.m4a.tmp', m4a([]));
    await put('A/B/.02 Hidden.m4a', m4a([]));
    expect(await TagRepairer.planTree(root), isEmpty);
  });
}
