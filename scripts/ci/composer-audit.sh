#!/usr/bin/env bash
# Audita composer.lock dos projetos PHP de aplicacao.
# Sem lock, o script falha. Nao ha passe vazio.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

audit_dir() {
  local dir="$1"
  local label="$2"
  if [[ ! -f "${dir}/composer.lock" ]]; then
    echo "FAIL ${label} sem composer.lock" >&2
    exit 1
  fi
  if ! command -v composer >/dev/null 2>&1; then
    echo "composer ausente para ${label}" >&2
    exit 1
  fi
  echo "composer audit ${label}"
  composer audit --no-interaction --locked --working-dir "$dir"
}

if [[ $# -gt 1 ]]; then
  echo "Uso: $0 [diretorio]" >&2
  exit 1
fi

if [[ $# -eq 1 ]]; then
  audit_dir "$1" "$1"
  exit 0
fi

SCAN_ROOT="${COMPOSER_AUDIT_ROOT:-$ROOT}"
projects=(
  app_nf
  app_sistema
  gsfacilFront
  googlecalendar
  peoplecontacts
)

for name in "${projects[@]}"; do
  audit_dir "${SCAN_ROOT}/php/${name}" "php/${name}"
done
