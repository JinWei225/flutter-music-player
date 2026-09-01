import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:provider/provider.dart';

import 'core/library/library_model.dart';
import 'core/player/audio_backend.dart';
import 'core/player/player_model.dart';
import 'platform/library_source.dart';
import 'platform/media_session.dart';
import 'platform/media_store_library_source.dart';
import 'platform/settings_store.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // just_audio has no native backend on Linux/Windows; media_kit (libmpv)
  // supplies one. Android/iOS/macOS keep just_audio's own implementations.
  if (Platform.isLinux || Platform.isWindows) {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
  }

  // Scoped storage rules out walking a music folder on Android, so the system
  // media index is used there; desktop scans the user's Music directory.
  final LibrarySource source = Platform.isAndroid
      ? MediaStoreLibrarySource()
      : DirectoryLibrarySource.defaultLocation();

  final settings = await SettingsStore.open();
  final library = LibraryModel(source);

  // On Android a media session is what keeps playback running once the app is
  // backgrounded, and it supplies the lock-screen and notification controls.
  // The handler owns the player so both it and the app drive the same one.
  MewsicAudioHandler? mediaSession;
  if (Platform.isAndroid) {
    mediaSession = await AudioService.init(
      builder: MewsicAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.jinwei.custom_music_player.playback',
        androidNotificationChannelName: 'Playback',
        // A white silhouette; Android tints status-bar icons itself.
        androidNotificationIcon: 'drawable/ic_notification',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  }

  final player = PlayerModel(
    settings,
    audio: JustAudioBackend(player: mediaSession?.player),
  );
  mediaSession?.bind(player);

  runApp(MusicPlayerApp(
    settings: settings,
    library: library,
    player: player,
  ));

  // Scan after the first frame so the window appears immediately.
  library.load();
}

class MusicPlayerApp extends StatelessWidget {
  final SettingsStore settings;
  final LibraryModel library;
  final PlayerModel player;

  const MusicPlayerApp({
    super.key,
    required this.settings,
    required this.library,
    required this.player,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider(create: (_) => ThemeController(settings)),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: 'Mewsic',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.mode,
          home: const AppShell(),
        ),
      ),
    );
  }
}
