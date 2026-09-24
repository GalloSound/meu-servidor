#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/restore-drill.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

src="${TMP}/run"
mkdir -p "${src}/sql" "${src}/configs/infra" "${src}/configs/nginx-proxy-manager" "${src}/full/php"
# shellcheck disable=SC2016
printf 'CREATE DATABASE gpsjundi_bdgsfacil;\nUSE `gpsjundi_bdgsfacil`;\nDump completed\n' > "${src}/sql/gpsjundi_bdgsfacil.sql"
printf 'services: {}\n' > "${src}/configs/infra/compose.yaml"
printf 'services: {}\n' > "${src}/configs/php-compose.yaml"
printf 'services: {}\n' > "${src}/configs/nginx-proxy-manager/compose.yaml"
printf '<?php echo "ok";\n' > "${src}/full/php/index.php"

out="$("$SCRIPT" --source "$src" --dry-run --require-app)"
printf '%s\n' "$out" | grep -q 'PASS sql' || fail "sql nao validado"
printf '%s\n' "$out" | grep -q 'PASS config configs/php-compose.yaml' || fail "config php ausente no plano"
printf '%s\n' "$out" | grep -q 'PASS aplicacao full/' || fail "aplicacao ausente no plano"
printf '%s\n' "$out" | grep -q 'mode=dry-run' || fail "nao ficou em dry-run"
[[ ! -d "${TMP}/dest" ]] || fail "dry-run criou destino"

dest="${TMP}/dest"
"$SCRIPT" --source "$src" --prepare-isolated "$dest" --require-app >/dev/null
[[ -s "${dest}/sql/gpsjundi_bdgsfacil.sql" ]] || fail "sql nao copiado"
[[ -s "${dest}/configs/php-compose.yaml" ]] || fail "config nao copiada"
[[ -s "${dest}/full/php/index.php" ]] || fail "aplicacao nao copiada"
[[ -s "${dest}/MANIFEST.txt" ]] || fail "manifesto ausente"
[[ -s "${src}/sql/gpsjundi_bdgsfacil.sql" ]] || fail "origem foi alterada"
if grep -q 'MANIFEST.txt' "${dest}/MANIFEST.txt"; then
  fail "manifesto inclui o proprio arquivo"
fi

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

listed=0
while IFS= read -r line; do
  case "$line" in
    source=*|aplicacao=*) continue ;;
  esac
  listed_hash="${line%%  *}"
  rel="${line#*  }"
  [[ -f "${dest}/${rel}" ]] || fail "arquivo do manifesto ausente: ${rel}"
  actual_hash="$(hash_file "${dest}/${rel}")"
  [[ "$actual_hash" == "$listed_hash" ]] || fail "hash divergente: ${rel}"
  listed=$((listed + 1))
done < "${dest}/MANIFEST.txt"
[[ "$listed" -ge 1 ]] || fail "manifesto sem arquivos"

while IFS= read -r file; do
  rel="${file#"${dest}/"}"
  grep -Fq "  ${rel}" "${dest}/MANIFEST.txt" || fail "arquivo fora do manifesto: ${rel}"
done <<EOF
$(find "$dest" -type f ! -path "${dest}/MANIFEST.txt" | sort)
EOF

rm -rf "${src}/full"
if "$SCRIPT" --source "$src" --dry-run --require-app >/dev/null 2>&1; then
  fail "restore sem aplicacao deveria falhar com --require-app"
fi

bad="${TMP}/empty"
mkdir -p "$bad"
if "$SCRIPT" --source "$bad" --dry-run >/dev/null 2>&1; then
  fail "origem invalida deveria falhar"
fi

protected="${TMP}/infra/data/destino"
mkdir -p "$(dirname "$protected")"
if "$SCRIPT" --source "$src" --prepare-isolated "$protected" >/dev/null 2>&1; then
  fail "destino protegido deveria ser recusado"
fi

stub="${TMP}/docker-stub.sh"
cat > "$stub" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$DOCKER_LOG"
case "$*" in
  *ping*) exit 1 ;;
esac
exit 0
EOF
chmod +x "$stub"
: > "${TMP}/docker.log"

import_dest="${TMP}/import-dest"
if DOCKER_BIN="$stub" DOCKER_LOG="${TMP}/docker.log" \
  RESTORE_DRILL_ATTEMPTS=1 RESTORE_DRILL_SLEEP=0 \
  "$SCRIPT" --source "$src" --import-isolated "$import_dest"; then
  fail "import sem banco pronto deveria falhar no stub"
fi
grep -q -- '--network none' "${TMP}/docker.log" || fail "import nao pediu network none"
grep -q -- '--tmpfs /var/lib/mysql' "${TMP}/docker.log" || fail "import nao pediu tmpfs"
if grep -q 'mariadb_global' "${TMP}/docker.log"; then
  fail "import apontou para o container de producao"
fi

echo "PASS restore-drill"
