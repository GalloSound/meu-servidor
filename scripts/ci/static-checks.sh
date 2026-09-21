#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

if grep -q 'composer update' php/Dockerfile; then
  fail "php/Dockerfile ainda executa composer update"
fi
if grep -q 'server-password' infra/backup/compose.yaml; then
  fail "infra/backup/compose.yaml expoe senha na linha de comando"
fi
if grep -q 'npm install' node/apigsfacil/Dockerfile; then
  fail "node/apigsfacil/Dockerfile ainda usa npm install"
fi
if ! grep -q 'npm ci --omit=dev' node/apigsfacil/Dockerfile; then
  fail "Dockerfile do Node sem npm ci --omit=dev"
fi

for file in \
  infra/compose.yaml \
  infra/nginx-proxy-manager/compose.yaml \
  php/compose.yaml \
  node/apigsfacil/compose.yaml \
  infra/backup/compose.yaml
do
  if ! grep -q 'healthcheck:' "$file"; then
    fail "sem healthcheck em ${file}"
  fi
done

if ! grep -q 'service_healthy' infra/compose.yaml; then
  fail "phpMyAdmin sem depends_on healthy"
fi
if ! grep -q 'service_healthy' infra/nginx-proxy-manager/compose.yaml; then
  fail "NPM sem depends_on healthy"
fi

echo "PASS static-checks"
