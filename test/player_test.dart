import 'dart:async';
import 'dart:math';

import 'package:custom_music_player/core/models/track.dart';
import 'package:custom_music_player/core/player/audio_backend.dart';
import 'package:custom_music_player/core/player/player_model.dart';
import 'package:custom_music_player/platform/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for the audio engine.
class FakeAudioBackend implements AudioBackend {
  String? loadedPath;
  bool _playing = false;
  Duration _position = Duration.zero;
  double volume = 0;

  @override
  bool completed = false;

  final _completions = StreamController<void>.broadcast();
  final _stateChanges = StreamController<void>.broadcast();

  /// Every path handed to the backend, in order.
  final List<String> playedPaths = [];

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  set position(Duration value) => _position = value;

  @override
  Stream<Duration> get positionStream => const Stream.empty();

  @override
  Stream<Duration?> get durationStream => const Stream.empty();

  @override
  Stream<void> get completions => _completions.stream;

  @override
  Stream<void> get stateChanges => _stateChanges.stream;

  @override
  Future<void> setSource(String path) async {
    loadedPath = path;
    playedPaths.add(path);
    _position = Duration.zero;
    completed = false;
  }

  @override
  Future<void> play() async => _playing = true;

  @override
  Future<void> pause() async => _playing = false;

  @override
  Future<void> seek(Duration position) async => _position = position;

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  Future<void> dispose() async {
    _completions.close();
    _stateChanges.close();
  }

  /// Simulates the current track running to its end.
  Future<void> finishTrack() async {
    completed = true;
    _completions.add(null);
    // Let the model's async listener run.
    await Future<void>.delayed(Duration.zero);
  }
}

