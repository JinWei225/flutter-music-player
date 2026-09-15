import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/track.dart';
import '../../core/player/player_model.dart';

/// A library row's "Play Next" callback: queues [track] after the current
/// song (or after whatever was already queued that way) and says so, since
/// on a phone the queue is out of sight when this is chosen.
VoidCallback playNextAction(BuildContext context, Track track) {
  return () {
    context.read<PlayerModel>().playNext(track);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Playing next: ${track.title}'),
          duration: const Duration(seconds: 2),
        ),
      );
  };
}
