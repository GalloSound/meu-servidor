#!/usr/bin/env bash
# Varre as imagens fixadas. Sem trivy, apenas lista o inventario.
# Por padrao o exit code e 0: CVE de imagem upstream nao bloqueia o CI.
set -euo pipefail

images="
mariadb:11.4@sha256:70cc072b29b4a89ae07abb2d4da2c64678a7f2dfe092751bb51c87d67dc1338b
phpmyadmin:5.2@sha256:9e915766488a0f603183367a4b51f5db6309ea801f3eaa25138a83815772b14f
filebrowser/filebrowser:v2-s6@sha256:ee4ac79e52966a5f6247f99c7d667c1debfb277a3a61ab829f505aa8f4c74b21
php:8.2-apache@sha256:163407b1ceca31a3a17211e07ca80982438bad31280ba18093b185d93a762fd2
php:7.4-apache@sha256:c9d7e608f73832673479770d66aacc8100011ec751d1905ff63fae3fe2e0ca6d
composer:2@sha256:a5f59b9fd2faf31218632be4809dc6491761085e8064c31dc3b84378c48c248b
node:20-alpine@sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293
kopia/kopia:0.23.1@sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e
rclone/rclone:1.69@sha256:1f497a86a6466395e62a5886613a14b7b18809543566ef9fa35fa1371a7ecc0f
jc21/nginx-proxy-manager:2.15.1@sha256:52b2c59994f3d36acfcf70a1626f29734df0ed8c71bacc0269f78b6f939858bb
"

if ! command -v trivy >/dev/null 2>&1; then
  echo "trivy ausente. Imagens fixadas:"
  for image in $images; do
    echo "  ${image}"
  done
  exit 0
fi

status=0
for image in $images; do
  echo "trivy image ${image%%@*}"
  if ! trivy image --severity CRITICAL --ignore-unfixed --exit-code 0 --quiet "$image"; then
    status=1
  fi
done

if [[ "${SCAN_IMAGES_STRICT:-false}" == "true" && "$status" -ne 0 ]]; then
  exit "$status"
fi
exit 0
