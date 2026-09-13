import 'dart:io';

import 'package:custom_music_player/core/library/library_model.dart';
import 'package:custom_music_player/core/metadata/track_reader.dart';
import 'package:custom_music_player/core/models/album.dart';
import 'package:custom_music_player/core/models/track.dart';
import 'package:custom_music_player/platform/library_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mewsic_tagfix/mewsic_tagfix.dart';

/// These run against the real iTunes files in the platform's own music
/// folders. They are the check that tag reading works on actual store-bought
/// AAC, not just synthetic fixtures.
void main() {
  final source = DirectoryLibrarySource.defaultLocation();

  group('iTunes m4a metadata', () {
    late List<Track> tracks;

    setUpAll(() async {
      tracks = await source.loadTracks();
    });

    test('finds every audio file', () {
      expect(tracks.length, 17);
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

    test('recovers names for store purchases that ship without any', () {
      // Three tracks of KILL MY DOUBT carry no ©nam/©ART/©alb -- not even
      // the sort variants -- only the store IDs. Their names come from the
      // tagged tracks of the same album, not from folder names.
      for (final name in ['02 CAKE', '03 None of My Business', '05 Psychic Lover']) {
        final t = tracks.firstWhere((t) => t.fileName.startsWith(name),
            orElse: () => throw StateError('$name not scanned'));
        expect(t.artist, 'ITZY', reason: name);
        expect(t.album, 'KILL MY DOUBT - EP', reason: name);
        expect(t.albumArtist, 'ITZY', reason: name);
        expect(t.genre, 'K-Pop', reason: name);
      }
      final cake = tracks.firstWhere((t) => t.fileName.startsWith('02 CAKE'));
      expect(cake.title, 'CAKE');
      expect(cake.trackNumber, 2);
    });

    test('preserves punctuation and parentheses in titles', () {
      final titles = tracks.map((t) => t.title).toSet();
      expect(titles, contains('Can’t Slow Me, No'));
      expect(titles, contains('Magic (feat. JULIE)'));
      expect(titles,
          contains('HalliGalli (Prod. by LEE CHANHYUK of AKMU)'));
    });

    test('groups into the three expected albums, in track order', () {
      final albums = Album.group(tracks);
      expect(albums.map((a) => a.name).toList(),
          ['AIR - EP', 'KILL MY DOUBT - EP', 'NA']);

      final kmd = albums.firstWhere((a) => a.name == 'KILL MY DOUBT - EP');
      expect(kmd.artist, 'ITZY');
      expect(kmd.tracks.length, 6);
      expect(kmd.tracks.map((t) => t.trackNumber), [1, 2, 3, 4, 5, 6]);

      final air = albums.firstWhere((a) => a.name == 'AIR - EP');
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
      library = LibraryModel(source);
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
      // ITZY's 6, then the 7 NA tracks, then YEJI's 4, with no interleaving.
      // One NA track is credited to a collaboration, which sorts inside
      // NAYEON's run rather than breaking it up.
      expect(artists.take(6).toSet(), {'ITZY'});
      expect(artists.skip(6).take(7).toSet(), {'NAYEON', 'NAYEON & SAM KIM'});
      expect(artists.skip(13).toSet(), {'YEJI'});
    });

    test('album sort orders by album then track number', () {
      library.setSort(SortField.album, SortDirection.ascending);
      final sorted = library.sortedTracks;
      expect(sorted.take(4).map((t) => t.album).toSet(), {'AIR - EP'});
      expect(sorted.take(4).map((t) => t.trackNumber), [1, 2, 3, 4]);
      expect(sorted.skip(4).take(6).map((t) => t.album).toSet(),
          {'KILL MY DOUBT - EP'});
      expect(sorted.skip(4).take(6).map((t) => t.trackNumber),
          [1, 2, 3, 4, 5, 6]);
      expect(sorted.skip(10).map((t) => t.trackNumber), [1, 2, 3, 4, 5, 6, 7]);
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

      final track = await TrackReader.read(tmp);
      expect(track.title, 'Untagged');
      expect(track.artist, 'Unknown Artist');
      expect(track.album, 'Unknown Album');
    });

    test('borrows artist and album from the folder layout when asked', () async {
      final root = await Directory.systemTemp.createTemp('lib');
      addTearDown(() => root.delete(recursive: true));
      final sep = Platform.pathSeparator;
      final file = await File('${root.path}${sep}ITZY${sep}KILL MY DOUBT - EP'
              '${sep}02 CAKE.m4a')
          .create(recursive: true);
      await file.writeAsBytes(List.filled(64, 0));

      final track = await TrackReader.read(file, libraryRoot: root);
      expect(track.title, 'CAKE');
      expect(track.artist, 'ITZY');
      expect(track.album, 'KILL MY DOUBT - EP');
      expect(track.trackNumber, 2);

      // A file sitting loose in the root gets nothing from its path.
      final loose = await File('${root.path}${sep}03 Loose.m4a').create();
      await loose.writeAsBytes(List.filled(64, 0));
      final looseTrack = await TrackReader.read(loose, libraryRoot: root);
      expect(looseTrack.artist, 'Unknown Artist');
      expect(looseTrack.album, 'Unknown Album');
      expect(TagReader.folderTagsFromPath('/elsewhere/a/b/c.m4a', root), isNull);
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
