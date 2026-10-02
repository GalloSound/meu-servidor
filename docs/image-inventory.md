# Inventario de imagens

Digests conferidos em 21/09/2026 com `docker buildx imagetools inspect`. O valor e o indice multi-arch, entao Mac (arm64) e VPS (amd64) usam o mesmo pin.

Para consultar de novo, sem alterar arquivos:

```bash
./scripts/refresh-image-inventory.sh
```

| Imagem | Tag | Digest | Onde |
|---|---|---|---|
| `mariadb` | `11.4` | `sha256:70cc072b29b4a89ae07abb2d4da2c64678a7f2dfe092751bb51c87d67dc1338b` | `infra/compose.yaml`, `infra/nginx-proxy-manager/compose.yaml` |
| `phpmyadmin` | `5.2` | `sha256:9e915766488a0f603183367a4b51f5db6309ea801f3eaa25138a83815772b14f` | `infra/compose.yaml` |
| `filebrowser/filebrowser` | `v2-s6` | `sha256:ee4ac79e52966a5f6247f99c7d667c1debfb277a3a61ab829f505aa8f4c74b21` | `infra/compose.yaml` |
| `php` | `8.2-apache` | `sha256:163407b1ceca31a3a17211e07ca80982438bad31280ba18093b185d93a762fd2` | `php/Dockerfile` (padrao) |
| `php` | `7.4-apache` | `sha256:c9d7e608f73832673479770d66aacc8100011ec751d1905ff63fae3fe2e0ca6d` | somente se `PHP_VERSION=7.4` |
| `composer` | `2` | `sha256:a5f59b9fd2faf31218632be4809dc6491761085e8064c31dc3b84378c48c248b` | `php/Dockerfile`, `php/scripts/install-composer-deps.sh` |
| `node` | `20-alpine` | `sha256:fb4cd12c85ee03686f6af5362a0b0d56d50c58a04632e6c0fb8363f609372293` | `node/apigsfacil/Dockerfile` |
| `kopia/kopia` | `0.23.1` | `sha256:89fd95ee2942880ca00eae964266958a394421ddbdf69bca62e38afc55f5900e` | `infra/backup/Dockerfile` |
| `rclone/rclone` | `1.69` | `sha256:1f497a86a6466395e62a5886613a14b7b18809543566ef9fa35fa1371a7ecc0f` | `infra/backup/Dockerfile` |
| `jc21/nginx-proxy-manager` | `2.15.1` | `sha256:52b2c59994f3d36acfcf70a1626f29734df0ed8c71bacc0269f78b6f939858bb` | `infra/nginx-proxy-manager/compose.yaml` |

## Como atualizar

1. Rode `./scripts/refresh-image-inventory.sh` e compare com esta tabela.
2. Troque o digest no compose ou Dockerfile e nesta tabela no mesmo cambio.
3. Se mudar `PHP_VERSION` para `7.4`, defina tambem `PHP_DIGEST` com a linha 7.4. O digest de 8.2 nao serve para a outra tag.
4. Reconstrua so a stack afetada (`--build` em PHP, Node e Kopia).
5. Marque a imagem local com `./scripts/tag-images.sh --apply`.
6. Nao apague volumes. O rollback esta em `docs/rollback-stacks.md`.

O CI varre estas referencias em `scripts/ci/scan-images.sh`. Achado CRITICAL de imagem upstream aparece no log e nao reprova o workflow. Falha do scanner bloqueia. Misconfig CRITICAL de Dockerfile reprova.

## CVE CRITICAL corrigivel em 02/10/2026

Trivy 0.74.0, nas referencias desta tabela, com `--severity CRITICAL --ignore-unfixed`. Cada linha e uma CVE unica. Pacotes repetidos na mesma imagem foram agrupados. Nenhuma tag foi solta e nenhum digest foi trocado.

Imagens sem CVE CRITICAL corrigivel: `filebrowser/filebrowser:v2-s6`, `php:8.2-apache`, `composer:2`.

