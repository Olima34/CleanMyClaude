#!/bin/zsh
# Creates, once per Mac, the local signing certificate "Clean My Claude Dev" in the login keychain.
# Signed with it, every build keeps the same identity: macOS keeps the permissions
# (Full Disk Access, Accessibility, folders, automation…) from one rebuild to the next.
#
# The certificate is self-signed and only exists on this Mac: it proves nothing to anybody else and changes no
# trust setting. Its private key cannot be exported and only codesign may use it. To remove it later:
#   security delete-identity -c "Clean My Claude Dev"
set -euo pipefail

NAME="Clean My Claude Dev"
KEYCHAIN="${CMC_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "\"$NAME\""; then
  echo "✓ Le certificat « $NAME » existe déjà : rien à faire."
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PASS="$(/usr/bin/openssl rand -hex 16)"

cat > "$WORK/cert.cnf" <<CNF
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
CNF

echo "→ Création du certificat local « $NAME » (valable 10 ans)…"
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -name "$NAME" \
  -out "$WORK/identity.p12" -passout "pass:$PASS" 2>/dev/null

echo "→ Ajout au trousseau de session (clé non exportable, réservée à codesign)…"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" -x -T /usr/bin/codesign >/dev/null

echo "✓ Certificat prêt. À la prochaine compilation, macOS demandera une seule fois si codesign peut utiliser"
echo "  cette clé : saisis ton mot de passe de session et choisis « Toujours autoriser »."
echo "  Accorde ensuite les autorisations une dernière fois (Réglages › Autorisations › Tout autoriser) :"
echo "  elles resteront acquises après chaque reconstruction."
