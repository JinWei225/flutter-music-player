import 'dart:convert';
import 'dart:io';

import 'package:custom_music_player/core/models/track.dart';
import 'package:custom_music_player/core/player/player_model.dart';
import 'package:custom_music_player/platform/player_status_file.dart';
import 'package:custom_music_player/platform/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test.dart' show FakeAudioBackend;

Track track(int n) => Track(
  path: '/music/$n.m4a',
  title: 'Song $n',
  artist: 'Artist',
  album: 'Album',
  albumArtist: '',
  trackNumber: n,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late PlayerModel player;
  late PlayerStatusFile status;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('status_test');
    SharedPreferences.setMockInitialValues({});
    player = PlayerModel(await SettingsStore.open(), audio: FakeAudioBackend());
    status = PlayerStatusFile(player, directory: () async => dir)..start();
  });

  tearDown(() async {
    status.dispose();
    await dir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> read() async {
    await status.settled;
    return jsonDecode(File('${dir.path}/player.json').readAsStringSync());
  }

  test('says nothing is playing before anything is', () async {
    final json = await read();
    expect(json['playing'], isFalse);
    expect(json['track'], isNull);
  });

  test('follows the song, play state and shuffle', () async {
    await player.playTracks([track(1), track(2)], shuffle: false);
    var json = await read();
    expect(json['playing'], isTrue);
    expect(json['track']['title'], 'Song 1');
    expect(json['shuffle'], isFalse);

    await player.next();
    await player.pause();
    player.toggleShuffle();
    json = await read();
    expect(json['track']['title'], 'Song 2');
    expect(json['playing'], isFalse);
    expect(json['shuffle'], isTrue);
  });
}
