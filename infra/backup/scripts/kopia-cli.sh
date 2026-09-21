#!/usr/bin/env bash
# Executa o Kopia dentro do container sem colocar senha no argv do host.
# O entrypoint le /run/secrets/kopia_repository_password.

kopia_cli() {
  docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" exec -T kopia_backup \
    /usr/local/bin/kopia-entrypoint "$@"
}
