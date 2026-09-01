import 'package:audio_service/audio_service.dart';
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

  /// Art lookup is async, so the item is published without it first and
  /// republished once resolved. Tracks which track that resolution was for, so
  /// a slow read cannot attach the wrong cover after a skip.
  String? _artworkPendingFor;

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
      if (current?.id != track.path || current?.duration != track.duration) {
        mediaItem.add(_toMediaItem(track, artUri: null));
        _resolveArtwork(track);
      }
    } else if (mediaItem.value != null) {
      mediaItem.add(null);
      _artworkPendingFor = null;
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

  /// Loads the cover in the background and republishes the item with it.
  Future<void> _resolveArtwork(Track track) async {
    _artworkPendingFor = track.path;
    final uri = await _artwork.uriFor(track);

    // A skip may have landed while the file was being read.
    if (_artworkPendingFor != track.path) return;
    if (mediaItem.value?.id != track.path) return;

    mediaItem.add(_toMediaItem(track, artUri: uri));
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
