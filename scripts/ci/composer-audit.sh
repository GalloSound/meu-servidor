#!/usr/bin/env bash
# Audita composer.lock quando o checkout tem os projetos PHP.
# No repo da plataforma esses diretorios sao repos separados e podem estar ausentes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAN_ROOT="${COMPOSER_AUDIT_ROOT:-$ROOT}"
found=0

projects="app app_nf app_sistema gsfacilFront googlecalendar peoplecontacts"
for name in $projects; do
  lock="${SCAN_ROOT}/php/${name}/composer.lock"
  if [[ ! -f "$lock" ]]; then
    continue
  fi
  found=1
  if ! command -v composer >/dev/null 2>&1; then
    echo "composer ausente e ha lockfile em php/${name}" >&2
    exit 1
  fi
  echo "composer audit php/${name}"
  composer audit --no-interaction --working-dir "${SCAN_ROOT}/php/${name}"
done

if [[ "$found" -eq 0 ]]; then
  echo "PASS composer-audit (nenhum composer.lock neste checkout)"
fi
