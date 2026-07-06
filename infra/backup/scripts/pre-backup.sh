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
: "${BACKUP_DB_START_CONTAINERS:=true}"
: "${BACKUP_DB_MIN_BYTES:=1024}"
: "${BACKUP_NPM_DB_ENABLED:=true}"
: "${BACKUP_NPM_DB_REQUIRED:=false}"
: "${BACKUP_FULL_ENABLED:=true}"
: "${BACKUP_FULL_FAIL_SOFT:=true}"
: "${BACKUP_FULL_TARGET_NAME:=full}"
: "${BACKUP_FULL_SOURCES:=php,node,infra,docs,README.md}"
: "${BACKUP_FULL_EXCLUDES:=.git/,.DS_Store,infra/data/,infra/filebrowser/database/,infra/filebrowser/config/,infra/nginx-proxy-manager/data/,infra/backup/data/,infra/backup/staging/,infra/backup/rclone/,infra/backup/credentials/,php/*/vendor/,node/*/node_modules/}"

INFRA_COMPOSE="${ROOT_DIR}/infra/compose.yaml"
INFRA_ENV="${ROOT_DIR}/infra/.env"
NPM_COMPOSE="${ROOT_DIR}/infra/nginx-proxy-manager/compose.yaml"
NPM_ENV="${ROOT_DIR}/infra/nginx-proxy-manager/.env"

container_running() {
  docker ps --format '{{.Names}}' | grep -Fxq "$1"
}

wait_for_mariadb() {
  local container="$1"
  local password="$2"
  local attempts="${3:-60}"

  for ((i = 1; i <= attempts; i++)); do
    if docker exec "${container}" mariadb-admin ping \
      -uroot "-p${password}" --silent >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "ERRO: ${container} nao respondeu apos ${attempts} tentativas."
  return 1
}

ensure_container_running() {
  local container="$1"
  local compose_file="$2"
  local env_file="$3"
  local service="$4"
  local password="$5"

  if container_running "${container}"; then
    return 0
  fi

  if [[ "${BACKUP_DB_START_CONTAINERS}" != "true" ]]; then
    echo "ERRO: container ${container} parado e BACKUP_DB_START_CONTAINERS=false."
    return 1
  fi

  echo "Container ${container} parado; iniciando servico ${service}..."
  if [[ -f "${env_file}" ]]; then
    docker compose -f "${compose_file}" --env-file "${env_file}" up -d "${service}"
  else
    echo "ERRO: ${env_file} nao encontrado; nao e possivel subir ${container}."
    return 1
  fi

  wait_for_mariadb "${container}" "${password}"
}

validate_sql_dump() {
  local file="$1"
  local label="$2"
  local min_bytes="${BACKUP_DB_MIN_BYTES}"

  if [[ ! -s "${file}" ]]; then
    echo "ERRO: dump ${label} vazio ou inexistente: ${file}"
    return 1
  fi

  local size
  size="$(wc -c < "${file}" | tr -d ' ')"
  if [[ "${size}" -lt "${min_bytes}" ]]; then
    echo "ERRO: dump ${label} muito pequeno (${size} bytes): ${file}"
    return 1
  fi

  if ! grep -qE '^(CREATE DATABASE|USE `|Dump completed)' "${file}"; then
    echo "ERRO: dump ${label} parece invalido (sem marcadores SQL esperados): ${file}"
    return 1
  fi

  echo "Dump ${label} validado (${size} bytes)."
}

dump_mariadb_database() {
  local container="$1"
  local password="$2"
  local database="$3"
  local output_file="$4"

  docker exec "${container}" mariadb-dump \
    -uroot \
    "-p${password}" \
    --single-transaction \
    --routines \
    --events \
    --databases "${database}" \
    > "${output_file}"
}

