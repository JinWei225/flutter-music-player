import 'dart:io';

import 'package:custom_music_player/core/library/library_model.dart';
import 'package:custom_music_player/core/metadata/tag_reader.dart';
import 'package:custom_music_player/core/models/album.dart';
import 'package:custom_music_player/core/models/track.dart';
import 'package:custom_music_player/platform/library_source.dart';
import 'package:flutter_test/flutter_test.dart';

/// These run against the real iTunes files in ~/Music. They are the check that
/// tag reading works on actual store-bought AAC, not just synthetic fixtures.
void main() {
  final musicDir = Directory(
      '${Platform.environment['HOME']}${Platform.pathSeparator}Music');

  group('iTunes m4a metadata', () {
    late List<Track> tracks;

    setUpAll(() async {
      tracks = await DirectoryLibrarySource(musicDir).loadTracks();
    });

    test('finds every audio file', () {
      expect(tracks.length, 11);
    });

    test('every track has real tags, not filename fallbacks', () {
      for (final t in tracks) {
        expect(t.title, isNotEmpty, reason: 'title missing for ${t.fileName}');
        expect(t.artist, isNot('Unknown Artist'),
            reason: 'artist fell back for ${t.fileName}');
        expect(t.album, isNot('Unknown Album'),
            reason: 'album fell back for ${t.fileName}');
        expect(t.trackNumber, isNotNull,
            reason: 'track number missing for ${t.fileName}');
        expect(t.duration, isNotNull,
            reason: 'duration missing for ${t.fileName}');
        expect(t.duration!.inSeconds, greaterThan(30));
      }
    });

    test('reads the moov-level ilst, not the empty one inside trak', () {
      // "01 ABCD.m4a" is moov-last and carries a decoy empty ilst in its trak.
      final abcd = tracks.firstWhere((t) => t.fileName.startsWith('01 ABCD'));
      expect(abcd.title, 'ABCD');
      expect(abcd.artist, 'NAYEON');
      expect(abcd.album, 'NA');
      expect(abcd.trackNumber, 1);
      expect(abcd.year, '2024');
    });

    test('preserves punctuation and parentheses in titles', () {
      final titles = tracks.map((t) => t.title).toSet();
      expect(titles, contains("Can't Slow Me, No"));
      expect(titles, contains('Magic (feat. JULIE)'));
      expect(titles,
          contains('HalliGalli (Prod. by LEE CHANHYUK of AKMU)'));
    });

    test('groups into the two expected albums, in track order', () {
      final albums = Album.group(tracks);
      expect(albums.map((a) => a.name).toList(), ['Air - EP', 'NA']);

      final air = albums.firstWhere((a) => a.name == 'Air - EP');
      expect(air.artist, 'YEJI');
      expect(air.tracks.length, 4);
      expect(air.tracks.map((t) => t.trackNumber), [1, 2, 3, 4]);
      expect(air.tracks.first.title, 'Air');

      final na = albums.firstWhere((a) => a.name == 'NA');
      expect(na.artist, 'NAYEON');
      expect(na.tracks.length, 7);
      expect(na.tracks.map((t) => t.trackNumber), [1, 2, 3, 4, 5, 6, 7]);
    });
  });

  group('All Songs sorting', () {
    late LibraryModel library;

    setUpAll(() async {
      library = LibraryModel(DirectoryLibrarySource(musicDir));
      await library.load();
    });

    test('title ascending and descending are exact reverses', () {
      library.setSort(SortField.title, SortDirection.ascending);
      final asc = library.sortedTracks.map((t) => t.title).toList();
      library.setSort(SortField.title, SortDirection.descending);
      final desc = library.sortedTracks.map((t) => t.title).toList();

      expect(asc, equals(List.of(asc)..sort(
          (a, b) => a.toLowerCase().compareTo(b.toLowerCase()))));
      expect(desc, equals(asc.reversed.toList()));
    });

    test('artist sort groups an artist together', () {
      library.setSort(SortField.artist, SortDirection.ascending);
      final artists = library.sortedTracks.map((t) => t.artist).toList();
      // NAYEON's 7 come before YEJI's 4, with no interleaving.
      expect(artists.take(7).toSet(), {'NAYEON'});
      expect(artists.skip(7).toSet(), {'YEJI'});
    });

    test('album sort orders by album then track number', () {
      library.setSort(SortField.album, SortDirection.ascending);
      final sorted = library.sortedTracks;
      expect(sorted.take(4).map((t) => t.album).toSet(), {'Air - EP'});
      expect(sorted.take(4).map((t) => t.trackNumber), [1, 2, 3, 4]);
      expect(sorted.skip(4).map((t) => t.trackNumber), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('selectSortField flips direction when reselected', () {
      library.setSort(SortField.title, SortDirection.ascending);
      library.selectSortField(SortField.title);
      expect(library.sortDirection, SortDirection.descending);
      library.selectSortField(SortField.artist);
      expect(library.sortField, SortField.artist);
      expect(library.sortDirection, SortDirection.ascending);
    });
  });

  group('TagReader fallbacks', () {
    test('derives a title from the filename when a file has no tags', () async {
      final tmp = await File(
              '${Directory.systemTemp.path}${Platform.pathSeparator}04 Untagged.m4a')
          .create();
      await tmp.writeAsBytes(List.filled(64, 0));
      addTearDown(() => tmp.delete());

      final track = await TagReader.read(tmp);
      expect(track.title, 'Untagged');
      expect(track.artist, 'Unknown Artist');
      expect(track.album, 'Unknown Album');
    });

    test('recovers a track number from a numbered filename', () {
      expect(TagReader.trackNumberFromFileName('/m/04 Magic.m4a'), 4);
      expect(TagReader.trackNumberFromFileName('/m/07 Count It.m4a'), 7);
      expect(TagReader.trackNumberFromFileName('/m/12-Song.mp3'), 12);
      // Not a leading number, or a meaningless one.
      expect(TagReader.trackNumberFromFileName('/m/Song.m4a'), isNull);
      expect(TagReader.trackNumberFromFileName('/m/2024 Recap.m4a'), isNull);
      expect(TagReader.trackNumberFromFileName('/m/00 Intro.m4a'), isNull);
    });

    test('recognises the formats the player supports', () {
      expect(TagReader.isSupported('/x/a.m4a'), isTrue);
      expect(TagReader.isSupported('/x/a.MP3'), isTrue);
      expect(TagReader.isSupported('/x/a.flac'), isFalse);
      expect(TagReader.isSupported('/x/cover.jpg'), isFalse);
    });
  });
}
