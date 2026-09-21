#!/usr/bin/env bash
# Valida e prepara um restore isolado (configs + SQL + aplicacao).
# Nao importa no MariaDB de producao e nao apaga a origem.
# Padrao: --dry-run. --prepare-isolated copia para um diretorio vazio.
# --import-isolated sobe um MariaDB temporario com tmpfs e --network none.
set -euo pipefail

MODE="dry-run"
SOURCE=""
DEST=""
REQUIRE_APP=false
CONTAINER_NAME="${RESTORE_DRILL_CONTAINER:-mariadb_restore_drill}"
IMPORT_ATTEMPTS="${RESTORE_DRILL_ATTEMPTS:-30}"
IMPORT_SLEEP="${RESTORE_DRILL_SLEEP:-2}"
DOCKER_BIN="${DOCKER_BIN:-docker}"
MARIADB_IMAGE="${RESTORE_DRILL_MARIADB_IMAGE:-mariadb:11.4@sha256:70cc072b29b4a89ae07abb2d4da2c64678a7f2dfe092751bb51c87d67dc1338b}"

usage() {
  echo "Uso: $0 --source DIR [--dry-run] [--require-app] [--prepare-isolated DEST] [--import-isolated DEST]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="${2:-}"; shift ;;
    --dry-run) MODE="dry-run" ;;
    --require-app) REQUIRE_APP=true ;;
    --prepare-isolated) MODE="prepare"; DEST="${2:-}"; shift ;;
    --import-isolated) MODE="import"; DEST="${2:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if [[ -z "$SOURCE" || ! -d "$SOURCE" ]]; then
  echo "Informe --source com um diretorio de staging." >&2
  usage
  exit 1
fi

SOURCE_REAL="$(cd "$SOURCE" && pwd -P)"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

