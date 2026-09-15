#!/bin/bash
# Build a release bundle and install it as a normal desktop application for the
# current user, so it shows up in the GNOME Activities search.
#
#   ./packaging/install.sh            build + install
#   ./packaging/install.sh --latest   download the latest GitHub release + install
#   ./packaging/install.sh --uninstall
#
# --latest skips the Flutter toolchain entirely: it fetches the bundle the
# Release workflow built (see .github/workflows/release.yml), so a laptop
# that only runs the app never has to compile it.
#
# Everything lands under ~/.local, so no root is needed.
set -euo pipefail

APP_ID=com.jinwei.custom_music_player
APP_NAME=Mewsic
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_URL=https://github.com/JinWei225/flutter-music-player/releases/latest/download/Mewsic-linux-x64.tar.gz

PREFIX="$HOME/.local"
INSTALL_DIR="$PREFIX/opt/$APP_ID"
BIN_LINK="$PREFIX/bin/custom-music-player"
DESKTOP_FILE="$PREFIX/share/applications/$APP_ID.desktop"
ICON_DIR="$PREFIX/share/icons/hicolor"

uninstall() {
  echo "Removing $APP_NAME..."
  rm -rf "$INSTALL_DIR"
  rm -f "$BIN_LINK" "$DESKTOP_FILE"
  for size in 16 24 32 48 64 128 256 512; do
    rm -f "$ICON_DIR/${size}x${size}/apps/$APP_ID.png"
  done
  update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
  gtk-update-icon-cache -f -t "$ICON_DIR" 2>/dev/null || true
  echo "Done."
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
  exit 0
fi

# --- build, or download -------------------------------------------------
if [[ "${1:-}" == "--latest" ]]; then
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  echo "Downloading the latest release..."
  curl -fsSL --retry 3 -o "$TMP/bundle.tar.gz" "$RELEASE_URL"
  tar -C "$TMP" -xzf "$TMP/bundle.tar.gz"
  BUNDLE="$TMP/bundle"
else
  if ! command -v flutter >/dev/null 2>&1; then
    export PATH="$HOME/dev/flutter/bin:$PATH"
  fi
  echo "Building release bundle..."
  cd "$PROJECT"
  flutter build linux --release
  BUNDLE="$PROJECT/build/linux/x64/release/bundle"
fi
[[ -x "$BUNDLE/Mewsic" ]] || { echo "No Mewsic binary in $BUNDLE"; exit 1; }

# --- install the bundle --------------------------------------------------
# The executable needs its sibling lib/ and data/ directories, so the whole
# bundle is copied out of build/ -- that way `flutter clean` cannot break the
# installed app.
echo "Installing to $INSTALL_DIR..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cp -r "$BUNDLE/." "$INSTALL_DIR/"

mkdir -p "$(dirname "$BIN_LINK")"
ln -sf "$INSTALL_DIR/Mewsic" "$BIN_LINK"

# --- icons ---------------------------------------------------------------
echo "Installing icons..."
python3 "$PROJECT/packaging/make_icons.py" "$PROJECT/packaging/icons" >/dev/null
for size in 16 24 32 48 64 128 256 512; do
  mkdir -p "$ICON_DIR/${size}x${size}/apps"
  cp "$PROJECT/packaging/icons/$size.png" "$ICON_DIR/${size}x${size}/apps/$APP_ID.png"
done

# --- desktop entry -------------------------------------------------------
echo "Installing desktop entry..."
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<DESKTOP
[Desktop Entry]
Type=Application
Version=1.0
Name=$APP_NAME
GenericName=Music Player
Comment=Play your local music library
Exec=$INSTALL_DIR/Mewsic %U
Icon=$APP_ID
Terminal=false
Categories=AudioVideo;Audio;Player;
Keywords=music;audio;player;song;album;m4a;mp3;aac;itunes;library;
MimeType=audio/mpeg;audio/mp4;audio/x-m4a;audio/aac;
StartupNotify=true
StartupWMClass=$APP_ID
DESKTOP
chmod 644 "$DESKTOP_FILE"

update-desktop-database "$PREFIX/share/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$ICON_DIR" 2>/dev/null || true

echo
echo "Installed. Press Super and type \"$APP_NAME\" to launch it."
echo "  binary : $INSTALL_DIR/Mewsic"
echo "  cli    : $BIN_LINK"
echo "  entry  : $DESKTOP_FILE"
