#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/scripts/ci/composer-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

projects=(
  app_nf
  app_sistema
  gsfacilFront
  googlecalendar
  peoplecontacts
)

set +e
out="$(COMPOSER_AUDIT_ROOT="$TMP" bash "$SCRIPT" 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "sem lock deveria falhar"
printf '%s\n' "$out" | grep -q 'nenhum composer.lock' && fail "falso PASS ainda existe"
printf '%s\n' "$out" | grep -q 'php/app_nf sem composer.lock' || fail "mensagem de lock ausente"

mkdir -p "${TMP}/solo"
set +e
out="$(bash "$SCRIPT" "${TMP}/solo" 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "diretorio sem lock deveria falhar"
printf '%s\n' "$out" | grep -q 'nenhum composer.lock' && fail "falso PASS no modo diretorio"

FAKE="${TMP}/bin"
mkdir -p "$FAKE"
cat > "${FAKE}/composer" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${COMPOSER_LOG}"
exit 0
EOF
chmod +x "${FAKE}/composer"

for name in "${projects[@]}"; do
  mkdir -p "${TMP}/php/${name}"
  printf '{}\n' > "${TMP}/php/${name}/composer.lock"
done

log="${TMP}/composer.log"
: > "$log"
COMPOSER_LOG="$log" PATH="${FAKE}:${PATH}" COMPOSER_AUDIT_ROOT="$TMP" bash "$SCRIPT"
for name in "${projects[@]}"; do
  grep -q -- "--working-dir ${TMP}/php/${name}" "$log" || fail "nao auditou php/${name}"
done
lines="$(wc -l < "$log" | tr -d ' ')"
[[ "$lines" -eq 5 ]] || fail "esperava 5 audits, veio ${lines}"

: > "$log"
mkdir -p "${TMP}/one"
printf '{}\n' > "${TMP}/one/composer.lock"
COMPOSER_LOG="$log" PATH="${FAKE}:${PATH}" bash "$SCRIPT" "${TMP}/one"
grep -q -- "--working-dir ${TMP}/one" "$log" || fail "nao auditou diretorio unico"
grep -q -- "--locked" "$log" || fail "audit sem --locked"

rm -f "${TMP}/php/googlecalendar/composer.lock"
: > "$log"
set +e
out="$(COMPOSER_LOG="$log" PATH="${FAKE}:${PATH}" COMPOSER_AUDIT_ROOT="$TMP" bash "$SCRIPT" 2>&1)"
status=$?
set -e
[[ "$status" -ne 0 ]] || fail "lock faltando deveria falhar"
printf '%s\n' "$out" | grep -q 'php/googlecalendar sem composer.lock' || fail "nao apontou googlecalendar"
printf '%s\n' "$out" | grep -q 'nenhum composer.lock' && fail "falso PASS com lock parcial"

if grep -q 'nenhum composer.lock' "$SCRIPT" "${ROOT}/.github/workflows/ci.yml" "${ROOT}/docs/ci.md"; then
  fail "falso PASS ainda documentado"
fi

echo "PASS composer-audit"
