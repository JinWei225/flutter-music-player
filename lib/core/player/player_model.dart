import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../platform/settings_store.dart';
import '../models/track.dart';
import 'audio_backend.dart';

enum RepeatMode { off, all, one }

/// Owns the play queue and the shuffle/repeat/volume state, driving an
/// [AudioBackend] for the actual audio.
class PlayerModel extends ChangeNotifier {
  final AudioBackend _audio;
  final SettingsStore _settings;
  final Random _random;

  /// The queue in its original (unshuffled) order.
  List<Track> _queue = [];

  /// Indices into [_queue] giving playback order. Shuffling permutes this
  /// rather than the queue itself, so turning shuffle off restores the
  /// original order without having to re-derive it.
  List<int> _order = [];

  /// Cursor into [_order].
  int _position = -1;

  /// How many entries directly after [_position] were put there by
  /// [playNext] and have not been reached yet. A further "Play Next" lands
  /// after them rather than in front, so queuing A then B plays A, then B --
  /// the run grows at its tail like a small queue of its own. It shrinks as
  /// playback advances through it and is forgotten on any other jump.
  int _pendingPlayNext = 0;

  bool _shuffle = false;

  /// Repeat-all is the default, and starting playback never leaves it off.
  RepeatMode _repeat = RepeatMode.all;

  double _volume = 0.7;
  bool _disposed = false;
  final List<StreamSubscription<void>> _subscriptions = [];

  PlayerModel(this._settings, {AudioBackend? audio, Random? random})
    : _audio = audio ?? JustAudioBackend(),
      _random = random ?? Random() {
    _volume = _settings.volume;
    _audio.setVolume(_volume);
    _subscriptions.add(_audio.completions.listen((_) => _onTrackCompleted()));
    _subscriptions.add(_audio.stateChanges.listen((_) => _safeNotify()));
  }

  // --- state ----------------------------------------------------------------

  bool get isPlaying => _audio.playing;
  bool get hasTrack => currentTrack != null;
  bool get shuffle => _shuffle;
  RepeatMode get repeat => _repeat;
  double get volume => _volume;

  Track? get currentTrack {
    final i = _currentQueueIndex;
    return i == null ? null : _queue[i];
  }

  int? get _currentQueueIndex {
    if (_position < 0 || _position >= _order.length) return null;
    return _order[_position];
  }

  /// The queue in playback order, for the queue panel.
  List<Track> get queueInPlayOrder => [for (final i in _order) _queue[i]];

