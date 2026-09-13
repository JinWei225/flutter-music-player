import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:custom_music_player/core/metadata/mp3_tags.dart';
import 'package:custom_music_player/core/metadata/mp4_tags.dart';
import 'package:custom_music_player/core/metadata/tag_edit.dart';
import 'package:custom_music_player/core/metadata/tag_writer.dart';
import 'package:custom_music_player/platform/library_source.dart';
import 'package:flutter_test/flutter_test.dart';

// --- MP4 fixture ------------------------------------------------------------

List<int> u32(int v) => [(v >> 24) & 0xff, (v >> 16) & 0xff, (v >> 8) & 0xff, v & 0xff];

Uint8List box(String type, List<int> payload) => Uint8List.fromList(
    [...u32(8 + payload.length), ...latin1.encode(type), ...payload]);

Uint8List textAtom(String key, String value) => box(
    key, box('data', [...u32(1), ...u32(0), ...utf8.encode(value)]));

Uint8List binaryAtom(String key, int type, List<int> payload) =>
    box(key, box('data', [...u32(type), ...u32(0), ...payload]));

const chunkMarker = 'CHUNK-MARKER';

/// A structurally valid m4a: `moov` (with a real `stco` pointing into `mdat`)
/// then optionally a `free` box, then `mdat`. Returns the bytes and the
/// offset of [chunkMarker] inside them.
({Uint8List bytes, int markerOffset}) buildM4a(
  List<Uint8List> atoms, {
  int freeSize = 0,
}) {
  final mdatPayload = [...List.filled(50, 0xaa), ...ascii.encode(chunkMarker)];

  Uint8List assemble(int markerOffset) {
    final stco = box('stco', [0, 0, 0, 0, ...u32(1), ...u32(markerOffset)]);
    final trak = box('trak', box('mdia', box('minf', box('stbl', stco))));
    final ilst = box('ilst', atoms.expand((a) => a).toList());
    final hdlr = box('hdlr', List.filled(25, 0));
    final meta = box('meta', [0, 0, 0, 0, ...hdlr, ...ilst]);
    final mvhd = box('mvhd', [
      0, 0, 0, 0, ...List.filled(8, 0), ...u32(1000), ...u32(9000),
      ...List.filled(80, 0),
    ]);
    final moov = box('moov', [...mvhd, ...trak, ...box('udta', meta)]);
    final ftyp = box('ftyp', ascii.encode('M4A mp42isom'));
    final free = freeSize > 0 ? box('free', List.filled(freeSize - 8, 0)) : <int>[];
    return Uint8List.fromList([...ftyp, ...moov, ...free, ...box('mdat', mdatPayload)]);
  }

  // The marker offset depends on moov's size, which is fixed regardless of
  // the offset's value, so one dry run settles it.
  final dry = assemble(0);
  final markerOffset = _indexOf(dry, ascii.encode(chunkMarker));
  return (bytes: assemble(markerOffset), markerOffset: markerOffset);
}

int _indexOf(Uint8List hay, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Reads the first `stco` entry back out of a written file.
int firstChunkOffset(Uint8List bytes) {
  final i = _indexOf(bytes, ascii.encode('stco'));
  final at = i + 4 + 4 + 4; // past type, version/flags, count
  return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3];
}

// --- MP3 fixture ------------------------------------------------------------

List<int> synchsafe(int v) => [(v >> 21) & 0x7f, (v >> 14) & 0x7f, (v >> 7) & 0x7f, v & 0x7f];

Uint8List id3Frame(int major, String id, List<int> data) => Uint8List.fromList([
      ...ascii.encode(id),
      ...(major >= 4 ? synchsafe(data.length) : u32(data.length)),
      0, 0,
      ...data,
    ]);

Uint8List latin1Text(String s) => Uint8List.fromList([0, ...latin1.encode(s)]);

Uint8List buildMp3(int major, List<Uint8List> frames, {bool v1 = false}) {
  final body = frames.expand((f) => f).toList();
  final audio = List.filled(200, 0x55);
  final trailer = v1
      ? [
          ...ascii.encode('TAG'),
          ...List.filled(30, 0), // title
          ...List.filled(30, 0), // artist
          ...List.filled(30, 0), // album
          ...List.filled(4, 0), // year
          ...List.filled(30, 0), // comment
          0xff, // genre
        ]
      : <int>[];
  return Uint8List.fromList([
    ...ascii.encode('ID3'), major, 0, 0, ...synchsafe(body.length), ...body,
    ...audio, ...trailer,
  ]);
}