| Imagem | CVE | Pacote instalado | Correcao informada pelo Trivy |
|---|---|---|---|
| `mariadb:11.4` | CVE-2025-68121 | `stdlib` v1.24.6 em `usr/local/bin/gosu` | 1.24.13, 1.25.7, 1.26.0-rc.3 |
| `phpmyadmin:5.2` | CVE-2026-24425 | `twig/twig` v3.11.3 | 3.0.0, 3.26.0 |
| `phpmyadmin:5.2` | CVE-2026-46633 | `twig/twig` v3.11.3 | 2.0.0, 3.0.0, 3.26.0 |
| `phpmyadmin:5.2` | CVE-2026-46634 | `twig/twig` v3.11.3 | 3.26.0 |
| `phpmyadmin:5.2` | CVE-2026-48805 | `twig/twig` v3.11.3 | 2.0.0, 3.0.0, 3.27.0 |
| `phpmyadmin:5.2` | CVE-2026-48806 | `twig/twig` v3.11.3 | 2.0.0, 3.0.0, 3.27.0 |
| `phpmyadmin:5.2` | CVE-2026-48807 | `twig/twig` v3.11.3 | 2.0.0, 3.0.0, 3.27.0 |
| `node:20-alpine` | CVE-2026-59873 | `tar` 6.2.1 | 7.5.19 |
| `kopia/kopia:0.23.1` | CVE-2026-33186 | `google.golang.org/grpc` v1.64.1 em `usr/bin/rclone` | 1.79.3 |
| `kopia/kopia:0.23.1` | CVE-2025-68121 | `stdlib` v1.23.3 em `usr/bin/rclone` | 1.24.13, 1.25.7, 1.26.0-rc.3 |
| `rclone/rclone:1.69` | CVE-2026-31789 | `libcrypto3` e `libssl3` 3.3.3-r0 | 3.3.7-r0 |
| `rclone/rclone:1.69` | CVE-2026-41176 | `github.com/rclone/rclone` v1.69.3+dirty | 1.73.5 |
| `rclone/rclone:1.69` | CVE-2026-41179 | `github.com/rclone/rclone` v1.69.3+dirty | 1.73.5 |
| `rclone/rclone:1.69` | CVE-2026-49980 | `github.com/rclone/rclone` v1.69.3+dirty | 1.74.3 |
| `rclone/rclone:1.69` | CVE-2026-88018 | `github.com/rclone/rclone` v1.69.3+dirty | 1.75.1 |
| `rclone/rclone:1.69` | CVE-2026-33186 | `google.golang.org/grpc` v1.67.1 | 1.79.3 |
| `rclone/rclone:1.69` | CVE-2025-68121 | `stdlib` v1.24.3 | 1.24.13, 1.25.7, 1.26.0-rc.3 |
| `jc21/nginx-proxy-manager:2.15.1` | CVE-2026-13221 | `perl`, `perl-base`, `perl-modules-5.40`, `libperl5.40` 5.40.1-6 | 5.40.1-6+deb13u1 |
| `jc21/nginx-proxy-manager:2.15.1` | CVE-2026-42496 | os mesmos pacotes Perl 5.40.1-6 | 5.40.1-6+deb13u1 |
| `jc21/nginx-proxy-manager:2.15.1` | CVE-2026-8376 | os mesmos pacotes Perl 5.40.1-6 | 5.40.1-6+deb13u1 |
| `jc21/nginx-proxy-manager:2.15.1` | CVE-2026-53215 | `linux-libc-dev` 6.12.90-2 | 6.12.94-1 |
| `jc21/nginx-proxy-manager:2.15.1` | CVE-2026-56123 | `socat` 1.8.0.3-1 | 1.8.0.3-1+deb13u1 |
| `jc21/nginx-proxy-manager:2.15.1` | CVE-2026-59873 | `tar` 7.5.11 e 7.5.15 | 7.5.19 |

`php:7.4-apache` so entra no build se `PHP_VERSION=7.4`. O scan mesmo assim achou 22 CVEs CRITICAL corrigiveis nessa referencia:

| CVE | Pacotes | Correcao informada pelo Trivy |
|---|---|---|
| CVE-2022-36760 | `apache2`, `apache2-bin`, `apache2-data`, `apache2-utils` 2.4.54-1~deb11u1 | 2.4.56-1~deb11u1 |
| CVE-2023-25690 | os mesmos pacotes Apache | 2.4.56-1~deb11u1 |
| CVE-2024-38474 | os mesmos pacotes Apache | 2.4.61-1~deb11u1 |
| CVE-2024-38475 | os mesmos pacotes Apache | 2.4.61-1~deb11u1 |
| CVE-2024-38476 | os mesmos pacotes Apache | 2.4.61-1~deb11u1 |
| CVE-2022-32221 | `curl`, `libcurl4` 7.74.0-1.3+deb11u3 | 7.74.0-1.3+deb11u5 |
| CVE-2023-38545 | `curl`, `libcurl4` 7.74.0-1.3+deb11u3 | 7.74.0-1.3+deb11u10 |
| CVE-2022-24963 | `libapr1` 1.7.0-6+deb11u1 | 1.7.0-6+deb11u2 |
| CVE-2024-45491 | `libexpat1` 2.2.10-2+deb11u5 | 2.2.10-2+deb11u6 |
| CVE-2024-45492 | `libexpat1` 2.2.10-2+deb11u5 | 2.2.10-2+deb11u6 |
| CVE-2025-14087 | `libglib2.0-0` 2.66.8-1 | 2.66.8-1+deb11u7 |
| CVE-2026-33845 | `libgnutls30` 3.7.1-5+deb11u2 | 3.7.1-5+deb11u10 |
| CVE-2026-42010 | `libgnutls30` 3.7.1-5+deb11u2 | 3.7.1-5+deb11u10 |
| CVE-2024-37371 | `libgssapi-krb5-2`, `libk5crypto3`, `libkrb5-3`, `libkrb5support0` 1.18.3-6+deb11u2 | 1.18.3-6+deb11u5 |
| CVE-2021-46848 | `libtasn1-6` 4.16.0-2 | 4.16.0-2+deb11u1 |
| CVE-2024-56171 | `libxml2` 2.9.10+dfsg-6.7+deb11u3 | 2.9.10+dfsg-6.7+deb11u6 |
| CVE-2023-25775 | `linux-libc-dev` 5.10.149-2 | 5.10.205-2 |
| CVE-2023-54257 | `linux-libc-dev` 5.10.149-2 | 5.10.178-1 |
| CVE-2024-47685 | `linux-libc-dev` 5.10.149-2 | 5.10.234-1 |
| CVE-2026-23112 | `linux-libc-dev` 5.10.149-2 | 5.10.257-1 |
| CVE-2026-43011 | `linux-libc-dev` 5.10.149-2 | 5.10.257-1 |
| CVE-2026-43037 | `linux-libc-dev` 5.10.149-2 | 5.10.257-1 |

Politica: misconfig CRITICAL continua bloqueante. Estas CVEs ficam inventariadas e o job de imagem nao falha por elas. Falha operacional do scanner de imagem bloqueia. `SCAN_IMAGES_STRICT=true` passa a detectar achado, porque o Trivy recebe codigo de saida 1, mas o workflow nao define essa variavel. So vale liga-la depois que um pin novo, escolhido a mao, zerar as CVE CRITICAL corrigiveis desta lista.
