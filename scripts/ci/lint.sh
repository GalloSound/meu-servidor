#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

if command -v shellcheck >/dev/null 2>&1; then
  files="$(find infra/backup/scripts php/scripts scripts -name '*.sh' -print)"
  # shellcheck disable=SC2086
  shellcheck $files
else
  echo "shellcheck ausente; validando sintaxe bash"
fi

find infra/backup/scripts php/scripts scripts -name '*.sh' -print | while IFS= read -r file; do
  bash -n "$file"
done

if command -v php >/dev/null 2>&1; then
  find php/shared php/www -name '*.php' -print | while IFS= read -r file; do
    php -l "$file" >/dev/null
  done
fi

if command -v node >/dev/null 2>&1 && [[ -d node/apigsfacil/src ]]; then
  find node/apigsfacil/src node/apigsfacil/tests -name '*.js' -print | while IFS= read -r file; do
    node --check "$file"
  done
fi

echo "PASS lint"
