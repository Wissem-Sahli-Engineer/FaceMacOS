#!/usr/bin/env bash
# Creates a self-signed "FaceMacOS Local Signing" code-signing identity in the login keychain.
# Signing every local build with the same identity keeps Camera/Accessibility permissions and
# Keychain access working across rebuilds (ad-hoc signatures change on every build).
set -euo pipefail

NAME="FaceMacOS Local Signing"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "\"$NAME\" already exists."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout pass:facemacos -name "$NAME"
security import "$WORK/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P facemacos -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\"."
