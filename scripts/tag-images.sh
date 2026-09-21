#!/usr/bin/env bash
# Marca as imagens locais com o commit que as produziu.
# Padrao: dry-run. Nao faz push e nao apaga tags antigas.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="dry-run"
DOCKER_BIN="${DOCKER_BIN:-docker}"

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

platform_sha="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
if git -C "${ROOT}/node/apigsfacil" rev-parse --short=12 HEAD >/dev/null 2>&1; then
  node_sha="$(git -C "${ROOT}/node/apigsfacil" rev-parse --short=12 HEAD)"
else
  node_sha="$platform_sha"
fi

kopia_tag="${KOPIA_IMAGE_TAG:-0.23.1}"

plan() {
  printf '%s %s %s\n' "$1" "$2" "$3"
}

echo "mode=${MODE}"
echo "platform_sha=${platform_sha}"
echo "node_sha=${node_sha}"

while read -r source target stack; do
  [[ -z "$source" ]] && continue
  echo "tag stack=${stack} source=${source} target=${target}"
  if [[ "$MODE" == "apply" ]]; then
    "$DOCKER_BIN" tag "$source" "$target"
  fi
done <<EOF
$(plan meu-servidor/php-global:local "meu-servidor/php-global:sha-${platform_sha}" php
plan "meu-servidor/apigsfacil:local" "meu-servidor/apigsfacil:sha-${node_sha}" node
plan "meu-servidor/kopia-rclone:${kopia_tag}" "meu-servidor/kopia-rclone:sha-${platform_sha}" backup)
EOF

if [[ "$MODE" == "dry-run" ]]; then
  echo "dry-run: nenhuma tag foi criada."
fi