const edit = TagEdit(
  title: 'CAKE',
  artist: 'ITZY',
  album: 'KILL MY DOUBT - EP',
  albumArtist: 'ITZY',
  genre: 'K-Pop',
  year: '2023',
  trackNumber: 2,
  discNumber: 1,
);

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('tagwriter');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  Future<File> write(String name, Uint8List bytes) async {
    final f = File('${tmp.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes);
    return f;
  }

  group('Mp4TagWriter', () {
    test('adds names to a file that has none and keeps the audio findable',
        () async {
      // Shape of the broken purchases: store IDs and a date, nothing else.
      final fixture = buildM4a([
        binaryAtom('cnID', 21, u32(1693905668)),
        textAtom('©day', '2023-07-31T07:00:00Z'),
      ]);
      final f = await write('nameless.m4a', fixture.bytes);

      await TagWriter.write(f, edit);

      final tags = (await Mp4TagParser.parse(f))!;
      expect(tags.title, 'CAKE');
      expect(tags.artist, 'ITZY');
      expect(tags.album, 'KILL MY DOUBT - EP');
      expect(tags.albumArtist, 'ITZY');
      expect(tags.genre, 'K-Pop');
      expect(tags.year, '2023');
      expect(tags.trackNumber, 2);
      expect(tags.discNumber, 1);
      expect(tags.storeTrackId, 1693905668, reason: 'unmanaged atoms survive');
      expect(tags.duration, const Duration(seconds: 9));

      // No free box to absorb the growth, so mdat moved -- and stco with it.
      final bytes = await f.readAsBytes();
      final offset = firstChunkOffset(bytes);
      expect(offset, greaterThan(fixture.markerOffset));
      expect(ascii.decode(bytes.sublist(offset, offset + chunkMarker.length)),
          chunkMarker);
      expect(await File('${f.path}.mewsic-tmp').exists(), isFalse);
    });

    test('uses the free box after moov so nothing else moves', () async {
      final fixture = buildM4a([textAtom('©nam', 'Old')], freeSize: 4096);
      final f = await write('padded.m4a', fixture.bytes);
      final before = await f.length();

      await TagWriter.write(f, edit);

      final bytes = await f.readAsBytes();
      expect(bytes.length, before, reason: 'growth came out of the free box');
      expect(firstChunkOffset(bytes), fixture.markerOffset);
      expect((await Mp4TagParser.parse(f))!.title, 'CAKE');
    });

    test('an empty field removes the atom', () async {
      final fixture = buildM4a([
        textAtom('©nam', 'Old'),
        textAtom('©gen', 'Wrong Genre'),
      ]);
      final f = await write('clear.m4a', fixture.bytes);

      await TagWriter.write(
        f,
        const TagEdit(
          title: 'New',
          artist: '',
          album: '',
          albumArtist: '',
          genre: '',
          year: '',
          trackNumber: null,
          discNumber: null,
        ),
      );

      final tags = (await Mp4TagParser.parse(f))!;
      expect(tags.title, 'New');
      expect(tags.genre, isNull);
      expect(tags.artist, isNull);
    });

    test('keeps the album track count when only the number changes', () async {
      final fixture = buildM4a([
        binaryAtom('trkn', 0, [0, 0, 0, 4, 0, 6, 0, 0]),
      ]);
      final f = await write('total.m4a', fixture.bytes);

      await TagWriter.write(f, edit);

      final bytes = await f.readAsBytes();
      final i = _indexOf(bytes, latin1.encode('trkn'));
      final payload = i + 4 + 8 + 8; // data header, type, locale
      expect(bytes.sublist(payload, payload + 6), [0, 0, 0, 2, 0, 6]);
    });

    test('round-trips a real store purchase', () async {
      final source = DirectoryLibrarySource.defaultLocation();
      final tracks = await source.loadTracks();
      final cake = tracks.where((t) => t.fileName.startsWith('02 CAKE'));
      if (cake.isEmpty) {
        markTestSkipped('KILL MY DOUBT is not in this library');
        return;
      }
      final copy = await File(cake.first.filePath!)
          .copy('${tmp.path}${Platform.pathSeparator}02 CAKE.m4a');

      await TagWriter.write(copy, edit);

      final tags = (await Mp4TagParser.parse(copy))!;
      expect(tags.title, 'CAKE');
      expect(tags.artist, 'ITZY');
      expect(tags.album, 'KILL MY DOUBT - EP');
      expect(tags.storeAlbumId, isNotNull);
      expect(tags.duration!.inSeconds, greaterThan(30));
      // iTunes' free box absorbed the change, so the size is unchanged.
      expect(await copy.length(), await File(cake.first.filePath!).length());
    });
  });

  group('Mp3TagWriter', () {
    test('rewrites a v2.3 tag keeping frames it does not own', () async {
      final f = await write(
        'v23.mp3',
        buildMp3(3, [
          id3Frame(3, 'TIT2', latin1Text('Old')),
          id3Frame(3, 'TXXX', latin1Text('keep me')),
          id3Frame(3, 'TRCK', latin1Text('9/12')),
        ]),
      );

      await TagWriter.write(f, edit);

      final tags = (await Mp3TagParser.parse(f))!;
      expect(tags.title, 'CAKE');
      expect(tags.artist, 'ITZY');
      expect(tags.album, 'KILL MY DOUBT - EP');
      expect(tags.albumArtist, 'ITZY');
      expect(tags.genre, 'K-Pop');
      expect(tags.year, '2023');
      expect(tags.trackNumber, 2);
      expect(tags.discNumber, 1);

      final bytes = await f.readAsBytes();
      expect(bytes[3], 3, reason: 'stays v2.3');
      expect(_indexOf(bytes, ascii.encode('TXXX')), greaterThan(0));
      // Track total preserved; v2.3 text is written as UTF-16LE.
      expect(_indexOf(bytes, [0x32, 0, 0x2f, 0, 0x31, 0, 0x32, 0]), greaterThan(0));
      // Audio bytes intact after the tag.
      expect(bytes.where((b) => b == 0x55).length, greaterThanOrEqualTo(200));
    });

    test('writes v2.4 with UTF-8 and TDRC', () async {
      final f = await write(
        'v24.mp3',
        buildMp3(4, [id3Frame(4, 'TIT2', latin1Text('Old'))]),
      );

      await TagWriter.write(f, edit);

      final tags = (await Mp3TagParser.parse(f))!;
      expect(tags.title, 'CAKE');
      expect(tags.year, '2023');
      final bytes = await f.readAsBytes();
      expect(bytes[3], 4);
      expect(_indexOf(bytes, ascii.encode('TDRC')), greaterThan(0));
      expect(_indexOf(bytes, ascii.encode('TYER')), -1);
    });

    test('tags a file that has no ID3v2 at all', () async {
      final f = await write('bare.mp3', Uint8List.fromList(List.filled(200, 0x55)));

      await TagWriter.write(f, edit);

      final tags = (await Mp3TagParser.parse(f))!;
      expect(tags.title, 'CAKE');
      expect(tags.artist, 'ITZY');
      expect((await f.readAsBytes()).length, greaterThan(200));
    });

    test('updates the ID3v1 trailer too', () async {
      final f = await write('v1.mp3', buildMp3(3, const [], v1: true));

      await TagWriter.write(f, edit);

      final bytes = await f.readAsBytes();
      final tail = bytes.sublist(bytes.length - 128);
      expect(ascii.decode(tail.sublist(0, 3)), 'TAG');
      expect(latin1.decode(tail.sublist(3, 7)), 'CAKE');
      expect(latin1.decode(tail.sublist(33, 37)), 'ITZY');
      expect(tail[125], 0);
      expect(tail[126], 2);
      expect(tail[127], 0xff, reason: 'K-Pop is not an ID3v1 genre');
      // Only one trailer: the audio before it is untouched.
      expect(bytes.sublist(bytes.length - 328, bytes.length - 128).every((b) => b == 0x55), isTrue);
    });
  });

  test('TagWriter.canWrite covers the formats the player edits', () {
    expect(TagWriter.canWrite('/x/a.m4a'), isTrue);
    expect(TagWriter.canWrite('/x/a.MP3'), isTrue);
    expect(TagWriter.canWrite('/x/a.aac'), isFalse);
  });
}
