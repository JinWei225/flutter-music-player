#!/bin/bash
# Create (once) a self-signed code-signing certificate named "Mewsic Dev" in
# the login keychain, and trust it for code signing.
#
# Why: macOS ties an app's privacy permissions (Media & Apple Music, etc.) to
# its code signature. An ad-hoc signature changes with every build, so each
# rebuild of Mewsic or mewsic-tagfix loses its permission and prompts again.
# Signing with one stable local certificate keeps the identity -- and the
# grant -- across builds. It is for this Mac only; it has nothing to do with
# Apple's developer program or distribution.
#
#   ./packaging/signing_identity_macos.sh          create + trust
#   ./packaging/signing_identity_macos.sh --remove
#
# Trusting the certificate changes your keychain's trust settings, so macOS
# asks for your login password once. Run this yourself; then the install
# scripts sign automatically whenever the identity is present.
set -euo pipefail

NAME="Mewsic Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if [[ "${1:-}" == "--remove" ]]; then
  echo "Removing the \"$NAME\" certificate and key..."
  security delete-identity -c "$NAME" "$KEYCHAIN" 2>/dev/null || true
  security delete-certificate -c "$NAME" "$KEYCHAIN" 2>/dev/null || true
  echo "Done. Rebuilt binaries fall back to ad-hoc signing."
  exit 0
fi

# --- create ----------------------------------------------------------------
if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate \"$NAME\" already exists."
else
  echo "Creating certificate \"$NAME\"..."
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
    -subj "/CN=$NAME/OU=Local code signing" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false" 2>/dev/null
  openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
    -name "$NAME" -out "$tmp/identity.p12" -passout pass:mewsic 2>/dev/null
  # -A: codesign may use the key without a per-use approval dialog.
  security import "$tmp/identity.p12" -k "$KEYCHAIN" -P mewsic -A \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null
fi

# --- trust -----------------------------------------------------------------
if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "Certificate \"$NAME\" is already trusted for code signing."
else
  echo "Trusting \"$NAME\" for code signing (macOS will ask for your password)..."
  tmp="${tmp:-$(mktemp -d)}"
  security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$tmp/trust.pem"
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/trust.pem"
  security find-identity -v -p codesigning | grep -q "\"$NAME\"" \
    || { echo "The certificate is still not usable for signing." >&2; exit 1; }
fi

echo
echo "Ready. Re-run ./packaging/install_tagfix_macos.sh and"
echo "./packaging/install_app_macos.sh; both now sign with \"$NAME\"."
echo "Each will ask for Media & Apple Music access one last time."
