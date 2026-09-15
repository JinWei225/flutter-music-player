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
- **Play Next** on any track (right-click, long-press, or the hover menu, in
  the library or the queue itself) moves it to just after the current song.
  Picking a second track queues it *behind* the first, so a run of picks
  plays in the order you chose them.
- **Space** toggles play/pause on desktop.
- **Edit Info** on any track (right-click, long-press, or the hover menu)
  writes corrected tags back into the file itself, so the fix follows the
  file to every other device and player.
- **Light and dark themes**, remembered between launches.
- **Background playback on Android**, with lock-screen and notification
  controls and cover art.
- Layout adapts to the window: a sidebar, full player bar and a docked
  Now Playing panel (art and queue) on desktop; an icon rail with Now Playing
  sliding over the library on a tablet held upright; bottom navigation and a
  mini player that expands to a full now-playing screen on a phone.

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
as empty. Without a release keystore (see [Releases](#releases)) the build is
signed with Flutter's debug key — fine for your own devices, not for
distribution.

### macOS

Needs Xcode from the App Store and CocoaPods (`sudo gem install cocoapods`).

```bash
flutter build macos --release
open build/macos/Build/Products/Release/
```

Drag **Mewsic.app** into `/Applications`. On first launch, right-click the app
and choose *Open* — it is unsigned, so Gatekeeper refuses a plain double-click
once.

Or let a script do the build, signing and install in one go:

```bash
./packaging/install_app_macos.sh
```

macOS ties an app's privacy grants to its code signature, and an ad-hoc
signature changes with every build — so each reinstall would ask for
*Media & Apple Music* access again. To keep the grant across builds, create a
local signing certificate once (it asks for your login password to trust it):

```bash
./packaging/signing_identity_macos.sh
```

From then on `install_app_macos.sh` (and mewsic-tagfix's own install script)
sign with it automatically. The certificate is for this Mac only and has nothing to
do with Apple's developer program.

The macOS runner is sandboxed, and the entitlements grant read and write
access to `~/Music` (write is what lets *Edit Info* save tags). Without that
entitlement the song list comes up empty.

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

## Releases

Rebuilding on a laptop for every change gets old. Pushing a version tag has
GitHub Actions build the Android APK and the Linux bundle and attach both to
a GitHub Release (`.github/workflows/release.yml`):

```bash
git tag v1.1.0 && git push origin v1.1.0
```

A few minutes later the release page has `Mewsic-android.apk` and
`Mewsic-linux-x64.tar.gz`. The workflow can also be started from the Actions
tab without a tag; that produces the same files as run artifacts, without a
release.

**Android.** Install [Obtainium](https://github.com/ImranR98/Obtainium) on
the phone and add `https://github.com/JinWei225/flutter-music-player` as an
app: it watches the releases and installs each new APK with one tap, no
laptop or cable involved. Or just open the release page in the phone's
browser and download the APK.

Android only lets an APK update an installed app when both are signed with
the same key, and the CI runner's debug key is not your laptop's. So make a
release key once and give it to the workflow:

```bash
keytool -genkeypair -v -keystore ~/mewsic-release.keystore -alias mewsic         -keyalg RSA -keysize 2048 -validity 10000
```

Then in the repository's *Settings → Secrets and variables → Actions* add:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 ~/mewsic-release.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | the store password you chose |
| `ANDROID_KEY_ALIAS` | `mewsic` |
| `ANDROID_KEY_PASSWORD` | the key password (same as the store password unless you set one) |

The first release-signed APK has to be installed over an *uninstalled* app
(the debug-signed one has a different key); after that every release updates
in place. To sign local builds with the same key, put the keystore path and
passwords in `android/key.properties` (gitignored; the four `storeFile`,
`storePassword`, `keyAlias`, `keyPassword` entries) — `flutter build apk`
picks it up automatically. Keep the keystore somewhere safe: lose it and the
next release cannot update existing installs.

**Linux.** With a checkout of the repo but no Flutter toolchain:

```bash
./packaging/install.sh --latest
```

downloads the bundle from the latest release and installs it exactly as the
build-from-source path does.

## What is platform-specific

Most of the app is shared. These are the parts that only matter on one
platform — worth knowing which changes to ignore when you pick the project up
on a different machine.

| Path | Applies to |
| --- | --- |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/` | macOS only |
| `macos/Runner/*.entitlements` | macOS only |
| The second root in `MusicFolders.resolve()` | macOS only |
| `android/app/src/main/res/mipmap-*` and `drawable-*` | Android only |
| `MediaStoreLibrarySource` | Android only |
| `_accent` in `lib/ui/theme.dart` | every platform |
| `ACCENT_TOP` / `ACCENT_BOTTOM` in `packaging/make_icons.py` | every platform |

The macOS entitlement `com.apple.security.assets.music.read-write` is what lets
the sandboxed app read `~/Music` and save tag edits there; nothing else grants it. The extra scan root
is `~/Music/Music/Media.localized`, where Apple Music keeps purchased songs —
Linux and Windows scan `~/Music` alone and never see that path.

The accent colour lives in two places that do not talk to each other. Dart
never reads the icon gradient, so changing `_accent` alone leaves the launcher
icon on the old colour. Change both, then regenerate:

```bash
python3 packaging/make_icons.py --macos macos/Runner/Assets.xcassets/AppIcon.appiconset
python3 packaging/make_icons.py --android android/app/src/main/res
```

Both commands rewrite committed PNGs, so expect icon files in your diff even
when you only meant to touch one platform.

## Development

```bash
flutter analyze
flutter test
```

The suite covers album grouping, sorting, the queue with shuffle and repeat,
volume persistence, the Edit Info sheet, and both the desktop and phone
layouts; tag parsing and writing are tested in the mewsic-tagfix package.

Most tests build their own fixtures, but `test/metadata_test.dart` and
`test/ui_test.dart` read a real library from disk: 17 store-bought AAC
tracks across three albums, which are not in the repository. They skip
themselves until that library is in place, so a fresh clone still gets a
green run from the rest of the suite. On a machine with those albums in
Apple Music, copy them in once:

```bash
test/fixtures/sync.sh
```

That fills `test/fixtures/library` (gitignored). `MEWSIC_TEST_LIBRARY`
points the tests at a copy kept somewhere else.

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
    metadata/    RawTags -> Track; the parsers themselves come from mewsic_tagfix
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

Store-bought AAC files defeat the usual readers, so metadata is parsed by the
app rather than trusted from the operating system. The parsers, the tag
writer behind *Edit Info*, and the album-mate / store completion live in
their own package, [mewsic-tagfix](https://github.com/JinWei225/mewsic-tagfix),
pulled in as a git dependency (`mewsic_tagfix` in `pubspec.yaml`). What they
handle:

- iTunes writes an **empty** `udta/meta/ilst` inside every `trak`, alongside
  the real one at `moov` level. A parser that takes the first `ilst` it finds
  reports blank titles.
- The `moov` box is often written *after* `mdat`, so the tree has to be walked
  by box size rather than assumed to sit near the start of the file.
- Some downloads carry **only** the sort-name atoms (`sonm` / `soar` / `soal`)
  with no `©nam` / `©ART` / `©alb` at all. Android's own media scanner reports
  these as `<unknown>` with the filename as the title; Mewsic falls back to the
  sort atoms and reads them correctly.
- Some purchases arrive with **no names at all** -- just the iTunes Store IDs
  (`cnID` / `atID` / `plID`), a date and a copyright line. Apple's Music app
  shows them correctly only because it reads its own library database. Mewsic
  lets such a track borrow artist, album, album artist and genre from any
  album-mate that shares its store IDs, and on desktop falls back to the
  `Artist/Album/` folder layout after that.
- When a file has no `trkn` atom, the track number falls back to the leading
  digits of its filename, so the album keeps its running order.
- A guest credit such as *"NAYEON & SAM KIM"* folds into the lead artist so it
  does not split an album, while two genuinely different artists who share an
  album title stay apart.

On Android the MediaStore index is the starting point, but any row that looks
like a scanner fallback is re-read with these parsers.

### Fixing the files themselves: `mewsic-tagfix`

All of that recovery only helps inside Mewsic. To make such files right for
every player and device, the same logic can be run the other way -- written
*into* the files -- by the standalone command-line tool in that same repo:
[**mewsic-tagfix**](https://github.com/JinWei225/mewsic-tagfix). It also asks
the iTunes Store for the exact titles and the album cover, and can watch the
Apple Music folder to complete new purchases as they land. Usage and
installation are documented there.

To work on the shared code and see it in the app before tagging a release,
point the dependency at a local checkout:

```yaml
dependency_overrides:
  mewsic_tagfix:
    path: ../mewsic-tagfix
```

## Known limitations

- **macOS and Windows are compile-ready but unrun.** Both targets are wired up
  and their platform code is in place, but neither has been built or tested on
  real hardware.
- **No background playback on desktop** — closing the window stops audio. The
  media session is Android-only.
- **Album art** is read from a file's embedded cover when present. Files
  without one show a neutral tile; the app itself fetches nothing from the
  internet (`mewsic-tagfix` can embed the store's cover into the files).
- **No playlists or search.**
