#!/usr/bin/env bash
# Mocks locais. Nao chama curl real nem repository status do Kopia.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/kopia-healthcheck.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

BIN="${TMP}/bin"
MOCK_LOG="${TMP}/calls.log"
mkdir -p "$BIN"

cat > "${BIN}/curl" <<'EOF'
#!/bin/sh
printf '%s' "${CURL_CODE:-000}"
EOF
chmod 0755 "${BIN}/curl"

cat > "${BIN}/kopia-entrypoint" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_LOG"
printf '%s\n' 'password=repo-secret-value remote=gdrive:Backup/secret token=ya29.oauth-token file=rclone.conf'
printf '%s\n' 'stderr password=repo-secret-value token=ya29.oauth-token invalid_grant' >&2
exit "${MOCK_STATUS_RC:-0}"
EOF
chmod 0755 "${BIN}/kopia-entrypoint"

grep -q '/usr/local/bin/kopia-entrypoint' "$SCRIPT" || fail "caminho padrao do entrypoint ausente"
grep -q 'repository status' "$SCRIPT" || fail "repository status ausente no script"

assert_no_secrets() {
  blob="$1"
  if printf '%s\n' "$blob" | grep -F -q 'repo-secret-value'; then
    fail "a saida contem a senha simulada"
  fi
  if printf '%s\n' "$blob" | grep -F -q 'ya29.oauth-token'; then
    fail "a saida contem o token simulado"
  fi
  if printf '%s\n' "$blob" | grep -F -q 'gdrive:Backup/secret'; then
    fail "a saida contem o caminho remoto simulado"
  fi
  if printf '%s\n' "$blob" | grep -F -q 'rclone.conf'; then
    fail "a saida contem rclone.conf"
  fi
}

run_check() {
  : > "$MOCK_LOG"
  set +e
  stdout=$(
    PATH="${BIN}:${PATH}" \
    CURL_CODE="$1" \
    KOPIA_ENTRYPOINT="${BIN}/kopia-entrypoint" \
    MOCK_LOG="$MOCK_LOG" \
    MOCK_STATUS_RC="$2" \
      "$SCRIPT" 2>"${TMP}/stderr"
  )
  rc=$?
  set -e
  stderr=$(cat "${TMP}/stderr")
  calls=$(wc -l < "$MOCK_LOG" | tr -d ' ')
}

run_check 200 0
[[ "$rc" -eq 0 ]] || fail "HTTP 200 com status ok deveria sair 0 (rc=${rc})"
[[ "$calls" -eq 1 ]] || fail "HTTP 200 deveria chamar repository status uma vez"
grep -qx 'repository status' "$MOCK_LOG" || fail "args de repository status divergiram"
[[ -z "$stdout" && -z "$stderr" ]] || fail "HTTP 200 com status ok imprimiu saida"
assert_no_secrets "${stdout}${stderr}"

run_check 401 0
[[ "$rc" -eq 0 ]] || fail "HTTP 401 com status ok deveria sair 0 (rc=${rc})"
[[ "$calls" -eq 1 ]] || fail "HTTP 401 deveria chamar repository status uma vez"
grep -qx 'repository status' "$MOCK_LOG" || fail "args de repository status divergiram no 401"
assert_no_secrets "${stdout}${stderr}"

run_check 500 0
[[ "$rc" -eq 1 ]] || fail "HTTP invalido deveria sair 1 (rc=${rc})"
[[ "$calls" -eq 0 ]] || fail "HTTP invalido nao deveria chamar repository status"
[[ "$stderr" == "kopia healthcheck HTTP 500" ]] || fail "mensagem de HTTP invalido divergiu"
assert_no_secrets "${stdout}${stderr}"

run_check 200 1
[[ "$rc" -eq 1 ]] || fail "status com falha deveria sair 1 (rc=${rc})"
[[ "$calls" -eq 1 ]] || fail "HTTP valido deveria chamar repository status antes da falha"
[[ "$stderr" == "kopia healthcheck: repositorio indisponivel" ]] || fail "mensagem generica ausente"
assert_no_secrets "${stdout}${stderr}"

run_check 401 7
[[ "$rc" -eq 1 ]] || fail "status com falha no 401 deveria sair 1"
assert_no_secrets "${stdout}${stderr}"
if printf '%s\n' "$stderr" | grep -F -q 'invalid_grant'; then
  fail "invalid_grant simulado vazou na saida"
fi

echo "PASS kopia-healthcheck"
