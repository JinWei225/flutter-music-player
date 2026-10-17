import 'package:custom_music_player/core/library/command_search.dart';
import 'package:custom_music_player/core/models/album.dart';
import 'package:custom_music_player/core/models/track.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(
  String title,
  String artist,
  String album, {
  int? track,
  String? year,
}) => Track(
  path: '/m/$album/$title.m4a',
  title: title,
  artist: artist,
  album: album,
  albumArtist: '',
  trackNumber: track,
  year: year,
  duration: const Duration(minutes: 3),
);

void main() {
  group('ParsedCommand', () {
    test('a bare query plays', () {
      final c = ParsedCommand.parse('  nayeon ');
      expect(c.verb, CommandVerb.play);
      expect(c.query, 'nayeon');
    });

    test('the kew prefix is optional', () {
      expect(ParsedCommand.parse('kew kill my doubt').query, 'kill my doubt');
      expect(ParsedCommand.parse('KEW air').query, 'air');
    });

    test('shuffle and next are verbs when followed by a query', () {
      final s = ParsedCommand.parse('kew shuffle itzy');
      expect(s.verb, CommandVerb.shuffle);
      expect(s.query, 'itzy');
      final n = ParsedCommand.parse('next cake');
      expect(n.verb, CommandVerb.next);
      expect(n.query, 'cake');
    });

    test('a verb on its own is searched for, not dropped', () {
      // There could be a song called "Shuffle".
      final c = ParsedCommand.parse('shuffle');
      expect(c.verb, CommandVerb.play);
      expect(c.query, 'shuffle');
    });
  });

  test('normalising ignores case, accents and punctuation', () {
    expect(normalizeForSearch('Can’t Slow Me, No'), 'cant slow me no');
    expect(normalizeForSearch('Beyoncé'), 'beyonce');
    expect(normalizeForSearch('KILL MY DOUBT - EP'), 'kill my doubt ep');
  });

  test('match scores rank exact over prefix over word over substring', () {
    expect(matchScore('air', 'air'), greaterThan(matchScore('air', 'air ep')));
    expect(
      matchScore('air', 'air ep'),
      greaterThan(matchScore('doubt', 'kill my doubt ep')),
    );
    expect(
      matchScore('doubt', 'kill my doubt ep'),
      greaterThan(matchScore('oub', 'kill my doubt ep')),
    );
    expect(matchScore('kmd', 'kill my doubt'), greaterThan(0));
    expect(matchScore('zzz', 'kill my doubt'), 0);
  });

  group('searchLibrary', () {
    final albums = Album.group([
      t('ABCD', 'NAYEON', 'NA', track: 1, year: '2024'),
      t('Butterflies', 'NAYEON', 'NA', track: 2, year: '2024'),
      t('POP!', 'NAYEON', 'IM NAYEON', track: 1, year: '2022'),
      t('Air', 'YEJI', 'AIR - EP', track: 1),
      t('Invasion', 'YEJI', 'AIR - EP', track: 2),
      t('CAKE', 'ITZY', 'KILL MY DOUBT - EP', track: 2),
      t('BET ON ME', 'ITZY', 'KILL MY DOUBT - EP', track: 1),
    ]);

    test('an artist plays every album, oldest first, in track order', () {
      final top = searchLibrary('nayeon', albums).first;
      expect(top.kind, MatchKind.artist);
      expect(top.tracks.map((x) => x.title), ['POP!', 'ABCD', 'Butterflies']);
    });

    test('an album plays from its first track', () {
      final top = searchLibrary('kill my doubt', albums).first;
      expect(top.kind, MatchKind.album);
      expect(top.startIndex, 0);
      expect(top.tracks.map((x) => x.title), ['BET ON ME', 'CAKE']);
    });

    test('a song plays its album from that song on', () {
      final top = searchLibrary('cake', albums).first;
      expect(top.kind, MatchKind.song);
      expect(top.tracks[top.startIndex].title, 'CAKE');
      expect(top.tracks.length, 2);
    });

    test('a query matching several kinds lists each, best first', () {
      final matches = searchLibrary('air', albums);
      // "Air" the song is an exact match; "AIR - EP" only a prefix.
      expect(matches.map((m) => (m.kind, m.label)).take(2), [
        (MatchKind.song, 'Air'),
        (MatchKind.album, 'AIR - EP'),
      ]);
    });

    test('nothing for an empty or unmatched query, and at most limit', () {
      expect(searchLibrary('   ', albums), isEmpty);
      expect(searchLibrary('zzzz', albums), isEmpty);
      expect(searchLibrary('e', albums, limit: 3).length, 3);
    });
  });
}
