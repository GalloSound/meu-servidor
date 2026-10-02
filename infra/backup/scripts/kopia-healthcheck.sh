#!/bin/sh
# 200: UI aberta. 401: UI no ar exigindo senha. Outros codigos: processo ainda nao pronto.
# HTTP valido ainda exige repository status. A saida do Kopia e descartada.
set -eu

# Testes injetam um mock. No container o padrao e o entrypoint real.
entrypoint="${KOPIA_ENTRYPOINT:-/usr/local/bin/kopia-entrypoint}"

code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:51515/ || true)
case "$code" in
  200|401)
    ;;
  *)
    echo "kopia healthcheck HTTP ${code}" >&2
    exit 1
    ;;
esac

if ! "$entrypoint" repository status >/dev/null 2>&1; then
  echo "kopia healthcheck: repositorio indisponivel" >&2
  exit 1
fi