  /// Swaps in a re-tagged copy of a queued track so the bar, the panel and
  /// the system's now-playing info show the new names without a reload.
  void replaceTrack(Track updated) {
    var changed = false;
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i] == updated) {
        _queue[i] = updated;
        changed = true;
      }
    }
    if (changed) _safeNotify();
  }

  /// Index of the now-playing track within [queueInPlayOrder].
  int get currentQueuePosition => _position;

  /// Number of tracks after the current one that were queued with
  /// [playNext] and are still to come.
  int get pendingPlayNextCount => _pendingPlayNext;

  Stream<Duration> get positionStream => _audio.positionStream;
  Stream<Duration?> get durationStream => _audio.durationStream;

  // --- playback -------------------------------------------------------------

  /// Replaces the queue and starts playing.
  ///
  /// [startIndex] indexes into [tracks] as given. Passing [shuffle] sets the
  /// shuffle mode; `true` also starts from a random track rather than
  /// [startIndex], which is what the "Shuffle" buttons want.
  Future<void> playTracks(
    List<Track> tracks, {
    int startIndex = 0,
    bool? shuffle,
  }) async {
    if (tracks.isEmpty) return;

    _queue = List.of(tracks);
    _pendingPlayNext = 0;
    if (shuffle != null) _shuffle = shuffle;

    // Starting playback always leaves repeat at least on "list"; an explicit
    // repeat-one choice is preserved.
    if (_repeat == RepeatMode.off) _repeat = RepeatMode.all;

    final start = startIndex.clamp(0, _queue.length - 1);
    _order = List.generate(_queue.length, (i) => i);

    if (_shuffle) {
      _order.shuffle(_random);
      if (shuffle != true) {
        // A clicked track must still be the one that plays; shuffle the rest.
        _order.remove(start);
        _order.insert(0, start);
      }
      _position = 0;
    } else {
      _position = start;
    }

    await _loadCurrent(autoPlay: true);
  }

  /// Jumps to a position within the existing playback order.
  Future<void> playQueuePosition(int position) async {
    if (position < 0 || position >= _order.length) return;
    _moveTo(position);
    await _loadCurrent(autoPlay: true);
  }

  /// Queues [track] to play after the current one -- or, when something has
  /// already been queued that way, after the last of those, so repeated
  /// "Play Next" picks play in the order they were chosen.
  ///
  /// A track already in the queue is moved rather than duplicated; one from
  /// outside it is added. With nothing playing it simply starts playing.
  Future<void> playNext(Track track) async {
    if (_order.isEmpty) {
      await playTracks([track]);
      return;
    }
    final current = _currentQueueIndex;
    if (current != null && _queue[current] == track) return;

    var queueIndex = _queue.indexOf(track);
    if (queueIndex < 0) {
      _queue.add(track);
      queueIndex = _queue.length - 1;
    } else {
      final at = _order.indexOf(queueIndex);
      _order.removeAt(at);
      if (at < _position) {
        _position--;
      } else if (at <= _position + _pendingPlayNext) {
        // It was already in the run; it now goes to the back of it.
        _pendingPlayNext--;
      }
    }
    _order.insert(_position + 1 + _pendingPlayNext, queueIndex);
    _pendingPlayNext++;
    _safeNotify();
  }

  Future<void> togglePlayPause() => _audio.playing ? pause() : resume();

  /// Explicit start, as opposed to [togglePlayPause]. The media-session
  /// controls use these so a notification button can never invert the state
  /// it was showing.
  Future<void> resume() async {
    if (!hasTrack) return;
    // Restart from the top if the last track ran to the end.
    if (_audio.completed) await _audio.seek(Duration.zero);
    await _audio.play();
    _safeNotify();
  }

  Future<void> pause() async {
    if (!hasTrack) return;
    await _audio.pause();
    _safeNotify();
  }

  Future<void> next() async {
    if (_order.isEmpty) return;
    if (_position + 1 < _order.length) {
      _moveTo(_position + 1);
    } else if (_repeat != RepeatMode.off) {
      _moveTo(0);
    } else {
      await _audio.pause();
      await _audio.seek(Duration.zero);
      _safeNotify();
      return;
    }
    await _loadCurrent(autoPlay: true);
  }

  /// Restarts the current track if it is already a few seconds in, matching
  /// what every other music player does with a "previous" press.
  Future<void> previous() async {
    if (_order.isEmpty) return;
    if (_audio.position > const Duration(seconds: 3)) {
      await _audio.seek(Duration.zero);
      _safeNotify();
      return;
    }
    if (_position > 0) {
      _moveTo(_position - 1);
    } else if (_repeat != RepeatMode.off) {
      _moveTo(_order.length - 1);
    } else {
      await _audio.seek(Duration.zero);
      _safeNotify();
      return;
    }
    await _loadCurrent(autoPlay: true);
  }

  Future<void> seek(Duration to) => _audio.seek(to);

  // --- modes ----------------------------------------------------------------

  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_queue.isEmpty) {
      _safeNotify();
      return;
    }

    final current = _currentQueueIndex;
    // Whatever was queued with "Play Next" still plays next: it is lifted
    // out before the order is rebuilt and put straight back after the
    // current track.
    final pending = _order.sublist(
      _position + 1,
      _position + 1 + _pendingPlayNext,
    );
    if (_shuffle) {
      _order = List.generate(_queue.length, (i) => i)..shuffle(_random);
      if (current != null) {
        // Keep playing the current track; reshuffle everything around it.
        _order.remove(current);
        _order.insert(0, current);
        _position = 0;
      }
    } else {
      _order = List.generate(_queue.length, (i) => i);
      _position = current ?? 0;
    }
    if (pending.isNotEmpty) {
      _order.removeWhere(pending.contains);
      _position = _order.indexOf(current!);
      _order.insertAll(_position + 1, pending);
    }
    _safeNotify();
  }

  void cycleRepeat() {
    _repeat = switch (_repeat) {
      RepeatMode.all => RepeatMode.one,
      RepeatMode.one => RepeatMode.off,
      RepeatMode.off => RepeatMode.all,
    };
    _safeNotify();
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    await _audio.setVolume(_volume);
    _safeNotify();
    await _settings.setVolume(_volume);
  }

  // --- internals ------------------------------------------------------------

  /// Moves the cursor, keeping the play-next run in step: stepping forward
  /// into it consumes that many entries, anything else abandons the run
  /// (the tracks stay where they are, they just stop counting as "next").
  void _moveTo(int position) {
    final ahead = position - _position;
    _pendingPlayNext = ahead > 0 && ahead <= _pendingPlayNext
        ? _pendingPlayNext - ahead
        : 0;
    _position = position;
  }

  Future<void> _loadCurrent({bool autoPlay = false}) async {
    final track = currentTrack;
    if (track == null) return;
    try {
      await _audio.setSource(track.path);
      await _audio.setVolume(_volume);
      if (autoPlay) await _audio.play();
    } catch (e) {
      debugPrint('Failed to play ${track.path}: $e');
      // A single unreadable file should not strand the queue.
      if (_position + 1 < _order.length) {
        _moveTo(_position + 1);
        await _loadCurrent(autoPlay: autoPlay);
        return;
      }
    }
    _safeNotify();
  }

  Future<void> _onTrackCompleted() async {
    if (_repeat == RepeatMode.one) {
      await _audio.seek(Duration.zero);
      await _audio.play();
      return;
    }
    await next();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subscriptions) {
      s.cancel();
    }
    _audio.dispose();
    super.dispose();
  }
}
