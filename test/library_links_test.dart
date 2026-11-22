import 'package:custom_music_player/core/library/library_links.dart';
import 'package:custom_music_player/core/models/album.dart';
import 'package:custom_music_player/core/models/track.dart';
import 'package:flutter_test/flutter_test.dart';

Album album(String name, String artist) => Album(
  name: name,
  artist: artist,
  year: null,
  tracks: [
    Track(
      path: '/m/$name/1.m4a',
      title: '1',
      artist: artist,
      album: name,
      albumArtist: artist,
    ),
  ],
);

void main() {
  group('LibraryLink', () {
    test('an album link survives the round trip, odd characters and all', () {
      const link = AlbumLink(name: 'Na & Co: Vol. 1?', artist: 'NAYEON / 나연');
      expect(LibraryLink.parse(link.toString()), link);
    });

    test('a search link survives the round trip', () {
      const link = SearchLink('shuffle twice');
      expect(link.toString(), startsWith('mewsic://search?q='));
      expect(LibraryLink.parse(link.toString()), link);
    });

    test('%20 and + both read as spaces, as launchers vary', () {
      expect(
        LibraryLink.parse('mewsic://search?q=love%20yourself'),
        const SearchLink('love yourself'),
      );
      expect(
        LibraryLink.parse('mewsic://search?q=love+yourself'),
        const SearchLink('love yourself'),
      );
    });

    test('scheme and host ignore case', () {
      expect(
        LibraryLink.parse('MEWSIC://Album?name=NA'),
        const AlbumLink(name: 'NA'),
      );
    });

    test('links the app does not know are refused', () {
      expect(LibraryLink.parse('https://album?name=NA'), isNull);
      expect(LibraryLink.parse('mewsic://artist?name=NAYEON'), isNull);
      expect(LibraryLink.parse('mewsic://album'), isNull);
      expect(LibraryLink.parse('mewsic://album?name='), isNull);
      expect(LibraryLink.parse('::not a link'), isNull);
    });
  });

  group('AlbumLink.findIn', () {
    final na = album('NA', 'NAYEON');
    final greatest = album('Greatest Hits', 'Queen');
    final greatest2 = album('Greatest Hits', 'ABBA');
    final albums = [na, greatest, greatest2];

    test('finds the album it was made from', () {
      for (final a in albums) {
        expect(AlbumLink.of(a).findIn(albums), same(a));
      }
    });

    test('ignores case when nothing matches exactly', () {
      expect(
        const AlbumLink(name: 'na', artist: 'nayeon').findIn(albums),
        same(na),
      );
    });

    test('a name alone is enough when only one album has it', () {
      expect(const AlbumLink(name: 'NA').findIn(albums), same(na));
    });

    test('a name alone does not guess between two albums', () {
      expect(const AlbumLink(name: 'Greatest Hits').findIn(albums), isNull);
    });

    test('an album no longer in the library is not found', () {
      expect(
        const AlbumLink(name: 'NA', artist: 'TWICE').findIn(albums),
        isNull,
      );
    });
  });
}
