#!/usr/bin/env bash
# Gera os arquivos de senha do Kopia a partir do .env, sem imprimir segredo
# e sem colocar a senha em argv.
set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-${BACKUP_DIR}/.env}"
SECRETS_DIR="${SECRETS_DIR:-${BACKUP_DIR}/secrets}"
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=true ;;
    -h|--help)
      echo "Uso: $0 [--force]"
      exit 0
      ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Arquivo ausente: ${ENV_FILE}" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${KOPIA_UI_USER:?Defina KOPIA_UI_USER}"
: "${KOPIA_UI_PASSWORD:?Defina KOPIA_UI_PASSWORD}"
: "${KOPIA_REPOSITORY_PASSWORD:?Defina KOPIA_REPOSITORY_PASSWORD}"

case "$KOPIA_UI_USER" in
  *:*|*[[:space:]]*)
    echo "KOPIA_UI_USER nao pode conter espaco ou dois-pontos." >&2
    exit 1
    ;;
esac

mkdir -p "$SECRETS_DIR"
umask 077

repo_file="${SECRETS_DIR}/kopia-repository-password"
htpasswd_file="${SECRETS_DIR}/kopia-ui.htpasswd"

if [[ "$FORCE" != "true" && -s "$repo_file" && -s "$htpasswd_file" ]]; then
  echo "Secrets ja existem em ${SECRETS_DIR}. Use --force para regravar."
  exit 0
fi

pass_file="$(mktemp)"
cleanup() {
  rm -f "$pass_file"
}
trap cleanup EXIT
printf '%s\n' "$KOPIA_UI_PASSWORD" > "$pass_file"

if command -v htpasswd >/dev/null 2>&1; then
  htpasswd -niB "$KOPIA_UI_USER" < "$pass_file" > "$htpasswd_file"
elif command -v openssl >/dev/null 2>&1; then
  hash="$(openssl passwd -apr1 -stdin < "$pass_file")"
  printf '%s:%s\n' "$KOPIA_UI_USER" "$hash" > "$htpasswd_file"
else
  echo "Instale htpasswd ou openssl para gerar o htpasswd." >&2
  exit 1
fi

printf '%s\n' "$KOPIA_REPOSITORY_PASSWORD" > "$repo_file"
chmod 600 "$repo_file" "$htpasswd_file"

echo "Secrets gravados em ${SECRETS_DIR} (senha do repositorio e htpasswd da UI)."
echo "O Compose le esses arquivos. A senha nao vai para a linha de comando do container."
