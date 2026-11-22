import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/player/player_model.dart';
import 'album_catalog.dart';

/// Keeps `player.json` beside the album catalog up to date with what the
/// player is doing: the song, whether it is playing, shuffle and repeat.
///
/// The Raycast extension's media commands read it after sending a command,
/// so they can say "Shuffle on" or name the next song rather than only
/// "Done". It is written only when one of those changes, never for the
/// playback position, so it costs nothing while a song plays on.
class PlayerStatusFile {
  final PlayerModel player;
  final Future<Directory?> Function() _directory;

  PlayerStatusFile(this.player, {Future<Directory?> Function()? directory})
    : _directory = directory ?? AlbumCatalog.sharedFolder;

  static const fileName = 'player.json';

  String? _written;
  Future<void> _writing = Future.value();

  void start() {
    player.addListener(_onPlayer);
    _onPlayer();
  }

  void dispose() => player.removeListener(_onPlayer);

  /// The file's contents for the player as it is now.
  @visibleForTesting
  String describe() {
    final track = player.currentTrack;
    return const JsonEncoder.withIndent(' ').convert({
      'format': 1,
      'playing': player.isPlaying,
      'shuffle': player.shuffle,
      'repeat': player.repeat.name,
      'track': track == null
          ? null
          : {
              'title': track.title,
              'artist': track.artist,
              'album': track.album,
              'path': track.path,
            },
    });
  }

  void _onPlayer() {
    final text = describe();
    if (text == _written) return;
    _written = text;
    // One write at a time, in order, so the file ends on the latest state.
    _writing = _writing.then((_) => _write(text));
  }

  /// Done once every change so far has reached the file.
  @visibleForTesting
  Future<void> get settled => _writing;

  Future<void> _write(String text) async {
    try {
      final dir = await _directory();
      if (dir == null) return;
      await dir.create(recursive: true);
      final file = File('${dir.path}/$fileName');
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(text);
      await temp.rename(file.path);
    } catch (e) {
      debugPrint('Could not write the player status: $e');
    }
  }
}
