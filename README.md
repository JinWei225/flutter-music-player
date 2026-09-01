# Mewsic

A music player for a local library — the songs already on your disk, not a
streaming service. Built with Flutter for Linux desktop and Android, with
macOS and Windows targets in the tree.

## Features

- **All Songs** and **Albums** pages, with albums opening to their own track
  listing.
- **Sorting** by title, artist or album, ascending or descending, chosen from
  a single menu.
- **Play All** and **Shuffle** on every album, following the album's own track
  order rather than filename order.
- **Playback controls**: play/pause, next/previous, shuffle, repeat
  (list / one / off), queue, and a volume slider.
- **Volume persists** across restarts. Repeat defaults to *list*, and starting
  playback never leaves repeat off.
- **Space** toggles play/pause on desktop.
- **Light and dark themes**, remembered between launches.
- **Background playback on Android**, with lock-screen and notification
  controls and cover art.
- Layout adapts: a sidebar and full player bar on desktop, bottom navigation
  and a mini player that expands to a full now-playing screen on a phone.

Supported files: `.m4a`, `.mp4`, `.m4b`, `.mp3`, `.aac`.

## Where it looks for music

| Platform | Library source |
| --- | --- |
| Linux, Windows | `~/Music` (`%USERPROFILE%\Music` on Windows), scanned recursively |
| macOS | `~/Music`, plus the Apple Music library at `~/Music/Music/Media.localized` |
| Android | The system media library (MediaStore) |

Set `MEWSIC_MUSIC_DIR` to scan somewhere else instead — one path, or several
separated by `:` (`;` on Windows):

```bash
MEWSIC_MUSIC_DIR="$HOME/Music/Music/Media.localized" flutter run -d macos
```

On macOS the Apple Music library is named as a folder of its own because the
system fences it off behind the **Media & Apple Music** privacy permission: a
plain walk of `~/Music` is turned away at that door and would otherwise report
an empty library rather than a refused one.

## Building and running

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install)
3.47 or newer (Dart 3.13+). `flutter pub get` is run for you by
`flutter run` and `flutter build`.

```bash
git clone https://github.com/JinWei225/flutter-music-player.git
cd flutter-music-player
```

### Linux

Install the desktop toolchain and the audio backend:

```bash
sudo apt install -y clang cmake ninja-build pkg-config \
                    libgtk-3-dev libstdc++-14-dev libmpv-dev mpv
```

Run it directly:

```bash
flutter run -d linux
```

Or install it as a normal desktop application, so it appears in the GNOME
Activities search with its own icon:

```bash
./packaging/install.sh
```

That builds a release bundle and installs everything under `~/.local`:
the app in `~/.local/opt/`, a `.desktop` entry, icons at eight sizes, and a
`custom-music-player` symlink on your `PATH`. The bundle is *copied* out of
`build/`, so a later `flutter clean` cannot break the installed copy. Re-run
the script after any change; `./packaging/install.sh --uninstall` removes it.

### Android

You need a JDK and the Android SDK. `cmdline-tools` is the piece Flutter
needs for licences and is not always installed by default — get it from
Android Studio's SDK Manager (*SDK Tools → Android SDK Command-line Tools*),
or unzip the standalone download into `$ANDROID_HOME/cmdline-tools/latest`.

```bash
sudo apt install -y openjdk-21-jdk
flutter doctor --android-licenses   # accept them once
flutter doctor                      # should show the Android toolchain green
```

With a device connected and USB debugging on:

```bash
flutter run -d android
```

To build an APK you can sideload:

