#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/scripts/tag-images.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

out="$("$SCRIPT" --dry-run)"
printf '%s\n' "$out" | grep -q 'mode=dry-run' || fail "dry-run ausente"
printf '%s\n' "$out" | grep -q 'tag stack=php ' || fail "plano php ausente"
printf '%s\n' "$out" | grep -q 'tag stack=node ' || fail "plano node ausente"
printf '%s\n' "$out" | grep -q 'tag stack=backup ' || fail "plano backup ausente"
printf '%s\n' "$out" | grep -q 'nenhuma tag foi criada' || fail "dry-run deveria recusar criar tag"

echo "PASS tag-images"
