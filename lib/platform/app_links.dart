import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/library/library_links.dart';

/// Receives the `mewsic://` links macOS hands the app: opened from Raycast,
/// Shortcuts or `open`, or picked as a Spotlight result.
///
/// Links that arrive before anyone is listening (the one that launched the
/// app, typically) are held and delivered once [listener] is set.
class AppLinks {
  static final instance = AppLinks();

  static const _channel = MethodChannel('com.jinwei.custom_music_player/links');

  final _waiting = <LibraryLink>[];
  ValueChanged<LibraryLink>? _listener;

  /// Starts taking links from the platform, including any that arrived
  /// before Dart was running.
  Future<void> start() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') _receive(call.arguments as String);
    });
    try {
      final early = await _channel.invokeListMethod<String>('ready');
      early?.forEach(_receive);
    } on MissingPluginException {
      // Not on a platform with links.
    }
  }

  /// Who gets each link. Setting it delivers anything held so far.
  set listener(ValueChanged<LibraryLink>? listener) {
    _listener = listener;
    if (listener == null) return;
    final held = [..._waiting];
    _waiting.clear();
    held.forEach(listener);
  }

  /// Handles [text] as if the platform had just opened it.
  @visibleForTesting
  void receive(String text) => _receive(text);

  void _receive(String text) {
    final link = LibraryLink.parse(text);
    if (link == null) {
      debugPrint('Ignoring link the app does not know: $text');
      return;
    }
    final listener = _listener;
    if (listener == null) {
      _waiting.add(link);
    } else {
      listener(link);
    }
  }
}
