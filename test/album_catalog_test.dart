import 'dart:convert';
import 'dart:io';

import 'package:custom_music_player/core/library/library_model.dart';
import 'package:custom_music_player/platform/album_catalog.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'spotlight_index_test.dart' show FakeSource, t;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late FakeSource source;
  late LibraryModel library;
  late AlbumCatalog catalog;
  late List<String> coversRead;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('catalog_test');
    coversRead = [];
    source = FakeSource([
      t('One', 'NA', 'NAYEON', n: 1),
      t('Two', 'NA', 'NAYEON', n: 2),
      t('Ready', 'Ready to Be', 'TWICE', n: 1),
    ]);
    library = LibraryModel(source);
    catalog = AlbumCatalog(
      library,
      directory: () async => dir,
      coverFor: (album) async {
        coversRead.add(album.name);
        return album.name == 'NA' ? Uint8List.fromList([1, 2, 3]) : null;
      },
    );
    await library.load();
  });

  tearDown(() => dir.delete(recursive: true));

  Map<String, dynamic> read() =>
      jsonDecode(File('${dir.path}/albums.json').readAsStringSync());
  Map album(String name) => (read()['albums'] as List).cast<Map>().firstWhere(
    (a) => a['name'] == name,
  );
  List<String> coverFiles() => [
    for (final f in Directory('${dir.path}/covers').listSync()) f.path,
  ];

  test('writes every album with its links and cover', () async {
    await catalog.sync();

    expect(read()['format'], AlbumCatalog.format);
    final na = album('NA');
    expect(na['artist'], 'NAYEON');
    expect(na['songs'], 2);
    expect(na['seconds'], 360);
    expect(na['links'], {
      'open': 'mewsic://album?name=NA&artist=NAYEON',
      'play': 'mewsic://album?name=NA&artist=NAYEON&action=play',
      'shuffle': 'mewsic://album?name=NA&artist=NAYEON&action=shuffle',
      'next': 'mewsic://album?name=NA&artist=NAYEON&action=next',
    });
    expect(File(na['cover']).readAsBytesSync(), [1, 2, 3]);
    final songs = (na['tracks'] as List).cast<Map>();
    expect(songs.map((s) => s['title']), ['One', 'Two']);
    expect(songs.first['number'], 1);
    expect(songs.first['seconds'], 180);
    expect(songs.first['links'], {
      'play': 'mewsic://song?path=%2Fm%2FNA%2FOne.m4a',
      'next': 'mewsic://song?path=%2Fm%2FNA%2FOne.m4a&action=next',
    });
    expect(album('Ready to Be')['cover'], isNull);
  });

  test(
    'an unchanged album keeps its cover and the file is left alone',
    () async {
      await catalog.sync();
      final written = File('${dir.path}/albums.json').lastModifiedSync();
      coversRead.clear();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await catalog.sync();

      expect(coversRead, isEmpty);
      expect(File('${dir.path}/albums.json').lastModifiedSync(), written);
    },
  );

  test('a changed album gets a new cover file and the old one goes', () async {
    await catalog.sync();
    final oldCover = album('NA')['cover'] as String;

    source.tracks = [
      t('One', 'NA', 'NAYEON', n: 1),
      t('Two', 'NA', 'NAYEON', n: 2),
      t('Three', 'NA', 'NAYEON', n: 3),
    ];
    await library.load();
    await catalog.sync();

    final newCover = album('NA')['cover'] as String;
    expect(newCover, isNot(oldCover));
    expect(coverFiles(), [newCover]);
    expect((read()['albums'] as List).map((a) => a['name']), ['NA']);
  });

  test('a cover file deleted by hand is written again', () async {
    await catalog.sync();
    File(album('NA')['cover'] as String).deleteSync();
    coversRead.clear();

    await catalog.sync();

    expect(coversRead, ['NA']);
    expect(File(album('NA')['cover'] as String).existsSync(), isTrue);
  });
}
