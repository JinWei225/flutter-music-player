#!/bin/bash
# Build the macOS release of Mewsic, sign it, and install it as
# /Applications/Mewsic.app, relaunching it if it was running.
#
#   ./packaging/install_app_macos.sh
#
# With the local "Mewsic Dev" certificate in place (signing_identity_macos.sh)
# the app keeps its Media & Apple Music permission across rebuilds; without
# it, macOS asks again after every install.
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME=Mewsic
BUILT="$PROJECT/build/macos/Build/Products/Release/$APP_NAME.app"
TARGET="/Applications/$APP_NAME.app"
ENTITLEMENTS="$PROJECT/macos/Runner/Release.entitlements"

# shellcheck source=codesign_macos.sh
source "$PROJECT/packaging/codesign_macos.sh"

# xcode-select on this machine points at the command-line tools; the build
# needs the full Xcode. Honour an existing DEVELOPER_DIR, else find one.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for xcode in /Applications/Xcode.app /Applications/Xcode-beta.app; do
    [[ -d "$xcode/Contents/Developer" ]] && export DEVELOPER_DIR="$xcode/Contents/Developer" && break
  done
fi

if ! command -v flutter >/dev/null 2>&1; then
  for candidate in "$HOME/dev/flutter/bin" "$HOME/flutter/bin"; do
    [[ -x "$candidate/flutter" ]] && export PATH="$candidate:$PATH" && break
  done
fi

echo "Building $APP_NAME..."
(cd "$PROJECT" && flutter build macos --release | tail -1)

sign_app "$BUILT" "$ENTITLEMENTS"

was_running=false
if pgrep -x "$APP_NAME" >/dev/null; then
  was_running=true
  echo "Quitting the running $APP_NAME..."
  osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "$APP_NAME" >/dev/null || break; sleep 0.5; done
  pkill -x "$APP_NAME" 2>/dev/null || true
fi

rm -rf "$TARGET"
cp -R "$BUILT" "$TARGET"
echo "Installed $TARGET"

if $was_running; then
  open "$TARGET"
  echo "Relaunched."
fi
