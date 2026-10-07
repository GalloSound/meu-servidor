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

make_run 20260827_010101
make_run 20260921_010101
make_run 20260930_010101
make_run 20261001_010101
make_run 20261002_010101
make_run 20261003_010101
make_run 20261004_010101
make_run 20261005_010101
make_run 20261006_010101
make_run 20261007_010101
make_run 20261007_020202
make_run 20260703_191955 no
mkdir -p "${TMP}/staging/restore-drill"
printf '20261007_020202\n' > "${TMP}/staging/latest"

out="$(STAGING_DIR="${TMP}/staging" "$SCRIPT" --dry-run)"
printf '%s\n' "$out" | grep -q 'mode=dry-run' || fail "dry-run nao anunciado"
printf '%s\n' "$out" | grep -q 'keep_daily=3' || fail "diario padrao"
printf '%s\n' "$out" | grep -q 'keep_weekly=1' || fail "semanal padrao"
printf '%s\n' "$out" | grep -q 'keep_monthly=1' || fail "mensal padrao"
printf '%s\n' "$out" | grep -q 'keep=20261007_020202 daily,latest' || fail "nao manteve o dia mais novo"
printf '%s\n' "$out" | grep -q 'keep=20261006_010101 daily' || fail "nao manteve o segundo dia"
printf '%s\n' "$out" | grep -q 'keep=20261005_010101 daily' || fail "nao manteve o terceiro dia"
printf '%s\n' "$out" | grep -q 'keep=20261004_010101 weekly' || fail "nao manteve a semana anterior"
printf '%s\n' "$out" | grep -q 'keep=20260930_010101 monthly' || fail "nao manteve o mes anterior"
printf '%s\n' "$out" | grep -q 'remove=20261007_010101' || fail "segunda execucao do mesmo dia deveria sair"
printf '%s\n' "$out" | grep -q 'remove=20261003_010101' || fail "dia extra da semana corrente deveria sair"
printf '%s\n' "$out" | grep -q 'remove=20260921_010101' || fail "setembro antigo deveria sair"
printf '%s\n' "$out" | grep -q 'remove=20260827_010101' || fail "agosto deveria sair"
printf '%s\n' "$out" | grep -q 'keep=20260703_191955 unconfirmed' || fail "apagaria run sem snapshot"
printf '%s\n' "$out" | grep -q 'keep=restore-drill ignored' || fail "apagaria diretorio fora do padrao"
[[ -d "${TMP}/staging/20260827_010101" ]] || fail "dry-run removeu diretorio"

if STAGING_DIR="${TMP}/staging" BACKUP_STAGING_CLEANUP=false "$SCRIPT" --apply >/dev/null 2>"${TMP}/apply.err"; then
  fail "--apply sem BACKUP_STAGING_CLEANUP deveria falhar"
fi
[[ -d "${TMP}/staging/20260827_010101" ]] || fail "--apply sem flag apagou staging"

STAGING_DIR="${TMP}/staging" BACKUP_STAGING_CLEANUP=true "$SCRIPT" --apply >"${TMP}/apply.out"
[[ ! -d "${TMP}/staging/20260827_010101" ]] || fail "apply nao removeu agosto"
[[ ! -d "${TMP}/staging/20260921_010101" ]] || fail "apply nao removeu setembro antigo"
[[ ! -d "${TMP}/staging/20261001_010101" ]] || fail "apply nao removeu 1 de outubro"
[[ ! -d "${TMP}/staging/20261003_010101" ]] || fail "apply nao removeu 3 de outubro"
[[ ! -d "${TMP}/staging/20261007_010101" ]] || fail "apply nao removeu execucao duplicada do dia"
[[ -d "${TMP}/staging/20260930_010101" ]] || fail "removeu o mensal"
[[ -d "${TMP}/staging/20261004_010101" ]] || fail "removeu o semanal"
[[ -d "${TMP}/staging/20261005_010101" ]] || fail "removeu um diario"
[[ -d "${TMP}/staging/20261006_010101" ]] || fail "removeu um diario"
[[ -d "${TMP}/staging/20261007_020202" ]] || fail "removeu o latest"
[[ -d "${TMP}/staging/20260703_191955" ]] || fail "removeu run sem marcador"
[[ -d "${TMP}/staging/restore-drill" ]] || fail "removeu restore-drill"

if STAGING_DIR="${TMP}/staging" BACKUP_STAGING_KEEP_DAILY=x "$SCRIPT" --dry-run >/dev/null 2>&1; then
  fail "diario invalido deveria ser recusado"
fi

echo "PASS cleanup-staging"
