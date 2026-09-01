import 'dart:io';

import 'package:custom_music_player/core/library/library_model.dart';
import 'package:custom_music_player/core/player/player_model.dart';
import 'package:custom_music_player/platform/library_source.dart';
import 'package:custom_music_player/platform/settings_store.dart';
import 'package:custom_music_player/ui/pages/all_songs_page.dart';
import 'package:custom_music_player/ui/shell.dart';
import 'package:custom_music_player/ui/theme.dart';
import 'package:custom_music_player/ui/widgets/mini_player.dart';
import 'package:custom_music_player/ui/widgets/now_playing_sheet.dart';
import 'package:custom_music_player/ui/widgets/player_bar.dart';
import 'package:custom_music_player/ui/widgets/queue_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test.dart' show FakeAudioBackend;

/// Drives the real UI against the real ~/Music library, with only the audio
/// engine faked out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final musicDir = Directory(
      '${Platform.environment['HOME']}${Platform.pathSeparator}Music');

  late FakeAudioBackend audio;
  late PlayerModel player;
  late LibraryModel library;
  late SettingsStore settings;

  Widget buildApp() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: library),
        ChangeNotifierProvider.value(value: player),
        ChangeNotifierProvider(create: (_) => ThemeController(settings)),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.mode,
          home: const AppShell(),
        ),
      ),
    );
  }

  /// The window must be wide enough for the sidebar + player bar layout.
  ///
  /// Scanning ~/Music is real file I/O, and it has to run inside `runAsync`:
  /// a widget test drives a fake clock, against which a real I/O future would
  /// never complete.
  Future<void> pumpApp(WidgetTester tester, {Size size = const Size(1600, 1000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await SettingsStore.open();
      audio = FakeAudioBackend();
      player = PlayerModel(settings, audio: audio);
      library = LibraryModel(DirectoryLibrarySource(musicDir));
      await library.load();
    });

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
  }

  testWidgets('All Songs lists every track with real tags', (tester) async {
    await pumpApp(tester);

    // "All Songs" is both the sidebar entry and the page heading, so scope
    // the check to the page itself.
    expect(
      find.descendant(
        of: find.byType(AllSongsPage),
        matching: find.text('All Songs'),
      ),
      findsOneWidget,
    );
    expect(find.text('11 songs'), findsOneWidget);
    // Titles come from the m4a tags, not the filenames.
    expect(find.text('ABCD'), findsWidgets);
    expect(find.text('Magic (feat. JULIE)'), findsWidgets);
    expect(find.text("Can't Slow Me, No"), findsWidgets);
  });

  testWidgets('sorting by artist reorders the list', (tester) async {
    await pumpApp(tester);

    library.setSort(SortField.artist, SortDirection.ascending);
    await tester.pumpAndSettle();
    expect(library.sortedTracks.first.artist, 'NAYEON');

    library.setSort(SortField.artist, SortDirection.descending);
    await tester.pumpAndSettle();
    expect(library.sortedTracks.first.artist, 'YEJI');
  });

  testWidgets('field and direction are chosen from one menu', (tester) async {
    await pumpApp(tester);

    // The button shows the field; its arrow and tooltip carry the direction.
    expect(find.byTooltip('Sort: Title A-Z'), findsOneWidget);

    await tester.tap(find.byTooltip('Sort: Title A-Z'));
    await tester.pumpAndSettle();
    // All six combinations are offered.
    expect(find.text('Title  Z-A'), findsOneWidget);
    expect(find.text('Artist  A-Z'), findsOneWidget);
    expect(find.text('Album  Z-A'), findsOneWidget);

    await tester.tap(find.text('Artist  Z-A'));
    await tester.pumpAndSettle();

    expect(library.sortField, SortField.artist);
    expect(library.sortDirection, SortDirection.descending);
    expect(find.byTooltip('Sort: Artist Z-A'), findsOneWidget);
  });

  testWidgets('the phone header fits without scrolling or wrapping',
      (tester) async {
    await pumpApp(tester, size: const Size(400, 860));

    // The sort control used to sit behind a horizontal scroll, off-screen.
    expect(tester.getRect(find.byTooltip('Sort: Title A-Z')).right,
        lessThanOrEqualTo(400));

    // And the action labels must stay on one line; when the sort menu shared
    // this row they wrapped to "Play / All" and "Shuffl / e".
    for (final label in ['Play All', 'Shuffle']) {
      expect(tester.getSize(find.text(label)).height, lessThan(24),
          reason: '"$label" wrapped onto a second line');
      expect(tester.getRect(find.text(label)).right, lessThanOrEqualTo(400));
    }

    // The heading must not be ellipsised into "All S...".
    final heading = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(AllSongsPage),
        matching: find.text('All Songs'),
      ),
    );
    expect(heading.didExceedMaxLines, isFalse,
        reason: 'the "All Songs" heading was truncated');
  });

  testWidgets('clicking a song plays that exact file', (tester) async {
    await pumpApp(tester);

    library.setSort(SortField.title, SortDirection.ascending);
    await tester.pumpAndSettle();

    await tester.tap(find.text('ABCD').first);
    await tester.pumpAndSettle();

    expect(player.currentTrack?.title, 'ABCD');
    expect(audio.loadedPath, contains('ABCD'));
    expect(player.isPlaying, isTrue);
  });

  testWidgets('Albums shows both albums and opens a detail page',
      (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();

    expect(find.text('2 albums'), findsOneWidget);
    expect(find.text('NA'), findsWidgets);
    expect(find.text('Air - EP'), findsWidgets);

    await tester.tap(find.text('Air - EP').first);
    await tester.pumpAndSettle();

    // Detail page: header, metadata line, and the two action buttons.
    expect(find.text('ALBUM'), findsOneWidget);
    expect(find.text('Play All'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);
    expect(find.textContaining('YEJI'), findsWidgets);
    expect(find.textContaining('4 songs'), findsOneWidget);
  });

  testWidgets('Play All queues the album in track order', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Air - EP').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play All'));
    await tester.pumpAndSettle();

    expect(player.shuffle, isFalse);
    expect(player.currentTrack?.title, 'Air');
    expect(
      player.queueInPlayOrder.map((t) => t.trackNumber),
      [1, 2, 3, 4],
    );
  });

  testWidgets('album Shuffle plays the album with shuffle on', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('NA').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shuffle'));
    await tester.pumpAndSettle();

    expect(player.shuffle, isTrue);
    expect(player.queueInPlayOrder.length, 7);
    expect(player.queueInPlayOrder.map((t) => t.album).toSet(), {'NA'});
  });

  testWidgets('the queue button opens the queue panel', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('ABCD').first);
    await tester.pumpAndSettle();

    expect(find.text('Queue'), findsNothing);
    await tester.tap(find.byTooltip('Show queue'));
    await tester.pumpAndSettle();

    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('11 songs'), findsWidgets);

    // Both the panel's close button and the player-bar toggle say "Hide
    // queue"; use the panel's own one.
    await tester.tap(find.descendant(
      of: find.byType(QueuePanel),
      matching: find.byTooltip('Hide queue'),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Queue'), findsNothing);
  });

  testWidgets('Space toggles play and pause', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('ABCD').first);
    await tester.pumpAndSettle();
    expect(player.isPlaying, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(player.isPlaying, isFalse, reason: 'Space should pause');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(player.isPlaying, isTrue, reason: 'Space should resume');
  });

  testWidgets('transport buttons move through the queue', (tester) async {
    await pumpApp(tester);

    library.setSort(SortField.album, SortDirection.ascending);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Air').first);
    await tester.pumpAndSettle();
    expect(player.currentTrack?.title, 'Air');

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(player.currentTrack?.title, 'Invasion');

    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    expect(player.currentTrack?.title, 'Air');
  });

  testWidgets('shuffle and repeat buttons report their state', (tester) async {
    await pumpApp(tester);

    expect(find.byTooltip('Shuffle: off'), findsOneWidget);
    await tester.tap(find.byTooltip('Shuffle: off'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Shuffle: on'), findsOneWidget);

    // Repeat starts on "list" before anything is played.
    expect(find.byTooltip('Repeat: list'), findsOneWidget);
    await tester.tap(find.byTooltip('Repeat: list'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Repeat: one'), findsOneWidget);
    await tester.tap(find.byTooltip('Repeat: one'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Repeat: off'), findsOneWidget);
  });

  testWidgets('the theme toggle switches between dark and light',
      (tester) async {
    await pumpApp(tester);

    // Dark is the default, so the toggle offers light.
    expect(find.text('Light mode'), findsOneWidget);
    await tester.tap(find.text('Light mode'));
    await tester.pumpAndSettle();

    expect(find.text('Dark mode'), findsOneWidget);
    expect(settings.darkMode, isFalse);
  });

  testWidgets('the volume slider persists its value', (tester) async {
    await pumpApp(tester);

    await player.setVolume(0.33);
    await tester.pumpAndSettle();

    expect(find.text('33'), findsOneWidget);
    expect(settings.volume, closeTo(0.33, 1e-9));
  });

  group('compact (phone) layout', () {
    // A typical phone in logical pixels; well under the 700 breakpoint.
    const phone = Size(400, 860);

    testWidgets('uses bottom navigation and a mini player, without overflow',
        (tester) async {
      await pumpApp(tester, size: phone);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(MiniPlayer), findsOneWidget);
      // The desktop chrome must be gone.
      expect(find.byType(PlayerBar), findsNothing);
      // The track count is dropped here so the heading is not truncated.
      expect(find.text('11 songs'), findsNothing);
      expect(find.text('ABCD'), findsWidgets);
    });

    testWidgets('the album column is dropped on a narrow screen',
        (tester) async {
      await pumpApp(tester, size: phone);

      expect(find.text('TITLE'), findsOneWidget);
      expect(find.text('ALBUM'), findsNothing);
      expect(find.text('ARTIST'), findsNothing);
      // Artist moves under the title instead of vanishing.
      expect(find.text('NAYEON'), findsWidgets);
    });

    testWidgets('tapping a song then the mini player opens the full player',
        (tester) async {
      await pumpApp(tester, size: phone);

      await tester.tap(find.text('ABCD').first);
      await tester.pumpAndSettle();
      expect(player.currentTrack?.title, 'ABCD');

      await tester.tap(find.byType(MiniPlayer));
      await tester.pumpAndSettle();

      // Every control the desktop bar has must be reachable here. The mini
      // player carries its own Next/Pause, so scope to the sheet.
      expect(find.byType(NowPlayingSheet), findsOneWidget);
      Finder inSheet(Finder f) =>
          find.descendant(of: find.byType(NowPlayingSheet), matching: f);

      expect(inSheet(find.byTooltip('Next')), findsOneWidget);
      expect(inSheet(find.byTooltip('Previous')), findsOneWidget);
      expect(inSheet(find.byTooltip('Shuffle: off')), findsOneWidget);
      expect(inSheet(find.byTooltip('Repeat: list')), findsOneWidget);
      expect(inSheet(find.text('Queue')), findsOneWidget);
    });

    testWidgets('navigating to Albums works from the bottom bar',
        (tester) async {
      await pumpApp(tester, size: phone);

      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(find.text('2 albums'), findsOneWidget);

      await tester.tap(find.text('Air - EP').first);
      await tester.pumpAndSettle();
      expect(find.text('Play All'), findsOneWidget);

      await tester.tap(find.text('Play All'));
      await tester.pumpAndSettle();
      expect(player.currentTrack?.title, 'Air');
    });
  });
}
