#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/render-kopia-secrets.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

secret='s3cret-value-not-for-logs'
cat > "${TMP}/backup.env" <<EOF
KOPIA_UI_USER=admin
KOPIA_UI_PASSWORD=${secret}
KOPIA_REPOSITORY_PASSWORD=repo-secret-value
EOF

out="$(ENV_FILE="${TMP}/backup.env" SECRETS_DIR="${TMP}/secrets" "$SCRIPT")"
if printf '%s\n' "$out" | grep -q "$secret"; then
  fail "a senha apareceu na saida"
fi
[[ -s "${TMP}/secrets/kopia-repository-password" ]] || fail "arquivo de senha ausente"
[[ -s "${TMP}/secrets/kopia-ui.htpasswd" ]] || fail "htpasswd ausente"
mode="$(stat -f '%OLp' "${TMP}/secrets/kopia-repository-password" 2>/dev/null || stat -c '%a' "${TMP}/secrets/kopia-repository-password")"
[[ "$mode" == "600" ]] || fail "permissao do secret: ${mode}"

repo_line="$(tr -d '\r\n' < "${TMP}/secrets/kopia-repository-password")"
[[ "$repo_line" == "repo-secret-value" ]] || fail "senha do repositorio nao confere"

grep -q '^admin:' "${TMP}/secrets/kopia-ui.htpasswd" || fail "htpasswd sem usuario"

entry="${ROOT}/kopia-entrypoint.sh"
fake="${TMP}/fake-kopia"
cat > "$fake" <<'EOF'
#!/bin/sh
printf '%s\n' "$KOPIA_PASSWORD" > "$FAKE_OUT"
printf '%s\n' "$*" > "$FAKE_ARGS"
EOF
chmod +x "$fake"
printf 'repo-secret-value\n' > "${TMP}/secrets/kopia-repository-password"
KOPIA_PASSWORD_FILE="${TMP}/secrets/kopia-repository-password" \
  KOPIA_BIN="$fake" \
  FAKE_OUT="${TMP}/seen-pass" \
  FAKE_ARGS="${TMP}/seen-args" \
  "$entry" snapshot list /staging/x
[[ "$(cat "${TMP}/seen-pass")" == "repo-secret-value" ]] || fail "entrypoint nao leu o arquivo"
[[ "$(cat "${TMP}/seen-args")" == "snapshot list /staging/x" ]] || fail "args do kopia divergiram"
if ps -p $$ -o args= 2>/dev/null | grep -q 'repo-secret-value'; then
  fail "senha do teste ficou no argv do runner"
fi

echo "PASS render-kopia-secrets"
