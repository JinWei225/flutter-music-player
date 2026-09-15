#!/usr/bin/env bash
# Copies the three albums test/metadata_test.dart and test/ui_test.dart were
# written against out of the Apple Music library into test/fixtures/library,
# which is gitignored (they are store purchases). Run once per machine; the
# tests skip themselves until it has been run.
#
#   test/fixtures/sync.sh                # from ~/Music/Music/Media.localized
#   test/fixtures/sync.sh /path/to/Music # from another Apple Music folder
set -euo pipefail

src="${1:-$HOME/Music/Music/Media.localized/Music}"
dest="$(cd "$(dirname "$0")" && pwd)/library"

albums=(
  "ITZY/KILL MY DOUBT - EP"
  "NAYEON/NA"
  "YEJI/AIR - EP"
)

for album in "${albums[@]}"; do
  if [[ ! -d "$src/$album" ]]; then
    echo "missing: $src/$album" >&2
    exit 1
  fi
  mkdir -p "$dest/$album"
  cp "$src/$album"/*.m4a "$dest/$album/"
done

echo "Fixture library ready: $(find "$dest" -name '*.m4a' | wc -l | tr -d ' ') files in $dest"
