#!/bin/sh
# 200: UI aberta. 401: UI no ar exigindo senha. Outros codigos: processo ainda nao pronto.
set -eu

code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:51515/ || true)
case "$code" in
  200|401)
    exit 0
    ;;
  *)
    echo "kopia healthcheck HTTP ${code}" >&2
    exit 1
    ;;
esac
