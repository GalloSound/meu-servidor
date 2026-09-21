#!/usr/bin/env bash
# Instala dependencias PHP a partir do composer.lock.
# Padrao: dry-run. Nao executa atualizacao de dependencias.
set -euo pipefail

PHP_DIR="${PHP_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MODE="dry-run"
COMPOSER_IMAGE="${COMPOSER_IMAGE:-composer:2@sha256:a5f59b9fd2faf31218632be4809dc6491761085e8064c31dc3b84378c48c248b}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --apply) MODE="apply" ;;
    -h|--help)
      echo "Uso: $0 [--dry-run|--apply]"
      exit 0
      ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
  esac
  shift
done

projects="app app_nf app_sistema gsfacilFront googlecalendar peoplecontacts"

run_install() {
  local dir="$1"
  if [[ "$MODE" == "dry-run" ]]; then
    echo "dry-run: composer install --no-dev --prefer-dist --no-interaction --working-dir=${dir}"
    return 0
  fi
  if [[ -n "${COMPOSER_INSTALL_CMD:-}" ]]; then
    # shellcheck disable=SC2086
    $COMPOSER_INSTALL_CMD "$dir"
    return 0
  fi
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "${dir}:/app" \
    -w /app \
    "$COMPOSER_IMAGE" \
    install --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader
}

echo "mode=${MODE}"
for name in $projects; do
  dir="${PHP_DIR}/${name}"
  if [[ ! -f "${dir}/composer.json" ]]; then
    echo "skip=${name} sem composer.json"
    continue
  fi
  if [[ ! -f "${dir}/composer.lock" ]]; then
    echo "skip=${name} sem composer.lock"
    continue
  fi
  echo "install=${name}"
  run_install "$dir"
done
