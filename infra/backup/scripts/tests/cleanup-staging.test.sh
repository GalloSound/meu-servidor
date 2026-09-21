#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/cleanup-staging.sh"
TMP="$(mktemp -d)"
export BACKUP_ENV_FILE=/dev/null
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_run() {
  local name="$1"
  local confirmed="${2:-yes}"
  mkdir -p "${TMP}/staging/${name}/sql"
  printf 'keep\n' > "${TMP}/staging/${name}/sql/app.sql"
  if [[ "$confirmed" == "yes" ]]; then
    printf 'confirmed\n' > "${TMP}/staging/${name}/SNAPSHOT_CONFIRMED"
  fi
}

make_run 20260917_010101
make_run 20260918_010101
make_run 20260919_010101
make_run 20260920_010101
make_run 20260921_010101
make_run 20260703_191955 no
mkdir -p "${TMP}/staging/restore-drill"
printf '20260921_010101\n' > "${TMP}/staging/latest"

out="$(STAGING_DIR="${TMP}/staging" BACKUP_STAGING_KEEP=3 "$SCRIPT" --dry-run)"
printf '%s\n' "$out" | grep -q 'mode=dry-run' || fail "dry-run nao anunciado"
printf '%s\n' "$out" | grep -q 'remove=20260917_010101' || fail "nao listou a execucao mais antiga"
printf '%s\n' "$out" | grep -q 'remove=20260918_010101' || fail "nao listou a segunda execucao"
printf '%s\n' "$out" | grep -q 'keep=20260921_010101 confirmed' || fail "nao manteve a mais nova"
printf '%s\n' "$out" | grep -q 'keep=20260703_191955 unconfirmed' || fail "apagaria run sem snapshot"
printf '%s\n' "$out" | grep -q 'keep=restore-drill ignored' || fail "apagaria diretorio fora do padrao"
[[ -d "${TMP}/staging/20260917_010101" ]] || fail "dry-run removeu diretorio"

if STAGING_DIR="${TMP}/staging" BACKUP_STAGING_KEEP=3 BACKUP_STAGING_CLEANUP=false "$SCRIPT" --apply >/dev/null 2>"${TMP}/apply.err"; then
  fail "--apply sem BACKUP_STAGING_CLEANUP deveria falhar"
fi
[[ -d "${TMP}/staging/20260917_010101" ]] || fail "--apply sem flag apagou staging"

STAGING_DIR="${TMP}/staging" BACKUP_STAGING_KEEP=2 BACKUP_STAGING_CLEANUP=true "$SCRIPT" --apply >"${TMP}/apply.out"
[[ ! -d "${TMP}/staging/20260917_010101" ]] || fail "apply nao removeu a mais antiga"
[[ ! -d "${TMP}/staging/20260918_010101" ]] || fail "apply nao removeu a segunda"
[[ ! -d "${TMP}/staging/20260919_010101" ]] || fail "keep=2 deveria deixar so duas confirmadas alem da unconfirmed"
[[ -d "${TMP}/staging/20260920_010101" ]] || fail "removeu execucao que deveria ficar"
[[ -d "${TMP}/staging/20260921_010101" ]] || fail "removeu a latest"
[[ -d "${TMP}/staging/20260703_191955" ]] || fail "removeu run sem marcador"
[[ -d "${TMP}/staging/restore-drill" ]] || fail "removeu restore-drill"

if STAGING_DIR="${TMP}/staging" BACKUP_STAGING_KEEP=1 "$SCRIPT" --dry-run >/dev/null 2>&1; then
  fail "KEEP=1 deveria ser recusado"
fi

echo "PASS cleanup-staging"