```bash
flutter build apk --release
# build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The app asks for audio access on first launch; without it the library reads
as empty. Note that the release build is signed with Flutter's debug keys —
fine for your own devices, not for distribution.

### macOS

Needs Xcode from the App Store and CocoaPods (`sudo gem install cocoapods`).

```bash
flutter build macos --release
open build/macos/Build/Products/Release/
```

Drag **Mewsic.app** into `/Applications`. On first launch, right-click the app
and choose *Open* — it is unsigned, so Gatekeeper refuses a plain double-click
once.

The macOS runner is sandboxed, and the entitlements grant read access to
`~/Music`. Without that entitlement the song list comes up empty.

Songs managed by Apple Music live in `~/Music/Music/Media.localized`, which
macOS protects separately. The first launch asks for **Media & Apple Music**
access; if it was declined, turn it back on in *System Settings → Privacy &
Security → Media & Apple Music* and reopen the app. Until then Mewsic says so
on its empty state instead of pretending the library is empty.

### Windows

Needs Visual Studio 2022 with the **Desktop development with C++** workload
(the C++ toolchain, not just an editor).

```powershell
flutter build windows --release
```

The output is `build\windows\x64\runner\Release\`, containing `Mewsic.exe`
alongside its DLLs and a `data` folder. There is no installer: copy that whole
folder somewhere such as `C:\Program Files\Mewsic` and make a shortcut to the
executable. Keep the folder together — the executable will not run on its own.

## Development

```bash
flutter analyze
flutter test
```

The suite covers tag parsing, album grouping, sorting, the queue with shuffle
and repeat, volume persistence, and both the desktop and phone layouts.

Most tests build their own fixtures, but `test/metadata_test.dart` and
`test/ui_test.dart` read the real music folders and assert against the
specific library they were written for (11 tracks, two albums). **They will
fail on a fresh clone with a different library** — that is expected; the rest
of the suite is self-contained. `MEWSIC_MUSIC_DIR` points them at a fixture
library if you have one.

`packaging/make_icons.py` generates every icon from the same Material glyph
the app shows in its sidebar, so the launcher, notification and in-app marks
cannot drift apart:

```bash
python3 packaging/make_icons.py packaging/icons              # desktop
python3 packaging/make_icons.py --android android/app/src/main/res
python3 packaging/make_icons.py --album-placeholder assets/album_placeholder.png
```

## How it is put together

```
lib/
  core/          pure Dart, no platform code
    metadata/    MP4 and ID3 tag parsers
    models/      Track, Album
    library/     scanning and sort state
    player/      queue, shuffle, repeat, volume
  platform/      the platform seams
  ui/            pages and widgets
```

Two interfaces keep the core portable. `LibrarySource` supplies tracks — a
directory scan on desktop, MediaStore on Android. `AudioBackend` plays them —
media_kit (libmpv) on Linux and Windows, ExoPlayer on Android, AVPlayer on
macOS. Because the player talks only to those interfaces, the queue, shuffle
and repeat rules are tested without an audio device.

### Why the tag parsing is hand-written

Store-bought AAC files defeat the usual readers, so metadata is parsed in-app
rather than trusted from the operating system:

- iTunes writes an **empty** `udta/meta/ilst` inside every `trak`, alongside
  the real one at `moov` level. A parser that takes the first `ilst` it finds
  reports blank titles.
- The `moov` box is often written *after* `mdat`, so the tree has to be walked
  by box size rather than assumed to sit near the start of the file.
- Some downloads carry **only** the sort-name atoms (`sonm` / `soar` / `soal`)
  with no `©nam` / `©ART` / `©alb` at all. Android's own media scanner reports
  these as `<unknown>` with the filename as the title; Mewsic falls back to the
  sort atoms and reads them correctly.
- When a file has no `trkn` atom, the track number falls back to the leading
  digits of its filename, so the album keeps its running order.
- A guest credit such as *"NAYEON & SAM KIM"* folds into the lead artist so it
  does not split an album, while two genuinely different artists who share an
  album title stay apart.

On Android the MediaStore index is the starting point, but any row that looks
like a scanner fallback is re-read with these parsers.

## Known limitations

- **macOS and Windows are compile-ready but unrun.** Both targets are wired up
  and their platform code is in place, but neither has been built or tested on
  real hardware.
- **No background playback on desktop** — closing the window stops audio. The
  media session is Android-only.
- **Album art** is read from a file's embedded cover when present. Files
  without one show a neutral tile; no artwork is fetched from the internet.
- **No playlists, search, or library editing.**
