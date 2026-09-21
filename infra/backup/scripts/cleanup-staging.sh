#!/usr/bin/env bash
# Remove execucoes antigas de infra/backup/staging depois de um snapshot confirmado.
# Padrao: dry-run. Nao apaga snapshots Kopia, volumes Docker nem runs sem marcador.
# BACKUP_STAGING_KEEP aceita 2 ou 3 (padrao 3).
# --apply so apaga quando BACKUP_STAGING_CLEANUP=true.
set -euo pipefail

BACKUP_DIR_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGING_DIR="${STAGING_DIR:-${BACKUP_DIR_DEFAULT}/staging}"
ENV_FILE="${BACKUP_ENV_FILE:-${BACKUP_DIR_DEFAULT}/.env}"

env_assignment() {
  local key="$1"
  if [[ ! -f "$ENV_FILE" ]]; then
    return 0
  fi
  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '[:space:]' || true
}

if [[ -z "${BACKUP_STAGING_KEEP:-}" ]]; then
  BACKUP_STAGING_KEEP="$(env_assignment BACKUP_STAGING_KEEP)"
fi
if [[ -z "${BACKUP_STAGING_CLEANUP:-}" ]]; then
  BACKUP_STAGING_CLEANUP="$(env_assignment BACKUP_STAGING_CLEANUP)"
fi
KEEP="${BACKUP_STAGING_KEEP:-3}"
BACKUP_STAGING_CLEANUP="${BACKUP_STAGING_CLEANUP:-false}"
MODE="dry-run"

usage() {
  echo "Uso: $0 [--dry-run|--apply]" >&2
  echo "BACKUP_STAGING_KEEP=2|3  BACKUP_STAGING_CLEANUP=true so com --apply" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --apply) MODE="apply" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ "$KEEP" != "2" && "$KEEP" != "3" ]]; then
  echo "BACKUP_STAGING_KEEP deve ser 2 ou 3 (recebido: ${KEEP})." >&2
  exit 1
fi

if [[ ! -d "$STAGING_DIR" ]]; then
  echo "Staging ausente: ${STAGING_DIR}" >&2
  exit 1
fi

STAGING_REAL="$(cd "$STAGING_DIR" && pwd -P)"

if [[ "$MODE" == "apply" && "${BACKUP_STAGING_CLEANUP:-false}" != "true" ]]; then
  echo "BACKUP_STAGING_CLEANUP nao esta true. Nada foi apagado." >&2
  exit 2
fi

is_run_name() {
  printf '%s' "$1" | grep -Eq '^[0-9]{8}_[0-9]{6}$'
}

latest_name=""
if [[ -f "${STAGING_REAL}/latest" ]]; then
  latest_name="$(tr -d '[:space:]' < "${STAGING_REAL}/latest")"
fi

confirmed_runs=""
while IFS= read -r dir; do
  [[ -z "$dir" ]] && continue
  base="$(basename "$dir")"
  if is_run_name "$base" && [[ -f "${dir}/SNAPSHOT_CONFIRMED" ]]; then
    confirmed_runs="${confirmed_runs}${base}"$'\n'
  fi
done <<EOF
$(find "$STAGING_REAL" -mindepth 1 -maxdepth 1 -type d | sort -r)
EOF

keep_names=""
kept_confirmed=0
while IFS= read -r base; do
  [[ -z "$base" ]] && continue
  if [[ "$kept_confirmed" -lt "$KEEP" ]]; then
    keep_names="${keep_names}${base}"$'\n'
    kept_confirmed=$((kept_confirmed + 1))
  fi
done <<EOF
$(printf '%s' "$confirmed_runs" | sort -r)
EOF

if [[ -n "$latest_name" ]] && is_run_name "$latest_name"; then
  if ! printf '%s\n' "$keep_names" | grep -Fxq "$latest_name"; then
    keep_names="${keep_names}${latest_name}"$'\n'
  fi
fi

in_keep() {
  printf '%s\n' "$keep_names" | grep -Fxq "$1"
}

echo "mode=${MODE}"
echo "staging=${STAGING_REAL}"
echo "keep_count=${KEEP}"

remove_count=0
while IFS= read -r dir; do
  [[ -z "$dir" ]] && continue
  base="$(basename "$dir")"
  if ! is_run_name "$base"; then
    echo "keep=${base} ignored"
    continue
  fi

  target_real="$(cd "$dir" && pwd -P)"
  case "$target_real" in
    "$STAGING_REAL"/*) ;;
    *)
      echo "Recusa caminho fora do staging: ${target_real}" >&2
      exit 1
      ;;
  esac

  if [[ ! -f "${dir}/SNAPSHOT_CONFIRMED" ]]; then
    echo "keep=${base} unconfirmed"
    continue
  fi

  if in_keep "$base"; then
    echo "keep=${base} confirmed"
    continue
  fi

  echo "remove=${base}"
  remove_count=$((remove_count + 1))
  if [[ "$MODE" == "apply" ]]; then
    rm -rf -- "$target_real"
    echo "removed=${base}"
  fi
done <<EOF
$(find "$STAGING_REAL" -mindepth 1 -maxdepth 1 -type d | sort)
EOF

if [[ "$MODE" == "dry-run" ]]; then
  echo "dry-run: ${remove_count} execucao(oes) seriam removidas. Nada foi apagado."
fi
