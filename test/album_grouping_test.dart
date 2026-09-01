import 'package:custom_music_player/core/models/album.dart';
import 'package:custom_music_player/core/models/track.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(
  String title,
  String artist,
  String album, {
  int? track,
  String albumArtist = '',
}) =>
    Track(
      path: '/m/$title.m4a',
      title: title,
      artist: artist,
      album: album,
      albumArtist: albumArtist,
      trackNumber: track,
    );

void main() {
  test('a guest artist does not split the album', () {
    // The shape found on the device: one track credits a collaborator.
    final albums = Album.group([
      t('ABCD', 'NAYEON', 'NA', track: 1),
      t('Butterflies', 'NAYEON', 'NA', track: 2),
      t('Heaven', 'NAYEON & SAM KIM', 'NA', track: 3),
      t('Count It', 'NAYEON', 'NA', track: 7),
    ]);

    expect(albums.length, 1);
    expect(albums.single.name, 'NA');
    expect(albums.single.artist, 'NAYEON');
    expect(albums.single.tracks.length, 4);
    expect(albums.single.tracks.map((x) => x.trackNumber), [1, 2, 3, 7]);
  });

  test('different artists sharing an album title stay separate', () {
    final albums = Album.group([
      t('Air', 'YEJI', 'Air'),
      t('Breeze', 'Someone Else', 'Air'),
    ]);

    expect(albums.length, 2);
    expect(albums.map((a) => a.artist).toSet(), {'YEJI', 'Someone Else'});
  });

  test('a band name containing a separator is left intact', () {
    final albums = Album.group([
      t('The Boxer', 'Simon & Garfunkel', 'Bridge'),
      t('Cecilia', 'Simon & Garfunkel', 'Bridge'),
    ]);

    expect(albums.length, 1);
    expect(albums.single.artist, 'Simon & Garfunkel');
  });

  test('a partial name match does not fold', () {
    // "NAY" must not swallow "NAYEON": the boundary check requires a
    // non-alphanumeric character after the prefix.
    final albums = Album.group([
      t('One', 'NAY', 'Split'),
      t('Two', 'NAYEON', 'Split'),
    ]);

    expect(albums.length, 2);
  });

  test('an explicit album artist still wins', () {
    final albums = Album.group([
      t('One', 'Guest A', 'Comp', track: 1, albumArtist: 'Various Artists'),
      t('Two', 'Guest B', 'Comp', track: 2, albumArtist: 'Various Artists'),
    ]);

    expect(albums.length, 1);
    expect(albums.single.artist, 'Various Artists');
  });

  test('albums are sorted by name then artist', () {
    final albums = Album.group([
      t('x', 'B', 'Zebra'),
      t('y', 'A', 'Apple'),
    ]);

    expect(albums.map((a) => a.name), ['Apple', 'Zebra']);
  });
}