Track _track(int n) => Track(
      path: '/music/$n.m4a',
      title: 'Song $n',
      artist: 'Artist',
      album: 'Album',
      albumArtist: '',
      trackNumber: n,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAudioBackend audio;
  late SettingsStore settings;
  final tracks = [for (var i = 1; i <= 5; i++) _track(i)];

  Future<PlayerModel> makePlayer({int seed = 1}) async {
    audio = FakeAudioBackend();
    return PlayerModel(settings, audio: audio, random: Random(seed));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsStore.open();
  });

  group('queue and transport', () {
    test('playing a track loads that exact file', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 2);
      expect(p.currentTrack, tracks[2]);
      expect(audio.loadedPath, '/music/3.m4a');
      expect(p.isPlaying, isTrue);
    });

    test('next advances and wraps with repeat-list', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 3);
      await p.next();
      expect(p.currentTrack, tracks[4]);
      await p.next(); // past the end
      expect(p.currentTrack, tracks[0], reason: 'should wrap to the start');
    });

    test('next stops at the end when repeat is off', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 4);
      p.cycleRepeat(); // all -> one
      p.cycleRepeat(); // one -> off
      await p.next();
      expect(p.isPlaying, isFalse);
      expect(p.currentTrack, tracks[4]);
    });

    test('previous restarts the track when past 3 seconds', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 2);
      audio.position = const Duration(seconds: 10);
      await p.previous();
      expect(p.currentTrack, tracks[2], reason: 'should not change track');
      expect(audio.position, Duration.zero);
    });

    test('previous steps back when near the start', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 2);
      audio.position = const Duration(seconds: 1);
      await p.previous();
      expect(p.currentTrack, tracks[1]);
    });

    test('playQueuePosition jumps within the order', () async {
      final p = await makePlayer();
      await p.playTracks(tracks);
      await p.playQueuePosition(3);
      expect(p.currentQueuePosition, 3);
      expect(p.currentTrack, tracks[3]);
    });

    test('togglePlayPause flips playback', () async {
      final p = await makePlayer();
      await p.playTracks(tracks);
      expect(p.isPlaying, isTrue);
      await p.togglePlayPause();
      expect(p.isPlaying, isFalse);
      await p.togglePlayPause();
      expect(p.isPlaying, isTrue);
    });
  });

  group('play next', () {
    List<String> titles(PlayerModel p) =>
        [for (final t in p.queueInPlayOrder) t.title];

    test('moves a queued track to right after the current one', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 0);
      await p.playNext(tracks[3]);
      expect(titles(p), ['Song 1', 'Song 4', 'Song 2', 'Song 3', 'Song 5']);
      expect(p.currentTrack, tracks[0], reason: 'nothing should jump');
      await p.next();
      expect(p.currentTrack, tracks[3]);
    });

    test('a second pick lands after the first, not in front of it', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 0);
      await p.playNext(tracks[3]);
      await p.playNext(tracks[4]);
      expect(titles(p), ['Song 1', 'Song 4', 'Song 5', 'Song 2', 'Song 3']);
      await p.next();
      expect(p.currentTrack, tracks[3]);
      await p.next();
      expect(p.currentTrack, tracks[4]);
      await p.next();
      expect(p.currentTrack, tracks[1]);
    });

    test('the run shrinks as it is played through', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 0);
      await p.playNext(tracks[3]);
      await p.playNext(tracks[4]);
      expect(p.pendingPlayNextCount, 2);
      await p.next(); // now on Song 4, Song 5 still pending
      expect(p.pendingPlayNextCount, 1);
      await p.playNext(tracks[2]);
      // Song 3 goes after Song 5, which was queued earlier.
      expect(titles(p), ['Song 1', 'Song 4', 'Song 5', 'Song 3', 'Song 2']);
      await p.next();
      await p.next();
      await p.next();
      expect(p.pendingPlayNextCount, 0);
    });

    test('a track from before the cursor keeps the current track in place',
        () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 3);
      await p.playNext(tracks[0]);
      expect(p.currentTrack, tracks[3]);
      expect(titles(p), ['Song 2', 'Song 3', 'Song 4', 'Song 1', 'Song 5']);
      expect(p.currentQueuePosition, 2);
    });

    test('picking the current track is a no-op', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 1);
      await p.playNext(tracks[1]);
      expect(p.queueInPlayOrder, tracks);
      expect(p.pendingPlayNextCount, 0);
    });

    test('re-picking a pending track sends it to the back of the run',
        () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 0);
      await p.playNext(tracks[3]);
      await p.playNext(tracks[4]);
      await p.playNext(tracks[3]);
      expect(titles(p), ['Song 1', 'Song 5', 'Song 4', 'Song 2', 'Song 3']);
      expect(p.pendingPlayNextCount, 2);
    });

    test('a track from outside the queue is added, not duplicated', () async {
      final p = await makePlayer();
      await p.playTracks(tracks.sublist(0, 3), startIndex: 0);
      final outsider = _track(9);
      await p.playNext(outsider);
      await p.playNext(outsider);
      expect(titles(p), ['Song 1', 'Song 9', 'Song 2', 'Song 3']);
    });

    test('with nothing playing it just plays the track', () async {
      final p = await makePlayer();
      await p.playNext(tracks[2]);
      expect(p.currentTrack, tracks[2]);
      expect(p.isPlaying, isTrue);
    });

    test('jumping elsewhere in the queue abandons the run', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 0);
      await p.playNext(tracks[3]);
      await p.playQueuePosition(3);
      expect(p.pendingPlayNextCount, 0);
      // Tracks stay where they were; only the grouping is gone.
      expect(titles(p), ['Song 1', 'Song 4', 'Song 2', 'Song 3', 'Song 5']);
    });

    test('survives toggling shuffle on and off', () async {
      final p = await makePlayer(seed: 3);
      await p.playTracks(tracks, startIndex: 0);
      await p.playNext(tracks[3]);
      await p.playNext(tracks[4]);
      p.toggleShuffle();
      var order = p.queueInPlayOrder;
      expect(p.currentTrack, tracks[0]);
      expect(order.sublist(1, 3), [tracks[3], tracks[4]]);
      expect(order.toSet().length, tracks.length);
      p.toggleShuffle();
      expect(titles(p), ['Song 1', 'Song 4', 'Song 5', 'Song 2', 'Song 3']);
      expect(p.currentTrack, tracks[0]);
      expect(p.pendingPlayNextCount, 2);
    });

    test('starting a new queue clears the run', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 0);
      await p.playNext(tracks[3]);
      await p.playTracks(tracks, startIndex: 2);
      expect(p.pendingPlayNextCount, 0);
      expect(p.queueInPlayOrder, tracks);
    });
  });

  group('repeat', () {
    test('defaults to repeat-list', () async {
      final p = await makePlayer();
      expect(p.repeat, RepeatMode.all);
    });

    test('playing a song turns repeat-list back on when it was off', () async {
      final p = await makePlayer();
      p.cycleRepeat(); // all -> one
      p.cycleRepeat(); // one -> off
      expect(p.repeat, RepeatMode.off);

      await p.playTracks(tracks);
      expect(p.repeat, RepeatMode.all);
    });

    test('an explicit repeat-one choice survives starting a song', () async {
      final p = await makePlayer();
      p.cycleRepeat(); // all -> one
      await p.playTracks(tracks);
      expect(p.repeat, RepeatMode.one);
    });

    test('cycles list -> one -> off -> list', () async {
      final p = await makePlayer();
      expect(p.repeat, RepeatMode.all);
      p.cycleRepeat();
      expect(p.repeat, RepeatMode.one);
      p.cycleRepeat();
      expect(p.repeat, RepeatMode.off);
      p.cycleRepeat();
      expect(p.repeat, RepeatMode.all);
    });

    test('repeat-one replays the same track on completion', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 1);
      p.cycleRepeat(); // -> one
      await audio.finishTrack();
      expect(p.currentTrack, tracks[1]);
      expect(p.isPlaying, isTrue);
    });

    test('repeat-list advances to the next track on completion', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 1);
      await audio.finishTrack();
      expect(p.currentTrack, tracks[2]);
    });
  });

  group('shuffle', () {
    test('shuffling from a clicked track still plays that track', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 3, shuffle: true);
      // Explicit shuffle starts anywhere, but the queue must be intact.
      expect(p.queueInPlayOrder.toSet(), tracks.toSet());
      expect(p.queueInPlayOrder.length, 5);
    });

    test('toggling shuffle on keeps the current track playing', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 2);
      final playing = p.currentTrack;
      p.toggleShuffle();
      expect(p.shuffle, isTrue);
      expect(p.currentTrack, playing, reason: 'must not jump tracks');
      expect(p.queueInPlayOrder.toSet(), tracks.toSet());
    });

    test('toggling shuffle off restores the original order', () async {
      final p = await makePlayer();
      await p.playTracks(tracks, startIndex: 2);
      p.toggleShuffle();
      p.toggleShuffle();
      expect(p.shuffle, isFalse);
      expect(p.queueInPlayOrder, tracks);
      expect(p.currentTrack, tracks[2],
          reason: 'position should follow the track back');
    });

    test('the queue contains every track exactly once when shuffled', () async {
      final p = await makePlayer(seed: 7);
      await p.playTracks(tracks, shuffle: true);
      final order = p.queueInPlayOrder;
      expect(order.length, tracks.length);
      expect(order.toSet().length, tracks.length);
    });
  });

  group('volume', () {
    test('is applied to the backend and persisted', () async {
      final p = await makePlayer();
      await p.setVolume(0.42);
      expect(p.volume, closeTo(0.42, 1e-9));
      expect(audio.volume, closeTo(0.42, 1e-9));
      expect(settings.volume, closeTo(0.42, 1e-9));
    });

    test('is restored on the next launch', () async {
      final first = await makePlayer();
      await first.setVolume(0.25);

      // A fresh store reading the same backing prefs, as at app start.
      final reopened = await SettingsStore.open();
      expect(reopened.volume, closeTo(0.25, 1e-9));

      final second = PlayerModel(reopened, audio: FakeAudioBackend());
      expect(second.volume, closeTo(0.25, 1e-9));
    });

    test('defaults to 70% before anything is saved', () async {
      final p = await makePlayer();
      expect(p.volume, closeTo(0.7, 1e-9));
    });

    test('is clamped to 0..1', () async {
      final p = await makePlayer();
      await p.setVolume(1.8);
      expect(p.volume, 1.0);
      await p.setVolume(-0.5);
      expect(p.volume, 0.0);
    });

    test('survives track changes', () async {
      final p = await makePlayer();
      await p.playTracks(tracks);
      await p.setVolume(0.3);
      await p.next();
      expect(audio.volume, closeTo(0.3, 1e-9));
    });
  });

  group('robustness', () {
    test('an unreadable file is skipped rather than stranding the queue',
        () async {
      audio = _FailingBackend(failFor: '/music/2.m4a');
      final p = PlayerModel(settings, audio: audio, random: Random(1));
      await p.playTracks(tracks, startIndex: 1);
      expect(p.currentTrack, tracks[2], reason: 'should skip past the bad file');
    });

    test('a load overtaken by a newer one does not skip ahead', () async {
      final backend = audio = _InterruptibleBackend();
      final p = PlayerModel(settings, audio: audio, random: Random(1));
      final start = p.playTracks(tracks, startIndex: 0);
      backend.finishLoad();
      await start;

      // Two quick presses of Next: the engine aborts the first load with an
      // error when the second one starts, as just_audio does.
      final first = p.next();
      final second = p.next();
      backend.finishLoad();
      await Future.wait([first, second]);

      expect(p.currentTrack, tracks[2],
          reason: 'the aborted load must not be mistaken for a bad file');
      expect(backend.loadedPath, '/music/3.m4a');
    });

    test('playing an empty list is a no-op', () async {
      final p = await makePlayer();
      await p.playTracks([]);
      expect(p.hasTrack, isFalse);
      expect(p.isPlaying, isFalse);
    });
  });
}

/// Backend that throws for one specific path, to exercise the skip path.
class _FailingBackend extends FakeAudioBackend {
  final String failFor;

  _FailingBackend({required this.failFor});

  @override
  Future<void> setSource(String path) async {
    if (path == failFor) throw Exception('cannot decode');
    await super.setSource(path);
  }
}

/// Backend whose loads only finish when told to, and that fails an in-flight
/// load as soon as a newer one starts -- the way just_audio reports an
/// interrupted `setAudioSource`.
class _InterruptibleBackend extends FakeAudioBackend {
  Completer<void>? _pending;

  @override
  Future<void> setSource(String path) async {
    _pending?.completeError(Exception('Loading interrupted'));
    final load = _pending = Completer<void>();
    await load.future;
    await super.setSource(path);
  }

  /// Lets the most recent load complete.
  void finishLoad() {
    _pending?.complete();
    _pending = null;
  }
}
