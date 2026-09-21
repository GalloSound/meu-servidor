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

O CI varre estas referencias em `scripts/ci/scan-images.sh`. Achado CRITICAL de imagem upstream aparece no log e nao reprova o workflow. Misconfig CRITICAL de Dockerfile reprova.
