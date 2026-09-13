import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:custom_music_player/core/metadata/mp4_tags.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a minimal MP4 box: size + type + payload.
Uint8List box(String type, List<int> payload) {
  final b = BytesBuilder();
  b.add(_u32(8 + payload.length));
  b.add(ascii.encode(type.padRight(4).substring(0, 4)));
  b.add(payload);
  return b.toBytes();
}

/// An `ilst` entry wrapping raw bytes with an explicit well-known type
/// (13 = JPEG, 14 = PNG), which is how cover art is stored.
Uint8List binaryAtom(String key, int wellKnownType, List<int> payload) {
  final data = BytesBuilder()
    ..add(_u32(wellKnownType))
    ..add(_u32(0))
    ..add(payload);
  final inner = box('data', data.toBytes());
  final b = BytesBuilder()
    ..add(_u32(8 + inner.length))
    ..add(ascii.encode(key.padRight(4).substring(0, 4)))
    ..add(inner);
  return b.toBytes();
}

/// An `ilst` entry holding a big-endian integer, as the store IDs are.
Uint8List intAtom(String key, int value, {int bytes = 4}) {
  final payload = [for (var i = bytes - 1; i >= 0; i--) (value >> (8 * i)) & 0xff];
  // 21 == signed integer in iTunes' well-known types.
  return binaryAtom(key, 21, payload);
}

/// An `ilst` entry: the 4cc wrapping a `data` box of UTF-8 text.
Uint8List textAtom(String key, String value) {
  final data = BytesBuilder()
    ..add(_u32(1)) // well-known type 1 == UTF-8
    ..add(_u32(0)) // locale
    ..add(utf8.encode(value));
  final keyBytes = key.codeUnits.length == 4
      ? Uint8List.fromList(key.codeUnits)
      : Uint8List.fromList(ascii.encode(key.padRight(4).substring(0, 4)));
  final inner = box('data', data.toBytes());
  final b = BytesBuilder()
    ..add(_u32(8 + inner.length))
    ..add(keyBytes)
    ..add(inner);
  return b.toBytes();
}

List<int> _u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

/// Assembles a tiny but structurally valid m4a carrying [atoms].
Uint8List buildM4a(List<Uint8List> atoms) {
  final ilst = box('ilst', atoms.expand((a) => a).toList());
  final hdlr = box('hdlr', List.filled(25, 0));
  // `meta` is a FullBox: 4 bytes of version/flags before its children.
  final meta = box('meta', [0, 0, 0, 0, ...hdlr, ...ilst]);
  final udta = box('udta', meta);

  // mvhd v0: version/flags, created, modified, timescale, duration, ...
  final mvhd = box('mvhd', [
    0, 0, 0, 0,
    ...List.filled(8, 0),
    ..._u32(1000), // timescale
    ..._u32(9000), // duration -> 9s
    ...List.filled(80, 0),
  ]);

  final moov = box('moov', [...mvhd, ...udta]);
  final ftyp = box('ftyp', ascii.encode('M4A mp42isom'));
  return Uint8List.fromList([...ftyp, ...moov]);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mp4tags');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<File> write(String name, Uint8List bytes) async {
    final f = File('${tmp.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  test('reads the standard name atoms', () async {
    final f = await write(
      'std.m4a',
      buildM4a([
        textAtom('©nam', 'Real Title'),
        textAtom('©ART', 'Real Artist'),
        textAtom('©alb', 'Real Album'),
      ]),
    );

    final tags = await Mp4TagParser.parse(f);
    expect(tags!.title, 'Real Title');
    expect(tags.artist, 'Real Artist');
    expect(tags.album, 'Real Album');
    expect(tags.duration, const Duration(seconds: 9));
  });

  test('reads the iTunes Store catalogue IDs', () async {
    // Shape of a purchase that arrives with no names whatsoever: nothing to
    // show but the IDs, which are what link it to its album-mates.
    final f = await write(
      'nameless.m4a',
      buildM4a([
        intAtom('cnID', 1693905668),
        intAtom('atID', 1451767737),
        intAtom('plID', 1693905661, bytes: 8),
        textAtom('©day', '2023-07-31T07:00:00Z'),
      ]),
    );

    final tags = await Mp4TagParser.parse(f);
    expect(tags!.title, isNull);
    expect(tags.artist, isNull);
    expect(tags.album, isNull);
    expect(tags.storeTrackId, 1693905668);
    expect(tags.storeArtistId, 1451767737);
    expect(tags.storeAlbumId, 1693905661);
  });

  test('falls back to sort atoms when the name atoms are absent', () async {
    // Shape of the store downloads that Android's scanner reports as
    // "<unknown>": only sonm/soar/soal are present.
    final f = await write(
      'sortonly.m4a',
      buildM4a([
        textAtom('sonm', 'Heaven'),
        textAtom('soar', 'NAYEON & SAM KIM'),
        textAtom('soal', 'NA'),
        textAtom('©day', '2024-06-14T12:00:00Z'),
      ]),
    );

    final tags = await Mp4TagParser.parse(f);
    expect(tags!.title, 'Heaven');
    expect(tags.artist, 'NAYEON & SAM KIM');
    expect(tags.album, 'NA');
    expect(tags.year, '2024');
  });

  test('a real name atom always beats the sort variant', () async {
    final f = await write(
      'both.m4a',
      buildM4a([
        textAtom('©nam', 'The Beatles Song'),
        textAtom('sonm', 'Beatles Song, The'),
        textAtom('©ART', 'The Beatles'),
        textAtom('soar', 'Beatles, The'),
      ]),
    );

    final tags = await Mp4TagParser.parse(f);
    expect(tags!.title, 'The Beatles Song');
    expect(tags.artist, 'The Beatles');
  });

  group('cover art', () {
    test('extracts embedded JPEG artwork', () async {
      final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 0xFF, 0xD9];
      final f = await write(
        'withart.m4a',
        buildM4a([
          textAtom('\u00a9nam', 'Cover Song'),
          binaryAtom('covr', 13, jpeg),
        ]),
      );

      final art = await Mp4TagParser.readArtwork(f);
      expect(art, isNotNull);
      expect(art, equals(jpeg));
    });

    test('extracts embedded PNG artwork', () async {
      final png = [0x89, 0x50, 0x4E, 0x47, 9, 9, 9];
      final f = await write(
        'withpng.m4a',
        buildM4a([binaryAtom('covr', 14, png)]),
      );

      expect(await Mp4TagParser.readArtwork(f), equals(png));
    });

    test('returns null when the file carries no cover', () async {
      // The shape of every file in this library: tags but no covr atom.
      final f = await write(
        'noart.m4a',
        buildM4a([
          textAtom('\u00a9nam', 'Heaven'),
          textAtom('\u00a9ART', 'NAYEON'),
        ]),
      );

      expect(await Mp4TagParser.readArtwork(f), isNull);
    });

    test('ignores a covr entry that is not an image type', () async {
      final f = await write(
        'badart.m4a',
        // Type 1 is UTF-8 text, not artwork.
        buildM4a([binaryAtom('covr', 1, [1, 2, 3])]),
      );

      expect(await Mp4TagParser.readArtwork(f), isNull);
    });
  });
}
