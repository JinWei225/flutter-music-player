import 'package:custom_music_player/core/metadata/raw_tags.dart';
import 'package:custom_music_player/core/metadata/sibling_tags.dart';
import 'package:flutter_test/flutter_test.dart';

RawTags tagged({
  String? title,
  String? artist,
  String? album,
  String? albumArtist,
  String? genre,
  int? albumId,
  int? artistId,
}) =>
    RawTags()
      ..title = title
      ..artist = artist
      ..album = album
      ..albumArtist = albumArtist
      ..genre = genre
      ..storeAlbumId = albumId
      ..storeArtistId = artistId;

void main() {
  group('SiblingTags', () {
    test('a nameless track takes its names from album-mates', () {
      final cake = tagged(albumId: 10, artistId: 7);
      final bratty = tagged(
        title: 'Bratty',
        artist: 'ITZY',
        album: 'KILL MY DOUBT - EP',
        albumArtist: 'ITZY',
        genre: 'K-Pop',
        albumId: 10,
        artistId: 7,
      );

      SiblingTags.complete([cake, bratty]);

      expect(cake.title, isNull, reason: 'titles are never borrowed');
      expect(cake.artist, 'ITZY');
      expect(cake.album, 'KILL MY DOUBT - EP');
      expect(cake.albumArtist, 'ITZY');
      expect(cake.genre, 'K-Pop');
      expect(bratty.title, 'Bratty');
    });

    test('never overwrites a track\'s own tags', () {
      final own = tagged(artist: 'Guest', album: 'Own', albumId: 10, artistId: 7);
      final other = tagged(artist: 'Main', album: 'Other', albumId: 10, artistId: 7);
      SiblingTags.complete([own, other]);
      expect(own.artist, 'Guest');
      expect(own.album, 'Own');
    });

    test('the most common artist spelling wins over a guest credit', () {
      final blank = tagged(artistId: 7);
      final siblings = [
        tagged(artist: 'NAYEON', artistId: 7),
        tagged(artist: 'NAYEON & SAM KIM', artistId: 7),
        tagged(artist: 'NAYEON', artistId: 7),
      ];
      SiblingTags.complete([blank, ...siblings]);
      expect(blank.artist, 'NAYEON');
    });

    test('prefers the album artist for a track with no artist line', () {
      final blank = tagged(albumId: 10, artistId: 7);
      final mate = tagged(
        artist: 'NAYEON & SAM KIM',
        album: 'NA',
        albumArtist: 'NAYEON',
        albumId: 10,
        artistId: 7,
      );
      SiblingTags.complete([blank, mate]);
      expect(blank.artist, 'NAYEON');
    });

    test('leaves tracks alone when nothing shares their IDs', () {
      final alone = tagged(albumId: 99, artistId: 98);
      final unrelated = tagged(artist: 'X', album: 'Y', albumId: 1, artistId: 2);
      final noIds = tagged();
      SiblingTags.complete([alone, unrelated, noIds]);
      expect(alone.artist, isNull);
      expect(alone.album, isNull);
      expect(noIds.artist, isNull);
    });
  });
}
