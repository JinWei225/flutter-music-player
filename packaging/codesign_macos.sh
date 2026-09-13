#!/bin/bash
# Shared by the macOS install scripts: sign with the local "Mewsic Dev"
# certificate when it exists (see signing_identity_macos.sh), otherwise fall
# back to the ad-hoc signature the build already carries.
#
# Source this file; it defines functions and sets nothing else.

MEWSIC_SIGN_IDENTITY="Mewsic Dev"

# True when the identity is present and trusted for code signing.
have_signing_identity() {
  security find-identity -v -p codesigning 2>/dev/null \
    | grep -q "\"$MEWSIC_SIGN_IDENTITY\""
}

# sign_binary <file> <identifier>
#
# A plain executable such as mewsic-tagfix. The identifier is what the
# permission database keys on together with the certificate.
sign_binary() {
  local file="$1" identifier="$2"
  if ! have_signing_identity; then
    echo "No \"$MEWSIC_SIGN_IDENTITY\" identity; leaving the ad-hoc signature" \
         "(run packaging/signing_identity_macos.sh to keep permissions across builds)."
    return 0
  fi
  codesign --force --sign "$MEWSIC_SIGN_IDENTITY" --identifier "$identifier" \
    --timestamp=none "$file"
  echo "Signed $(basename "$file") as \"$MEWSIC_SIGN_IDENTITY\"."
}

# sign_app <Something.app> <entitlements.plist>
#
# Signs the nested frameworks and libraries first (inside out, as codesign
# requires), then the bundle itself with its entitlements, so the sandbox
# and music-folder grants the app relies on stay in force.
sign_app() {
  local app="$1" entitlements="$2"
  if ! have_signing_identity; then
    echo "No \"$MEWSIC_SIGN_IDENTITY\" identity; leaving the ad-hoc signature" \
         "(run packaging/signing_identity_macos.sh to keep permissions across builds)."
    return 0
  fi
  local nested
  while IFS= read -r -d '' nested; do
    codesign --force --sign "$MEWSIC_SIGN_IDENTITY" --timestamp=none "$nested"
  done < <(find "$app/Contents/Frameworks" \( -name '*.framework' -o -name '*.dylib' \) \
             -maxdepth 1 -print0 2>/dev/null)
  codesign --force --sign "$MEWSIC_SIGN_IDENTITY" --timestamp=none \
    --entitlements "$entitlements" "$app"
  codesign --verify --deep --strict "$app"
  echo "Signed $(basename "$app") as \"$MEWSIC_SIGN_IDENTITY\"."
}
