#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BACKUP_DIR="${ROOT_DIR}/infra/backup"
STAGING_DIR="${BACKUP_DIR}/staging"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
RUN_DIR="${STAGING_DIR}/${TIMESTAMP}"

mkdir -p "${RUN_DIR}/sql" "${RUN_DIR}/configs"

if [[ -f "${BACKUP_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${BACKUP_DIR}/.env"
  set +a
else
  echo "Arquivo ${BACKUP_DIR}/.env nao encontrado."
  echo "Copie infra/backup/.env.example para infra/backup/.env e ajuste os valores."
  exit 1
fi

if [[ -f "${ROOT_DIR}/infra/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/infra/.env"
  set +a
fi

if [[ -f "${ROOT_DIR}/infra/nginx-proxy-manager/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${ROOT_DIR}/infra/nginx-proxy-manager/.env"
  set +a
fi

: "${MARIADB_CONTAINER:=mariadb_global}"
: "${MARIADB_DATABASE:=gpsjundi_bdgsfacil}"
: "${NPM_DB_CONTAINER:=npm_db}"

if [[ -z "${MARIADB_ROOT_PASSWORD:-}" ]]; then
  echo "MARIADB_ROOT_PASSWORD nao definido. Configure em infra/.env."
  exit 1
fi

echo "Gerando dump do banco principal (${MARIADB_CONTAINER}/${MARIADB_DATABASE})..."
docker exec "${MARIADB_CONTAINER}" mariadb-dump \
  -uroot \
  "-p${MARIADB_ROOT_PASSWORD}" \
  --single-transaction \
  --routines \
  --events \
  --databases "${MARIADB_DATABASE}" \
  > "${RUN_DIR}/sql/${MARIADB_DATABASE}.sql"

if docker ps --format '{{.Names}}' | rg -x "${NPM_DB_CONTAINER}" >/dev/null 2>&1; then
  if [[ -n "${NPM_DB_ROOT_PASSWORD:-}" && -n "${NPM_DB_NAME:-}" ]]; then
    echo "Gerando dump do banco do NPM (${NPM_DB_CONTAINER}/${NPM_DB_NAME})..."
    docker exec "${NPM_DB_CONTAINER}" mariadb-dump \
      -uroot \
      "-p${NPM_DB_ROOT_PASSWORD}" \
      --single-transaction \
      --databases "${NPM_DB_NAME}" \
      > "${RUN_DIR}/sql/${NPM_DB_NAME}.sql"
  else
    echo "NPM_DB_ROOT_PASSWORD ou NPM_DB_NAME nao definido; dump do NPM ignorado."
  fi
else
  echo "Container ${NPM_DB_CONTAINER} nao esta em execucao; dump do NPM ignorado."
fi

echo "Copiando configuracoes criticas..."
mkdir -p "${RUN_DIR}/configs/infra" "${RUN_DIR}/configs/nginx-proxy-manager"
cp "${ROOT_DIR}/infra/compose.yaml" "${RUN_DIR}/configs/infra/compose.yaml"
cp "${ROOT_DIR}/infra/mariadb.cnf" "${RUN_DIR}/configs/infra/mariadb.cnf"
cp "${ROOT_DIR}/infra/nginx-proxy-manager/compose.yaml" "${RUN_DIR}/configs/nginx-proxy-manager/compose.yaml"
cp "${ROOT_DIR}/php/compose.yaml" "${RUN_DIR}/configs/php-compose.yaml"
cp "${ROOT_DIR}/node/apigsfacil/compose.yaml" "${RUN_DIR}/configs/apigsfacil-compose.yaml" 2>/dev/null || true

for env_file in \
  "${ROOT_DIR}/infra/.env" \
  "${ROOT_DIR}/infra/nginx-proxy-manager/.env" \
  "${ROOT_DIR}/php/.env" \
  "${ROOT_DIR}/node/apigsfacil/.env"; do
  if [[ -f "${env_file}" ]]; then
    cp "${env_file}" "${RUN_DIR}/configs/$(basename "${env_file}").$(basename "$(dirname "${env_file}")")"
  fi
done

if [[ -d "${ROOT_DIR}/infra/nginx-proxy-manager/data/letsencrypt" ]]; then
  tar -czf "${RUN_DIR}/configs/letsencrypt.tar.gz" \
    -C "${ROOT_DIR}/infra/nginx-proxy-manager/data" \
    letsencrypt
fi

echo "${TIMESTAMP}" > "${STAGING_DIR}/latest"
echo "Pre-backup concluido: ${RUN_DIR}"
