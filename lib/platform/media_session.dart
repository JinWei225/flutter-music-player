import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:just_audio/just_audio.dart';

import '../core/models/track.dart';
import '../core/player/player_model.dart';
import 'artwork_cache.dart';

/// Bridges the app's [PlayerModel] to Android's media session, which is what
/// keeps audio alive in the background and draws the lock-screen and
/// notification controls.
///
/// The handler owns the [AudioPlayer] so that the session and the app drive the
/// same player. [PlayerModel] stays the single source of truth for the queue,
/// shuffle and repeat; transport buttons from the notification are forwarded to
/// it, and its notifications are mirrored back out as session state.
class MewsicAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer player = AudioPlayer();
  final ArtworkCache _artwork = ArtworkCache();

  PlayerModel? _model;

  /// Art lookup is async. A track is published once its cover is ready; only
  /// a cover slower than [_artworkGrace] is attached afterwards. Tracks which
  /// track that resolution was for, so a slow read cannot attach the wrong
  /// cover after a skip.
  String? _artworkPendingFor;

  /// How long a new track waits for its cover before it is published without
  /// one. A cover that arrives after its item is easily missed by the system
  /// UI -- the notification keeps the app icon -- so it is worth a short wait,
  /// but not an unbounded one.
  static const _artworkGrace = Duration(milliseconds: 1500);

  MewsicAudioHandler() {
    // Position/buffering changes come straight from the player.
    player.playbackEventStream.listen(
      (_) => _publish(),
      onError: (Object _, StackTrace _) => _publish(),
    );
  }

  /// Connects the handler to the app's player. Called once at startup, after
  /// [PlayerModel] has been built around this handler's [player].
  void bind(PlayerModel model) {
    _model = model;
    model.addListener(_publish);
    _publish();
  }

  // --- commands from the notification / lock screen -------------------------

  @override
  Future<void> play() async => _model?.resume();

  @override
  Future<void> pause() async => _model?.pause();

  @override
  Future<void> skipToNext() async => _model?.next();

  @override
  Future<void> skipToPrevious() async => _model?.previous();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  // --- state published to the session ---------------------------------------

  void _publish() {
    final model = _model;
    final track = model?.currentTrack;

    if (track != null) {
      final current = mediaItem.value;
      if (current != null && current.id == track.path) {
        if (current.title != track.title ||
            current.artist != track.artist ||
            current.album != track.album ||
            current.duration != track.duration) {
          // Same file, new tags (Edit Info on the playing track): the cover is
          // unchanged, so keep whatever art has already been resolved.
          mediaItem.add(_toMediaItem(track, artUri: current.artUri));
        }
      } else if (_artworkPendingFor != track.path) {
        _publishWithArtwork(track);
      }
    } else {
      _artworkPendingFor = null;
      if (mediaItem.value != null) mediaItem.add(null);
    }

    final playing = player.playing;
    playbackState.add(
      playbackState.value.copyWith(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        systemActions: const {MediaAction.seek},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: _processingState,
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: model?.currentQueuePosition,
      ),
    );
  }

  AudioProcessingState get _processingState =>
      switch (player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      };

  /// Publishes [track] with its cover attached, so the system never sees the
  /// item without art. A cover slower than [_artworkGrace] is attached once it
  /// arrives instead.
  Future<void> _publishWithArtwork(Track track) async {
    _artworkPendingFor = track.path;
    final art = _artwork.uriFor(track);
    // If a skip returns below before `art` is awaited again, its failure
    // would otherwise surface as an unhandled error.
    art.ignore();

    Uri? uri;
    var timedOut = false;
    try {
      uri = await art.timeout(_artworkGrace);
    } on TimeoutException {
      timedOut = true;
    } catch (e) {
      debugPrint('Could not resolve artwork for ${track.title}: $e');
    }
    if (_superseded(track)) return;
    mediaItem.add(_toMediaItem(_latest(track), artUri: uri));
    if (!timedOut) return;

    try {
      uri = await art;
    } catch (e) {
      debugPrint('Could not resolve artwork for ${track.title}: $e');
      return;
    }
    if (_superseded(track)) return;
    mediaItem.add(_toMediaItem(_latest(track), artUri: uri));
  }

  /// True once a skip has moved on from [track] while its cover was loading.
  bool _superseded(Track track) {
    final stale = _artworkPendingFor != track.path ||
        _model?.currentTrack?.path != track.path;
    // Nothing else will publish this track if it comes back later while the
    // marker still says it is in progress.
    if (stale && _artworkPendingFor == track.path) _artworkPendingFor = null;
    return stale;
  }

  /// [track] as the model holds it now: its tags may have been edited while
  /// the cover was loading.
  Track _latest(Track track) {
    final now = _model?.currentTrack;
    return now != null && now.path == track.path ? now : track;
  }

  static MediaItem _toMediaItem(Track track, {required Uri? artUri}) =>
      MediaItem(
        id: track.path,
        title: track.title,
        artist: track.artist,
        album: track.album,
        duration: track.duration,
        artUri: artUri,
      );
}
