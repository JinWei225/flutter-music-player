import 'package:just_audio/just_audio.dart';

/// The slice of audio-engine behaviour [PlayerModel] depends on.
///
/// Keeping it behind an interface means the queue, shuffle and repeat rules can
/// be tested without an audio device, and lets a platform swap in a different
/// engine (media_kit on Linux/Windows, ExoPlayer/AVPlayer on mobile) without
/// the player logic changing.
abstract class AudioBackend {
  bool get playing;
  Duration get position;

  /// True once the current track has run to its end.
  bool get completed;

  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;

  /// Fires when the current track finishes.
  Stream<void> get completions;

  /// Fires on any playback-state change worth repainting for.
  Stream<void> get stateChanges;

  /// Loads a track. [source] is either an absolute file path (desktop) or a
  /// URI such as `content://` (Android MediaStore).
  Future<void> setSource(String source);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

/// Production backend. On Linux and Windows just_audio is served by media_kit
/// (libmpv), which is initialised in `main`; on Android it uses ExoPlayer and
/// on Apple platforms AVPlayer.
class JustAudioBackend implements AudioBackend {
  final AudioPlayer _player;

  /// [player] can be supplied so the Android media session and this backend
  /// drive the same underlying player rather than two competing ones.
  JustAudioBackend({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  @override
  bool get playing => _player.playing;

  @override
  Duration get position => _player.position;

  @override
  bool get completed => _player.processingState == ProcessingState.completed;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<void> get completions => _player.playerStateStream
      .where((s) => s.processingState == ProcessingState.completed);

  @override
  Stream<void> get stateChanges => _player.playerStateStream;

  @override
  Future<void> setSource(String source) {
    // A bare path has no scheme; MediaStore hands us content:// URIs, which
    // ExoPlayer resolves directly.
    final uri = source.contains('://') ? Uri.parse(source) : Uri.file(source);
    return _player.setAudioSource(AudioSource.uri(uri));
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}
