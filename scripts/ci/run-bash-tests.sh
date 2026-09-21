#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail=0
while IFS= read -r test; do
  echo "== ${test}"
  if ! bash "$test"; then
    fail=1
  fi
done <<EOF
$(find infra/backup/scripts/tests php/scripts/tests scripts/tests -name '*.test.sh' | sort)
EOF

if [[ "$fail" -ne 0 ]]; then
  echo "FAIL bash tests" >&2
  exit 1
fi

bash scripts/ci/static-checks.sh
echo "PASS bash tests"