refuse_protected() {
  local path="$1"
  case "$path" in
    */infra/data|*/infra/data/*|\
    */infra/nginx-proxy-manager/data|*/infra/nginx-proxy-manager/data/*|\
    */infra/backup/data|*/infra/backup/data/*|\
    */var/lib/mysql|*/var/lib/mysql/*)
      echo "Destino protegido: ${path}" >&2
      return 1
      ;;
  esac
  return 0
}

validate_sql() {
  local file="$1"
  if [[ ! -s "$file" ]]; then
    echo "FAIL sql vazio: ${file}" >&2
    return 1
  fi
  if ! grep -qE '^(CREATE DATABASE|USE `|Dump completed)' "$file"; then
    echo "FAIL sql sem marcadores: ${file}" >&2
    return 1
  fi
  local size hash
  size="$(wc -c < "$file" | tr -d ' ')"
  hash="$(hash_file "$file")"
  echo "PASS sql $(basename "$file") bytes=${size} sha256=${hash}"
}

echo "mode=${MODE}"
echo "source=${SOURCE_REAL}"

sql_ok=0
if [[ -d "${SOURCE_REAL}/sql" ]]; then
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    validate_sql "$file"
    sql_ok=$((sql_ok + 1))
  done <<EOF
$(find "${SOURCE_REAL}/sql" -maxdepth 1 -type f -name '*.sql' | sort)
EOF
fi

if [[ "$sql_ok" -lt 1 ]]; then
  echo "FAIL sql ausente" >&2
  exit 1
fi

for required in \
  "${SOURCE_REAL}/configs/infra/compose.yaml" \
  "${SOURCE_REAL}/configs/php-compose.yaml" \
  "${SOURCE_REAL}/configs/nginx-proxy-manager/compose.yaml"
do
  if [[ ! -s "$required" ]]; then
    echo "FAIL config ausente: ${required#"${SOURCE_REAL}/"}" >&2
    exit 1
  fi
  echo "PASS config ${required#"${SOURCE_REAL}/"}"
done

app_status="AUSENTE"
app_file=""
if [[ -d "${SOURCE_REAL}/full" ]]; then
  app_file="$(find "${SOURCE_REAL}/full" -type f -print | sed -n '1p')"
fi
if [[ -n "$app_file" ]]; then
  app_status="PASS"
  echo "PASS aplicacao full/"
else
  echo "aplicacao AUSENTE"
  if [[ "$REQUIRE_APP" == "true" ]]; then
    echo "FAIL aplicacao obrigatoria" >&2
    exit 1
  fi
fi

if [[ "$MODE" == "dry-run" ]]; then
  echo "dry-run: plano de restore isolado (configs + sql + aplicacao=${app_status}). Nada foi copiado."
  exit 0
fi

if [[ -z "$DEST" ]]; then
  echo "Informe o diretorio de destino." >&2
  exit 1
fi

refuse_protected "$DEST"
mkdir -p "$DEST"
DEST_REAL="$(cd "$DEST" && pwd -P)"
refuse_protected "$DEST_REAL"

case "$DEST_REAL" in
  "$SOURCE_REAL"|"$SOURCE_REAL"/*)
    echo "Destino nao pode ficar dentro da origem." >&2
    exit 1
    ;;
esac
case "$SOURCE_REAL" in
  "$DEST_REAL"/*)
    echo "Origem nao pode ficar dentro do destino." >&2
    exit 1
    ;;
esac

if [[ -n "$(ls -A "$DEST_REAL")" ]]; then
  echo "Destino precisa estar vazio: ${DEST_REAL}" >&2
  exit 1
fi

copy_tree() {
  local rel="$1"
  if [[ -d "${SOURCE_REAL}/${rel}" ]]; then
    mkdir -p "${DEST_REAL}/${rel}"
    cp -R "${SOURCE_REAL}/${rel}/." "${DEST_REAL}/${rel}/"
  elif [[ -f "${SOURCE_REAL}/${rel}" ]]; then
    mkdir -p "$(dirname "${DEST_REAL}/${rel}")"
    cp "${SOURCE_REAL}/${rel}" "${DEST_REAL}/${rel}"
  fi
}

copy_tree sql
copy_tree configs
if [[ "$app_status" == "PASS" ]]; then
  copy_tree full
fi

{
  echo "source=${SOURCE_REAL}"
  echo "aplicacao=${app_status}"
  find "$DEST_REAL" -type f | sort | while IFS= read -r file; do
    rel="${file#"${DEST_REAL}/"}"
    hash="$(hash_file "$file")"
    echo "${hash}  ${rel}"
  done
} > "${DEST_REAL}/MANIFEST.txt"

echo "PASS prepare ${DEST_REAL}"

if [[ "$MODE" != "import" ]]; then
  exit 0
fi

case "$CONTAINER_NAME" in
  mariadb_global|npm_db|phpmyadmin_global|nginx_proxy_manager|php_global|apigsfacil|kopia_backup|filebrowser_global)
    echo "Nome de container reservado: ${CONTAINER_NAME}" >&2
    exit 1
    ;;
esac

sql_file=""
for candidate in "${DEST_REAL}/sql"/*.sql; do
  if [[ -f "$candidate" ]]; then
    sql_file="$candidate"
    break
  fi
done
if [[ -z "$sql_file" ]]; then
  echo "FAIL sql para importacao" >&2
  exit 1
fi

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cnf="${root_dir}/infra/mariadb.cnf"
if [[ ! -f "$cnf" ]]; then
  echo "mariadb.cnf ausente: ${cnf}" >&2
  exit 1
fi

echo "import container=${CONTAINER_NAME} network=none tmpfs=mysql image=${MARIADB_IMAGE}"
"$DOCKER_BIN" run --rm -d \
  --name "$CONTAINER_NAME" \
  --network none \
  --tmpfs /var/lib/mysql \
  -v "${cnf}:/etc/mysql/conf.d/custom.cnf:ro" \
  -e MARIADB_ROOT_PASSWORD=restore-drill-only \
  -e MARIADB_DATABASE=gpsjundi_bdgsfacil \
  "$MARIADB_IMAGE" >/dev/null

cleanup_container() {
  "$DOCKER_BIN" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup_container EXIT

ready=0
attempt=0
while [[ "$attempt" -lt "$IMPORT_ATTEMPTS" ]]; do
  attempt=$((attempt + 1))
  if "$DOCKER_BIN" exec "$CONTAINER_NAME" mariadb-admin ping -uroot -prestore-drill-only --silent >/dev/null 2>&1; then
    ready=1
    break
  fi
  if [[ "$IMPORT_SLEEP" != "0" ]]; then
    sleep "$IMPORT_SLEEP"
  fi
done

if [[ "$ready" != "1" ]]; then
  echo "FAIL MariaDB isolado nao ficou pronto" >&2
  exit 1
fi

"$DOCKER_BIN" exec -i "$CONTAINER_NAME" mariadb -uroot -prestore-drill-only < "$sql_file"
"$DOCKER_BIN" exec "$CONTAINER_NAME" mariadb -uroot -prestore-drill-only -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='gpsjundi_bdgsfacil';"
echo "PASS import isolado"
