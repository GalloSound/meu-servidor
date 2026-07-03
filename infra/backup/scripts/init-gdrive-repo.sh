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

: "${GDRIVE_FOLDER_ID:?Defina GDRIVE_FOLDER_ID no infra/backup/.env}"
: "${GDRIVE_CREDENTIALS_FILE:=/credentials/gdrive-service-account.json}"

docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" up -d

docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" exec -T kopia_backup \
  kopia repository create gdrive \
  --folder-id "${GDRIVE_FOLDER_ID}" \
  --credentials-file "${GDRIVE_CREDENTIALS_FILE}"

echo "Repositorio Kopia criado no Google Drive com sucesso."
