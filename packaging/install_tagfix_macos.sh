#!/bin/bash
# Build mewsic-tagfix as a standalone binary and register it to run at login,
# watching the Apple Music folder and completing the tags of new purchases.
# The music player app is not involved; only the Dart SDK is needed to build.
#
#   ./packaging/install_tagfix_macos.sh              build + install + start
#   ./packaging/install_tagfix_macos.sh --uninstall
#
# Everything lands under the current user's home: the binary in ~/.local/bin,
# the agent in ~/Library/LaunchAgents, the log in ~/Library/Logs.
set -euo pipefail

LABEL=com.jinwei.mewsic-tagfix
PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/mewsic-tagfix"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/mewsic-tagfix.log"

uninstall() {
  echo "Stopping and removing mewsic-tagfix..."
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$BIN"
  echo "Done. (Log kept at $LOG)"
}

if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
  exit 0
fi

# --- build ---------------------------------------------------------------
if ! command -v dart >/dev/null 2>&1; then
  # Flutter ships a Dart SDK; fall back to it when dart is not on PATH.
  for candidate in "$HOME/dev/flutter/bin" "$HOME/flutter/bin" /opt/homebrew/bin; do
    [[ -x "$candidate/dart" ]] && export PATH="$candidate:$PATH" && break
  done
fi
command -v dart >/dev/null 2>&1 || { echo "dart not found on PATH" >&2; exit 1; }

echo "Building mewsic-tagfix..."
mkdir -p "$BIN_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
# `dart compile exe` refuses a package whose dependencies have build hooks
# (a Flutter plugin's), so use `dart build`. The bundle also carries that
# plugin's dylib, which this tool never loads; only the executable is kept.
BUILD_OUT="$PROJECT/build/tagfix"
(cd "$PROJECT" && dart pub get >/dev/null \
  && dart build cli -t bin/tagfix.dart -o "$BUILD_OUT" >/dev/null)
install -m 755 "$BUILD_OUT/bundle/bin/tagfix" "$BIN"

# --- launch agent --------------------------------------------------------
# Stop any running copy before the plist is rewritten.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
    <string>watch</string>
    <string>--quiet</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <!-- Restart if it ever exits, but not in a tight loop. -->
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>30</integer>
  <key>StandardOutPath</key>
  <string>$LOG</string>
  <key>StandardErrorPath</key>
  <string>$LOG</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed. mewsic-tagfix is watching your Apple Music folder."
echo "  binary:  $BIN"
echo "  agent:   $PLIST"
echo "  log:     $LOG"
echo
echo "If the log says macOS is blocking access, allow mewsic-tagfix under"
echo "System Settings > Privacy & Security > Media & Apple Music."