run_full_backup() {
  echo "Gerando clone completo de arquivos (full backup)..."
  local full_dir="${RUN_DIR}/${BACKUP_FULL_TARGET_NAME}"
  mkdir -p "${full_dir}"

  local sources excludes
  IFS=',' read -r -a sources <<< "${BACKUP_FULL_SOURCES}"
  IFS=',' read -r -a excludes <<< "${BACKUP_FULL_EXCLUDES}"

  local rsync_args=(-a)
  local pattern trimmed
  for pattern in "${excludes[@]}"; do
    trimmed="$(echo "${pattern}" | xargs)"
    if [[ -n "${trimmed}" ]]; then
      rsync_args+=("--exclude=${trimmed}")
    fi
  done

  local src src_trimmed src_path
  for src in "${sources[@]}"; do
    src_trimmed="$(echo "${src}" | xargs)"
    [[ -z "${src_trimmed}" ]] && continue
    src_path="${ROOT_DIR}/${src_trimmed}"

    if [[ -d "${src_path}" ]]; then
      mkdir -p "${full_dir}/${src_trimmed}"
      rsync "${rsync_args[@]}" "${src_path}/" "${full_dir}/${src_trimmed}/"
    elif [[ -f "${src_path}" ]]; then
      mkdir -p "$(dirname "${full_dir}/${src_trimmed}")"
      rsync "${rsync_args[@]}" "${src_path}" "${full_dir}/${src_trimmed}"
    else
      echo "Fonte ${src_trimmed} nao encontrada; ignorando."
    fi
  done
}

if [[ -z "${MARIADB_ROOT_PASSWORD:-}" ]]; then
  echo "ERRO: MARIADB_ROOT_PASSWORD nao definido. Configure em infra/.env."
  exit 1
fi

echo "=== Backup do banco principal (obrigatorio) ==="
ensure_container_running \
  "${MARIADB_CONTAINER}" \
  "${INFRA_COMPOSE}" \
  "${INFRA_ENV}" \
  "mariadb" \
  "${MARIADB_ROOT_PASSWORD}"

MAIN_DUMP="${RUN_DIR}/sql/${MARIADB_DATABASE}.sql"
echo "Gerando dump de ${MARIADB_CONTAINER}/${MARIADB_DATABASE}..."
dump_mariadb_database \
  "${MARIADB_CONTAINER}" \
  "${MARIADB_ROOT_PASSWORD}" \
  "${MARIADB_DATABASE}" \
  "${MAIN_DUMP}"
validate_sql_dump "${MAIN_DUMP}" "${MARIADB_DATABASE}"

if [[ "${BACKUP_NPM_DB_ENABLED}" == "true" ]]; then
  echo "=== Backup do banco do NPM (opcional) ==="
  if [[ -z "${NPM_DB_ROOT_PASSWORD:-}" || -z "${NPM_DB_NAME:-}" ]]; then
    msg="NPM_DB_ROOT_PASSWORD ou NPM_DB_NAME nao definido"
    if [[ "${BACKUP_NPM_DB_REQUIRED}" == "true" ]]; then
      echo "ERRO: ${msg}."
      exit 1
    fi
    echo "AVISO: ${msg}; dump do NPM ignorado."
  elif ensure_container_running \
    "${NPM_DB_CONTAINER}" \
    "${NPM_COMPOSE}" \
    "${NPM_ENV}" \
    "npm_db" \
    "${NPM_DB_ROOT_PASSWORD}"; then
    NPM_DUMP="${RUN_DIR}/sql/${NPM_DB_NAME}.sql"
    echo "Gerando dump de ${NPM_DB_CONTAINER}/${NPM_DB_NAME}..."
    dump_mariadb_database \
      "${NPM_DB_CONTAINER}" \
      "${NPM_DB_ROOT_PASSWORD}" \
      "${NPM_DB_NAME}" \
      "${NPM_DUMP}"
    validate_sql_dump "${NPM_DUMP}" "${NPM_DB_NAME}"
  elif [[ "${BACKUP_NPM_DB_REQUIRED}" == "true" ]]; then
    echo "ERRO: nao foi possivel subir ${NPM_DB_CONTAINER} para o dump."
    exit 1
  else
    echo "AVISO: dump do NPM ignorado (container indisponivel)."
  fi
fi

echo "=== Configuracoes criticas ==="
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

if [[ "${BACKUP_FULL_ENABLED}" == "true" ]]; then
  echo "=== Clone de arquivos (secundario) ==="
  if ! run_full_backup; then
    if [[ "${BACKUP_FULL_FAIL_SOFT}" == "true" ]]; then
      echo "AVISO: full backup falhou; dumps SQL e configs serao enviados ao Kopia."
    else
      echo "ERRO: full backup falhou."
      exit 1
    fi
  fi
fi

echo "${TIMESTAMP}" > "${STAGING_DIR}/latest"
echo "Pre-backup concluido: ${RUN_DIR}"
echo "SQL gerado: ${MAIN_DUMP}"
