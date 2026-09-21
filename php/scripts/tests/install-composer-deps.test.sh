#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/install-composer-deps.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if grep -n 'composer update' "$SCRIPT"; then
  fail "script ainda cita composer update"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "${TMP}/app" "${TMP}/gsfacilFront"
printf '{}\n' > "${TMP}/app/composer.json"
printf '{}\n' > "${TMP}/gsfacilFront/composer.json"
printf '{}\n' > "${TMP}/gsfacilFront/composer.lock"

out="$(PHP_DIR="$TMP" "$SCRIPT" --dry-run)"
printf '%s\n' "$out" | grep -q 'mode=dry-run' || fail "dry-run ausente"
printf '%s\n' "$out" | grep -q 'install=gsfacilFront' || fail "gsfacilFront nao entrou no plano"
printf '%s\n' "$out" | grep -q 'skip=app sem composer.lock' || fail "app sem lock deveria ser ignorado"
printf '%s\n' "$out" | grep -q 'composer install --no-dev' || fail "plano nao usa composer install"

echo "PASS install-composer-deps"
