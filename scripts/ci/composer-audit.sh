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
  set +e
  output="$(composer audit --no-interaction --locked --working-dir "$dir" 2>&1)"
  status=$?
  set -e
  printf '%s\n' "$output"
  if [[ $status -eq 0 ]]; then
    return 0
  fi
  # Composer 2.10 sai com erro quando o lock existe e nao tem pacotes.
  # Isso nao e advisory. Lock ausente continua falhando acima.
  if printf '%s\n' "$output" | grep -F -q 'No installed packages found'; then
    package_count="$(php -r 'echo count(json_decode(file_get_contents($argv[1]), true)["packages"]);' "${dir}/composer.lock")"
    if [[ "$package_count" == "0" ]]; then
      echo "OK ${label} sem pacotes no lock; nada a auditar"
      return 0
    fi
  fi
  exit "$status"
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
