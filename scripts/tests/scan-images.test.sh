#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/scripts/ci/scan-images.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expected=10
bash_bin="$(command -v bash)"

set +e
out="$(PATH="" "$bash_bin" "$SCRIPT" 2>&1)"
status=$?
set -e
[[ "$status" -eq 0 ]] || fail "sem trivy deveria sair 0, saiu ${status}"
printf '%s\n' "$out" | grep -q 'trivy ausente' || fail "aviso de trivy ausente"
printf '%s\n' "$out" | grep -q 'node:20-alpine@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293' \
  || fail "inventario sem a imagem pinada do Node"
lines="$(printf '%s\n' "$out" | grep -c '@sha256:' || true)"
[[ "$lines" -eq "$expected" ]] || fail "inventario esperava ${expected} imagens, veio ${lines}"

cat > "${TMP}/trivy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${TRIVY_ARGS_LOG}"
exit_code=0
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--exit-code" ]]; then
    exit_code="$arg"
  fi
  prev="$arg"
done
if [[ "${TRIVY_FORCE_EXIT:-}" != "" ]]; then
  exit "$TRIVY_FORCE_EXIT"
fi
if [[ "$exit_code" -ne 0 ]]; then
  echo "CRITICAL finding" >&2
  exit "$exit_code"
fi
exit 0
EOF
chmod +x "${TMP}/trivy"
log="${TMP}/trivy.log"

run_scan() {
  : > "$log"
  set +e
  out="$(TRIVY_ARGS_LOG="$log" PATH="${TMP}:${PATH}" "$@" bash "$SCRIPT" 2>&1)"
  status=$?
  set -e
}

run_scan
[[ "$status" -eq 0 ]] || fail "relatorio deveria sair 0, saiu ${status}"
calls="$(wc -l < "$log" | tr -d ' ')"
[[ "$calls" -eq "$expected" ]] || fail "relatorio esperava ${expected} chamadas, veio ${calls}"
grep -q -- '--exit-code 0' "$log" || fail "relatorio nao passou exit-code 0"
grep -q -- '--exit-code 1' "$log" && fail "relatorio passou exit-code 1"
grep -q '@sha256:' "$log" || fail "relatorio varreu tag sem digest"
printf '%s\n' "$out" | grep -q 'trivy image node:20-alpine' || fail "relatorio nao listou a imagem do Node"

run_scan env SCAN_IMAGES_STRICT=false
[[ "$status" -eq 0 ]] || fail "strict false deveria sair 0, saiu ${status}"
grep -q -- '--exit-code 0' "$log" || fail "strict false nao passou exit-code 0"

run_scan env SCAN_IMAGES_STRICT=true
[[ "$status" -eq 1 ]] || fail "strict true com achado deveria sair 1, saiu ${status}"
calls="$(wc -l < "$log" | tr -d ' ')"
[[ "$calls" -eq "$expected" ]] || fail "strict true deveria varrer todas as imagens, veio ${calls}"
grep -q -- '--exit-code 1' "$log" || fail "strict true nao passou exit-code 1"
grep -q -- '--exit-code 0' "$log" && fail "strict true ainda passou exit-code 0"
printf '%s\n' "$out" | grep -q 'CRITICAL finding' || fail "strict true engoliu o achado"

run_scan env SCAN_IMAGES_STRICT=true TRIVY_FORCE_EXIT=0
[[ "$status" -eq 0 ]] || fail "strict true sem achado deveria sair 0, saiu ${status}"
grep -q -- '--exit-code 1' "$log" || fail "strict true sem achado nao passou exit-code 1"

run_scan env TRIVY_FORCE_EXIT=2
[[ "$status" -ne 0 ]] || fail "erro operacional no modo padrao deveria falhar, saiu ${status}"
calls="$(wc -l < "$log" | tr -d ' ')"
[[ "$calls" -eq "$expected" ]] || fail "erro operacional deveria varrer todas as imagens, veio ${calls}"
grep -q -- '--exit-code 0' "$log" || fail "erro operacional no modo padrao nao passou exit-code 0"

# shellcheck disable=SC2016
if ! grep -q -- '--exit-code "$trivy_exit"' "$SCRIPT"; then
  fail "o script voltou a fixar o exit code do Trivy"
fi

echo "PASS scan-images"
