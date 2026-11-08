#!/bin/bash
set -euo pipefail

NAME="KeyBoop Local"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Сертификат «$NAME» уже есть"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no
x509_extensions = code_sign

[req_distinguished_name]
CN = KeyBoop Local

[code_sign]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -config "$TMP/cert.cnf"
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout pass:keyboop

security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P keyboop -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true
echo "Создан сертификат «$NAME». Следующая сборка подпишет им KeyBoop.app."
