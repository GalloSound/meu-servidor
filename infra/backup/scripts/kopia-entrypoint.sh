#!/bin/sh
# Le a senha do repositorio de um arquivo e exec o Kopia.
# A senha nao entra em argv. O arquivo e montado como secret do Compose.
set -eu

if [ -n "${KOPIA_PASSWORD_FILE:-}" ]; then
  if [ ! -f "$KOPIA_PASSWORD_FILE" ]; then
    echo "Arquivo de senha do repositorio ausente: $KOPIA_PASSWORD_FILE" >&2
    exit 1
  fi
  # Uma linha. Quebras de linha finais nao fazem parte da senha.
  KOPIA_PASSWORD=$(tr -d '\r\n' < "$KOPIA_PASSWORD_FILE")
  export KOPIA_PASSWORD
  unset KOPIA_PASSWORD_FILE
fi

if [ -z "${KOPIA_PASSWORD:-}" ]; then
  echo "KOPIA_PASSWORD ausente. Monte o secret do repositorio." >&2
  exit 1
fi

KOPIA_BIN="${KOPIA_BIN:-/bin/kopia}"
exec "$KOPIA_BIN" "$@"
