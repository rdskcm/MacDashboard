#!/bin/bash
# Create, once per Mac, the stable self-signed code-signing identity that build_app.sh
# signs local builds with. Idempotent: an existing identity is reused, never duplicated.
#
# Why: an ad-hoc signature's designated requirement is the build's cdhash, which changes
# whenever the code does, so macOS treats each such rebuild as a new app and drops its
# Full Disk Access / Automation grants. A certificate signature's designated requirement
# names the certificate instead, so it stays the same across rebuilds.
#
# The certificate is deliberately NOT added to any trust settings: codesign signs with an
# untrusted identity, and designated-requirement checks compare the certificate hash.
#
# Usage: tools/signing/make-identity.sh
# The probe signing at the end may show a macOS dialog once ("codesign wants to sign using
# key ... in your keychain"): enter the login password and click "Always Allow".
set -euo pipefail
umask 077

CN="MacDashboard Local Signing"   # keep equal to SIGN_CN in build_app.sh
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# The system LibreSSL: its PKCS#12 defaults are the ones `security import` accepts
# (OpenSSL 3 defaults produce "MAC verification failed").
OPENSSL=/usr/bin/openssl
PROBE_TIMEOUT=300   # seconds to wait for the one-time keychain dialog

# Without -v: -v lists only identities with a TRUSTED certificate, and this one is not.
identity_hashes() {
  { security find-identity -p codesigning 2>/dev/null || true; } \
    | awk -v cn="\"$CN\"" 'index($0, cn) { print $2 }' | sort -u
}
count_lines() { printf '%s' "$1" | grep -c . || true; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HASHES="$(identity_hashes)"
COUNT="$(count_lines "$HASHES")"
if [ "$COUNT" -gt 1 ]; then
  echo "!! $COUNT code-signing identities named \"$CN\" exist — codesign cannot pick one." >&2
  echo "!! Keep one: delete the others in Keychain Access (login > My Certificates). SHA-1s:" >&2
  printf '%s\n' "$HASHES" >&2
  exit 1
elif [ "$COUNT" -eq 1 ]; then
  echo "identity exists: $HASHES \"$CN\" — nothing created"
else
  case "$("$OPENSSL" version)" in
    LibreSSL*) ;;
    *) echo "!! $OPENSSL is not LibreSSL ($("$OPENSSL" version)); stopping" >&2; exit 1 ;;
  esac
  [ -f "$KEYCHAIN" ] || { echo "!! login keychain not found: $KEYCHAIN" >&2; exit 1; }

  cat > "$TMP_DIR/req.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions    = codesign_ext
prompt             = no
[ dn ]
CN = $CN
[ codesign_ext ]
basicConstraints     = critical, CA:false
keyUsage             = critical, digitalSignature
extendedKeyUsage     = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
    -config "$TMP_DIR/req.cnf" -keyout "$TMP_DIR/key.pem" -out "$TMP_DIR/cert.pem"
  P12_PASS="$("$OPENSSL" rand -hex 16)"
  "$OPENSSL" pkcs12 -export -name "$CN" -inkey "$TMP_DIR/key.pem" -in "$TMP_DIR/cert.pem" \
    -out "$TMP_DIR/identity.p12" -passout "pass:$P12_PASS"
  # -x: the private key can never be exported; -T: codesign is on the key's access list.
  security import "$TMP_DIR/identity.p12" -k "$KEYCHAIN" -f pkcs12 -P "$P12_PASS" \
    -x -T /usr/bin/codesign

  HASHES="$(identity_hashes)"
  COUNT="$(count_lines "$HASHES")"
  if [ "$COUNT" -ne 1 ]; then
    echo "!! after import expected 1 identity named \"$CN\", found $COUNT" >&2
    exit 1
  fi
  echo "created identity: $HASHES \"$CN\""
fi

echo "== probe signing (a keychain dialog may appear once: login password, then Always Allow) =="
cp /usr/bin/true "$TMP_DIR/probe"
codesign --force --timestamp=none --sign "$HASHES" "$TMP_DIR/probe" &
PID=$!
WAITED=0
while kill -0 "$PID" 2>/dev/null; do
  if [ "$WAITED" -ge "$PROBE_TIMEOUT" ]; then
    kill "$PID" 2>/dev/null || true
    echo "!! probe signing did not finish in ${PROBE_TIMEOUT}s — the keychain dialog was not answered" >&2
    exit 1
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done
wait "$PID" || { echo "!! probe signing failed — see codesign's message above" >&2; exit 1; }
codesign --verify --strict "$TMP_DIR/probe"
echo "probe OK in ${WAITED}s: codesign signed with \"$CN\" ($HASHES)"
