#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BACKUP_DIR="${ROOT_DIR}/infra/backup"

if [[ ! -f "${BACKUP_DIR}/.env" ]]; then
  echo "Arquivo ${BACKUP_DIR}/.env nao encontrado."
  echo "Copie infra/backup/.env.example para infra/backup/.env e ajuste os valores."
  exit 1
fi

set -a
# shellcheck disable=SC1091
source "${BACKUP_DIR}/.env"
set +a

: "${KOPIA_RCLONE_EXE:=/usr/bin/rclone}"
: "${RCLONE_REMOTE_NAME:?Defina RCLONE_REMOTE_NAME no infra/backup/.env}"
: "${RCLONE_REMOTE_PATH:?Defina RCLONE_REMOTE_PATH no infra/backup/.env}"
: "${RCLONE_CONFIG:=/rclone/rclone.conf}"

if [[ ! -f "${BACKUP_DIR}/rclone/rclone.conf" ]]; then
  echo "Arquivo ${BACKUP_DIR}/rclone/rclone.conf nao encontrado."
  echo "Crie com 'rclone config' no host e copie para esse caminho."
  exit 1
fi

docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" up -d

if docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" exec -T kopia_backup \
  kopia repository status >/dev/null 2>&1; then
  echo "Repositorio Kopia ja configurado e conectado."
  exit 0
fi

CREATE_OUTPUT="$(
  docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" exec -T kopia_backup \
    kopia repository create rclone \
    --rclone-exe="${KOPIA_RCLONE_EXE}" \
    --remote-path="${RCLONE_REMOTE_NAME}:${RCLONE_REMOTE_PATH}" 2>&1
)" || CREATE_EXIT=$?

CREATE_EXIT="${CREATE_EXIT:-0}"
if [[ "${CREATE_EXIT}" -ne 0 ]]; then
  if echo "${CREATE_OUTPUT}" | rg -q "found existing data in storage location"; then
    echo "Repositorio ja existe no destino remoto; assumindo configuracao existente."
    exit 0
  fi
  echo "${CREATE_OUTPUT}"
  exit "${CREATE_EXIT}"
fi

echo "Repositorio Kopia (Rclone + Google Drive) criado com sucesso."
