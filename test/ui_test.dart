import 'dart:io';

import 'package:custom_music_player/core/library/library_model.dart';
import 'package:custom_music_player/core/models/album.dart';
import 'package:custom_music_player/core/player/player_model.dart';
import 'package:custom_music_player/platform/library_source.dart';
import 'package:custom_music_player/platform/settings_store.dart';
import 'package:custom_music_player/ui/pages/all_songs_page.dart';
import 'package:custom_music_player/ui/shell.dart';
import 'package:custom_music_player/ui/theme.dart';
import 'package:custom_music_player/ui/widgets/edit_track_info_dialog.dart';
import 'package:custom_music_player/ui/widgets/mini_player.dart';
import 'package:custom_music_player/ui/widgets/now_playing_panel.dart';
import 'package:custom_music_player/ui/widgets/now_playing_sheet.dart';
import 'package:custom_music_player/ui/widgets/player_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mewsic_tagfix/mewsic_tagfix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test.dart' show FakeAudioBackend;

/// Drives the real UI against the real on-disk library, with only the audio
/// engine faked out.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAudioBackend audio;
  late PlayerModel player;
  late LibraryModel library;
  late SettingsStore settings;

  /// What the Edit Info sheet asked to write, instead of touching the
  /// real files in the music folder.
  final written = <(File, TagEdit)>[];

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
  /// Scanning the music folders is real file I/O, and it has to run inside `runAsync`:
  /// a widget test drives a fake clock, against which a real I/O future would
  /// never complete.
  Future<void> pumpApp(
    WidgetTester tester, {
    Size size = const Size(1600, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await SettingsStore.open();
      audio = FakeAudioBackend();
      player = PlayerModel(settings, audio: audio);
      written.clear();
      library = LibraryModel(
        DirectoryLibrarySource.defaultLocation(),
        writeTags: (file, edit) async => written.add((file, edit)),
      );
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
    expect(find.text('17 songs'), findsOneWidget);
    // Titles come from the m4a tags, not the filenames.
    expect(find.text('ABCD'), findsWidgets);
    expect(find.text('Magic (feat. JULIE)'), findsWidgets);
    expect(find.text('Can’t Slow Me, No'), findsWidgets);
  });

  testWidgets('sorting by artist reorders the list', (tester) async {
    await pumpApp(tester);

    library.setSort(SortField.artist, SortDirection.ascending);
    await tester.pumpAndSettle();
    expect(library.sortedTracks.first.artist, 'ITZY');

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

  testWidgets('the phone header fits without scrolling or wrapping', (
    tester,
  ) async {
    await pumpApp(tester, size: const Size(400, 860));

    // The sort control used to sit behind a horizontal scroll, off-screen.
    expect(
      tester.getRect(find.byTooltip('Sort: Title A-Z')).right,
      lessThanOrEqualTo(400),
    );

    // And the action labels must stay on one line; when the sort menu shared
    // this row they wrapped to "Play / All" and "Shuffl / e".
    for (final label in ['Play All', 'Shuffle']) {
      expect(
        tester.getSize(find.text(label)).height,
        lessThan(24),
        reason: '"$label" wrapped onto a second line',
      );
      expect(tester.getRect(find.text(label)).right, lessThanOrEqualTo(400));
    }

    // The heading must not be ellipsised into "All S...".
    final heading = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: find.byType(AllSongsPage),
        matching: find.text('All Songs'),
      ),
    );
    expect(
      heading.didExceedMaxLines,
      isFalse,
      reason: 'the "All Songs" heading was truncated',
    );
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

  testWidgets('Albums shows both albums and opens a detail page', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();

    expect(find.text('3 albums'), findsOneWidget);
    expect(find.text('NA'), findsWidgets);
    expect(find.text('AIR - EP'), findsWidgets);

    await tester.tap(find.text('AIR - EP').first);
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
    await tester.tap(find.text('AIR - EP').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play All'));
    await tester.pumpAndSettle();

    expect(player.shuffle, isFalse);
    expect(player.currentTrack?.title, 'Air');
    expect(player.queueInPlayOrder.map((t) => t.trackNumber), [1, 2, 3, 4]);
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

  testWidgets('Now Playing opens by itself on a wide window', (tester) async {
    await pumpApp(tester);

    // Nothing to show yet, so the panel stays out of the way.
    expect(find.byType(NowPlayingPanel), findsNothing);

    await tester.tap(find.text('ABCD').first);
    await tester.pumpAndSettle();

    expect(find.byType(NowPlayingPanel), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+ of 17$')), findsOneWidget);
    // The player bar keeps the transport; the panel does not repeat it.
    expect(find.byTooltip('Next'), findsOneWidget);

    // Both the panel's close button and the player-bar toggle say "Hide Now
    // Playing"; use the panel's own one.
    await tester.tap(
      find.descendant(
        of: find.byType(NowPlayingPanel),
        matching: find.byTooltip('Hide Now Playing'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingPanel), findsNothing);

    // Once closed it stays closed for the next track...
    await tester.tap(find.text('Air').first);
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingPanel), findsNothing);

    // ...until asked for again.
    await tester.tap(find.byTooltip('Show Now Playing'));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingPanel), findsOneWidget);
  });

  testWidgets('on a smaller window Now Playing docks only when asked', (
    tester,
  ) async {
    // Wide enough for the full sidebar, too narrow to auto-open the panel.
    await pumpApp(tester, size: const Size(1100, 800));

    await tester.tap(find.text('ABCD').first);
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingPanel), findsNothing);

    await tester.tap(find.byTooltip('Show Now Playing'));
    await tester.pumpAndSettle();
    expect(find.byType(NowPlayingPanel), findsOneWidget);

    // Docked, not overlaid: the panel ends at the window edge and the
    // library is still clickable beside it.
    expect(tester.getRect(find.byType(NowPlayingPanel)).right, 1100);
    await tester.tap(find.text('Air').first);
    await tester.pumpAndSettle();
    expect(player.currentTrack?.title, 'Air');
    expect(find.byType(NowPlayingPanel), findsOneWidget);
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

  testWidgets('the theme toggle switches between dark and light', (
    tester,
  ) async {
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

  group('Edit Info', () {
    testWidgets('right-clicking a row opens the editor pre-filled', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.text('CAKE').first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.text('Edit Info…'), findsOneWidget);

      await tester.tap(find.text('Edit Info…'));
      await tester.pumpAndSettle();

      expect(find.byType(EditTrackInfoDialog), findsOneWidget);
      expect(find.widgetWithText(TextField, 'CAKE'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'ITZY'), findsNWidgets(2));
      expect(find.widgetWithText(TextField, 'KILL MY DOUBT - EP'), findsOneWidget);
      expect(find.text('02 CAKE.m4a'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(EditTrackInfoDialog), findsNothing);
      expect(written, isEmpty);
    });

    testWidgets('saving writes the file and updates the list and albums', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.longPress(find.text('CAKE').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Info…'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'CAKE'), 'Cake');
      await tester.enterText(
          find.widgetWithText(TextField, 'KILL MY DOUBT - EP'), 'Kill My Doubt');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(EditTrackInfoDialog), findsNothing);
      expect(written.length, 1);
      expect(written.single.$1.path, endsWith('02 CAKE.m4a'));
      expect(written.single.$2.title, 'Cake');
      expect(written.single.$2.album, 'Kill My Doubt');
      expect(written.single.$2.artist, 'ITZY');
      expect(written.single.$2.trackNumber, 2);

      // The row reflects the edit without a rescan...
      expect(find.text('Cake'), findsWidgets);
      expect(find.text('Kill My Doubt'), findsWidgets);
      expect(find.textContaining('Saved to'), findsOneWidget);
      // ...and the albums regrouped around the new name.
      final names = library.albums.map((a) => a.name).toList();
      expect(names, contains('Kill My Doubt'));
      expect(Album.group(library.sortedTracks).length, 4);
    });

    testWidgets('a write failure is shown in the sheet, not swallowed', (
      tester,
    ) async {
      await pumpApp(tester);
      library = LibraryModel(
        library.source,
        writeTags: (_, _) async =>
            throw const TagWriteException('disk says no'),
      );
      await tester.runAsync(library.load);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('CAKE').first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Info…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(EditTrackInfoDialog), findsOneWidget);
      expect(find.text('disk says no'), findsOneWidget);
      expect(find.text('CAKE'), findsWidgets);
    });

    testWidgets('the playing track is renamed in the player bar too', (
      tester,
    ) async {
      await pumpApp(tester);

      await tester.tap(find.text('CAKE').first);
      await tester.pumpAndSettle();
      expect(player.currentTrack?.title, 'CAKE');

      await tester.tap(find.text('CAKE').first, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit Info…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'CAKE'), 'Cake');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(player.currentTrack?.title, 'Cake');
      expect(find.text('CAKE'), findsNothing);
    });
  });

  group('medium (portrait tablet) layout', () {
    // A 10-inch tablet held upright: past the phone breakpoint, but with no
    // room for the labelled sidebar and a docked panel.
    const tablet = Size(800, 1200);

    testWidgets('collapses the sidebar to an icon rail', (tester) async {
      await pumpApp(tester, size: tablet);

      expect(find.byType(PlayerBar), findsOneWidget);
      // Labels live in tooltips now; "Albums" is not drawn anywhere.
      expect(find.text('Albums'), findsNothing);
      expect(find.byTooltip('Albums'), findsOneWidget);
      expect(find.text('Light mode'), findsNothing);
      expect(find.byTooltip('Light mode'), findsOneWidget);

      await tester.tap(find.byTooltip('Albums'));
      await tester.pumpAndSettle();
      expect(find.text('3 albums'), findsOneWidget);
    });

    testWidgets('Now Playing slides over the library and dismisses on tap', (
      tester,
    ) async {
      await pumpApp(tester, size: tablet);

      await tester.tap(find.text('ABCD').first);
      await tester.pumpAndSettle();
      // Parked off-screen until asked for.
      expect(
        tester.getRect(find.byType(NowPlayingPanel)).left,
        greaterThanOrEqualTo(800),
      );

      await tester.tap(find.byTooltip('Show Now Playing'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(NowPlayingPanel)).right, 800);
      expect(find.text('Up next'), findsOneWidget);

      // Tapping the dimmed library closes the panel instead of hitting a song.
      await tester.tapAt(const Offset(150, 400));
      await tester.pumpAndSettle();
      expect(player.currentTrack?.title, 'ABCD');
      expect(
        tester.getRect(find.byType(NowPlayingPanel)).left,
        greaterThanOrEqualTo(800),
      );
    });
  });

  group('compact (phone) layout', () {
    // A typical phone in logical pixels; well under the 700 breakpoint.
    const phone = Size(400, 860);

    testWidgets('uses bottom navigation and a mini player, without overflow', (
      tester,
    ) async {
      await pumpApp(tester, size: phone);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(MiniPlayer), findsOneWidget);
      // The desktop chrome must be gone.
      expect(find.byType(PlayerBar), findsNothing);
      // The track count is dropped here so the heading is not truncated.
      expect(find.text('17 songs'), findsNothing);
      expect(find.text('ABCD'), findsWidgets);
    });

    testWidgets('the album column is dropped on a narrow screen', (
      tester,
    ) async {
      await pumpApp(tester, size: phone);

      expect(find.text('TITLE'), findsOneWidget);
      expect(find.text('ALBUM'), findsNothing);
      expect(find.text('ARTIST'), findsNothing);
      // Artist and album move under the title instead of vanishing.
      expect(find.text('NAYEON  ·  NA'), findsWidgets);
      expect(find.text('YEJI  ·  AIR - EP'), findsWidgets);
    });

    testWidgets('a tap anywhere on a row plays it, not just on its text', (
      tester,
    ) async {
      await pumpApp(tester, size: phone);

      // A finger never hovers, so the row used to accept taps only on the
      // text itself; the blank space right of the time did nothing.
      final row = tester.getRect(find.text('ABCD').first);
      await tester.tapAt(Offset(phone.width - 8, row.center.dy));
      await tester.pumpAndSettle();

      expect(player.currentTrack?.title, 'ABCD');
    });

    testWidgets('tapping a song then the mini player opens the full player', (
      tester,
    ) async {
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

    testWidgets('navigating to Albums works from the bottom bar', (
      tester,
    ) async {
      await pumpApp(tester, size: phone);

      await tester.tap(find.text('Albums'));
      await tester.pumpAndSettle();
      expect(find.text('3 albums'), findsOneWidget);

      await tester.tap(find.text('AIR - EP').first);
      await tester.pumpAndSettle();
      expect(find.text('Play All'), findsOneWidget);

      await tester.tap(find.text('Play All'));
      await tester.pumpAndSettle();
      expect(player.currentTrack?.title, 'Air');
    });
  });
}
