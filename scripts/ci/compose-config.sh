#!/usr/bin/env bash
# Valida os compose sem imprimir o YAML interpolado (ele pode conter segredo).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
created=""
trap 'rm -rf "$TMP"; if [[ -n "$created" ]]; then rm -f "$created"; fi' EXIT

repo_secret="${TMP}/kopia-repository-password"
ui_secret="${TMP}/kopia-ui.htpasswd"
printf 'placeholder\n' > "$repo_secret"
# shellcheck disable=SC2016
printf 'admin:$apr1$ci$placeholder\n' > "$ui_secret"

check() {
  local file="$1"
  local envfile="$2"
  shift 2
  echo "compose config ${file}"
  docker compose -f "$file" --env-file "$envfile" "$@" config --quiet
}

check infra/compose.yaml infra/.env.example
check infra/nginx-proxy-manager/compose.yaml infra/nginx-proxy-manager/.env.example
check php/compose.yaml php/.env.example

node_env="node/apigsfacil/.env"
if [[ ! -f "$node_env" ]]; then
  cp node/apigsfacil/.env.example "$node_env"
  created="$node_env"
fi
check node/apigsfacil/compose.yaml node/apigsfacil/.env.example

KOPIA_REPOSITORY_PASSWORD_FILE="$repo_secret" \
KOPIA_UI_HTPASSWD_FILE="$ui_secret" \
  check infra/backup/compose.yaml infra/backup/.env.example

echo "PASS compose-config"
