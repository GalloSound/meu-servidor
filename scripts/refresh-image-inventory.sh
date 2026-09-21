#!/usr/bin/env bash
# Mostra os digests atuais das imagens fixadas. Nao altera compose nem volumes.
set -euo pipefail

images="
mariadb:11.4
phpmyadmin:5.2
filebrowser/filebrowser:v2-s6
php:8.2-apache
php:7.4-apache
composer:2
node:20-alpine
kopia/kopia:0.23.1
rclone/rclone:1.69
jc21/nginx-proxy-manager:2.15.1
"

echo "# Inventario consultado em $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo
echo "| Imagem | Digest |"
echo "|---|---|"
for image in $images; do
  digest="$(docker buildx imagetools inspect "$image" --format '{{.Manifest.Digest}}')"
  # shellcheck disable=SC2016
  printf '| `%s` | `%s` |\n' "$image" "$digest"
done
echo
echo "Atualize docs/image-inventory.md e os compose/Dockerfiles no mesmo commit."
echo "Nao recrie volumes ao trocar o digest."
