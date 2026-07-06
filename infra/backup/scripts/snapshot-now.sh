#!/usr/bin/env bash
# Executa o script com bash (portavel entre sistemas).
# Retorno esperado: nenhum; apenas define o interpretador.

set -euo pipefail
# -e: para o script se qualquer comando falhar.
# -u: erro se usar variavel nao definida.
# -o pipefail: falha em pipeline se algum comando da cadeia falhar.
# Retorno esperado: nenhum; apenas configura o comportamento de erro.

# Caminho absoluto da raiz do projeto (meu-servidor).
# Retorno esperado: ex. /Applications/Docker_Projetos/meu-servidor
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Caminho absoluto da stack de backup.
# Retorno esperado: ex. .../meu-servidor/infra/backup
BACKUP_DIR="${ROOT_DIR}/infra/backup"

# Gera dumps SQL (obrigatorio), copia configs e (se habilitado) rsync em staging/.
# Retorno esperado: mensagens do pre-backup, dump validado e staging/latest atualizado.
"${BACKUP_DIR}/scripts/pre-backup.sh"

# Confirma que o dump SQL principal existe antes de enviar ao Kopia.
# Retorno esperado: continua em silencio; ou mensagem de erro + exit 1.
LATEST_RUN="$(cat "${BACKUP_DIR}/staging/latest")"
SQL_DIR="${BACKUP_DIR}/staging/${LATEST_RUN}/sql"
if ! ls "${SQL_DIR}"/*.sql >/dev/null 2>&1; then
  echo "ERRO: nenhum dump SQL encontrado em ${SQL_DIR}. Snapshot abortado."
  exit 1
fi

# Valida se o .env existe antes de subir o container.
# Retorno esperado: continua em silencio; ou mensagem de erro + exit 1.
if [[ ! -f "${BACKUP_DIR}/.env" ]]; then
  echo "Arquivo ${BACKUP_DIR}/.env nao encontrado."
  echo "Copie infra/backup/.env.example para infra/backup/.env e ajuste os valores."
  exit 1
fi

# Sobe (ou mantem) o container kopia_backup em background.
# Retorno esperado: "Container kopia_backup Running" ou "Started".
docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" up -d

# Caminho da pasta de staging dentro do container (volume montado em /staging).
# Retorno esperado: ex. /staging/20260706_115030
TARGET_DIR="/staging/${LATEST_RUN}"

# Cria snapshot criptografado no repositorio Kopia (Google Drive via rclone).
# Retorno esperado: "Created snapshot with root ... ID ... in Xs".
docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" exec -T kopia_backup \
  kopia snapshot create "${TARGET_DIR}"

# Lista snapshots da pasta para confirmar que foi gravado.
# Retorno esperado: linha com ID, tamanho, data e caminho do snapshot.
docker compose -f "${BACKUP_DIR}/compose.yaml" --env-file "${BACKUP_DIR}/.env" exec -T kopia_backup \
  kopia snapshot list "${TARGET_DIR}"

# Mensagem final de sucesso.
# Retorno esperado: "Snapshot criado com sucesso para /staging/20260706_115030"
echo "Snapshot criado com sucesso para ${TARGET_DIR}"
