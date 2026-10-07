#!/usr/bin/env bash
# Remove execucoes antigas de infra/backup/staging depois de um snapshot confirmado.
# Mantem 3 dias, 1 semana anterior e 1 mes anterior.
# Padrao: --dry-run. Nao apaga snapshots Kopia, volumes Docker nem runs sem marcador.
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

load_count() {
  local key="$1"
  local fallback="$2"
  local value="${!key:-}"
  if [[ -z "$value" ]]; then
    value="$(env_assignment "$key")"
  fi
  if [[ -z "$value" ]]; then
    value="$fallback"
  fi
  if ! printf '%s' "$value" | grep -Eq '^[0-9]+$'; then
    echo "${key} deve ser um inteiro (recebido: ${value})." >&2
    exit 1
  fi
  printf '%s' "$value"
}

if [[ -z "${BACKUP_STAGING_CLEANUP:-}" ]]; then
  BACKUP_STAGING_CLEANUP="$(env_assignment BACKUP_STAGING_CLEANUP)"
fi
BACKUP_STAGING_CLEANUP="${BACKUP_STAGING_CLEANUP:-false}"
KEEP_DAILY="$(load_count BACKUP_STAGING_KEEP_DAILY 3)"
KEEP_WEEKLY="$(load_count BACKUP_STAGING_KEEP_WEEKLY 1)"
KEEP_MONTHLY="$(load_count BACKUP_STAGING_KEEP_MONTHLY 1)"
MODE="dry-run"

usage() {
  echo "Uso: $0 [--dry-run|--apply]" >&2
  echo "BACKUP_STAGING_KEEP_DAILY=3 BACKUP_STAGING_KEEP_WEEKLY=1 BACKUP_STAGING_KEEP_MONTHLY=1" >&2
  echo "BACKUP_STAGING_CLEANUP=true so com --apply" >&2
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

iso_week_of_run() {
  local ymd="${1:0:8}"
  local spec="${ymd:0:4}-${ymd:4:2}-${ymd:6:2}"
  if date --version >/dev/null 2>&1; then
    date -d "$spec" +%G-%V
  else
    date -j -f "%Y-%m-%d" "$spec" +%G-%V
  fi
}

month_of_run() {
  printf '%s' "${1:0:6}"
}

list_has() {
  printf '%s\n' "$1" | grep -Fxq "$2"
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

daily_names=""
daily_days=""
daily_count=0
weekly_names=""
weekly_weeks=""
weekly_count=0
monthly_names=""
monthly_months=""
monthly_count=0
newest_week=""
newest_month=""

while IFS= read -r base; do
  [[ -z "$base" ]] && continue
  if [[ -z "$newest_week" ]]; then
    newest_week="$(iso_week_of_run "$base")"
    newest_month="$(month_of_run "$base")"
  fi

  day="${base:0:8}"
  if [[ "$daily_count" -lt "$KEEP_DAILY" ]] && ! list_has "$daily_days" "$day"; then
    daily_names="${daily_names}${base}"$'\n'
    daily_days="${daily_days}${day}"$'\n'
    daily_count=$((daily_count + 1))
  fi

  week="$(iso_week_of_run "$base")"
  if [[ "$week" != "$newest_week" && "$weekly_count" -lt "$KEEP_WEEKLY" ]] && ! list_has "$weekly_weeks" "$week"; then
    weekly_names="${weekly_names}${base}"$'\n'
    weekly_weeks="${weekly_weeks}${week}"$'\n'
    weekly_count=$((weekly_count + 1))
  fi

  month="$(month_of_run "$base")"
  if [[ "$month" != "$newest_month" && "$monthly_count" -lt "$KEEP_MONTHLY" ]] && ! list_has "$monthly_months" "$month"; then
    monthly_names="${monthly_names}${base}"$'\n'
    monthly_months="${monthly_months}${month}"$'\n'
    monthly_count=$((monthly_count + 1))
  fi
done <<EOF
$(printf '%s' "$confirmed_runs" | sort -r)
EOF

keep_names=""
append_keep() {
  local base="$1"
  if ! list_has "$keep_names" "$base"; then
    keep_names="${keep_names}${base}"$'\n'
  fi
}

while IFS= read -r base; do
  [[ -z "$base" ]] && continue
  append_keep "$base"
done <<EOF
$(printf '%s%s%s' "$daily_names" "$weekly_names" "$monthly_names")
EOF

if [[ -n "$latest_name" ]] && is_run_name "$latest_name"; then
  append_keep "$latest_name"
fi

roles_of() {
  local base="$1"
  local roles=""
  if list_has "$daily_names" "$base"; then
    roles="daily"
  fi
  if list_has "$weekly_names" "$base"; then
    roles="${roles:+${roles},}weekly"
  fi
  if list_has "$monthly_names" "$base"; then
    roles="${roles:+${roles},}monthly"
  fi
  if [[ "$base" == "$latest_name" ]]; then
    roles="${roles:+${roles},}latest"
  fi
  printf '%s' "$roles"
}

echo "mode=${MODE}"
echo "staging=${STAGING_REAL}"
echo "keep_daily=${KEEP_DAILY}"
echo "keep_weekly=${KEEP_WEEKLY}"
echo "keep_monthly=${KEEP_MONTHLY}"

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

  if list_has "$keep_names" "$base"; then
    echo "keep=${base} $(roles_of "$base")"
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
