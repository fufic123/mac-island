#!/usr/bin/env bash
# One-time: creates a self-signed "MacIsland Local Signing" code-signing identity in the login
# keychain. bundle.sh signs with it, so the app keeps one identity across rebuilds and macOS
# remembers the permissions you grant it (Automation for Terminal/iTerm, folder access) instead
# of asking again after every build, as it does for ad-hoc signatures.
# macOS asks for your password once, to trust the certificate for code signing.
set -euo pipefail

NAME="MacIsland Local Signing"
if security find-identity -v -p codesigning | grep -q "$NAME"; then
  echo "\"$NAME\" already exists."
  exit 0
fi

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# A previous run may have imported the identity but not finished trusting it.
if security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$tmp/cert.pem" 2>/dev/null; then
  echo "Trusting the existing \"$NAME\" certificate (macOS will ask for your password)..."
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"
  security find-identity -v -p codesigning | grep "$NAME"
  echo "Done. Rebuild with ./scripts/bundle.sh; if asked to let codesign use the key, choose Always Allow."
  exit 0
fi
cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" 2>/dev/null
pass=$(openssl rand -hex 12)
openssl pkcs12 -export -legacy -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -out "$tmp/id.p12" -passout "pass:$pass" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout "pass:$pass"

security import "$tmp/id.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"

security find-identity -v -p codesigning | grep "$NAME"
echo "Done. Rebuild with ./scripts/bundle.sh; the first build may ask to let codesign use the key: choose Always Allow."
