#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
BACKUP_DIR="${ROOT_DIR}/infra/backup"

"${BACKUP_DIR}/scripts/pre-backup.sh"

if [[ ! -f "${BACKUP_DIR}/.env" ]]; then
  echo "Arquivo ${BACKUP_DIR}/.env nao encontrado."
  echo "Copie infra/backup/.env.example para infra/backup/.env e ajuste os valores."
  exit 1
fi

docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" up -d

LATEST_RUN="$(cat "${BACKUP_DIR}/staging/latest")"
TARGET_DIR="/staging/${LATEST_RUN}"

docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" exec -T kopia_backup \
  kopia snapshot create "${TARGET_DIR}" --all

docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" exec -T kopia_backup \
  kopia snapshot list "${TARGET_DIR}"

echo "Snapshot criado com sucesso para ${TARGET_DIR}"
