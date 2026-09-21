# Rollback por stack

Cada stack volta sozinha. Volume de MariaDB, NPM, sessao PHP e repositorio Kopia ficam. Healthcheck pode ser revertido no compose sem tocar dado.

As imagens construidas aqui recebem uma tag de commit:

```bash
./scripts/tag-images.sh --dry-run
./scripts/tag-images.sh --apply
```

| Imagem local | Tag de commit |
|---|---|
| `meu-servidor/php-global:local` | `meu-servidor/php-global:sha-<commit da plataforma>` |
| `meu-servidor/apigsfacil:local` | `meu-servidor/apigsfacil:sha-<commit do submodulo>` |
| `meu-servidor/kopia-rclone:0.23.1` | `meu-servidor/kopia-rclone:sha-<commit da plataforma>` |

O script nao faz push. Guarde a tag anterior na maquina que fez o build, ou envie para um registry quando houver um. Sem a tag local antiga, o rollback de PHP/Node/Kopia exige rebuild do commit anterior.

## Infra (`mariadb_global`, `phpmyadmin_global`)

1. No compose, volte o digest da tabela anterior em `docs/image-inventory.md`.
2. `docker compose -f infra/compose.yaml --env-file infra/.env up -d`
3. Confirme `mariadb_global` healthy e o login do phpMyAdmin. O volume `infra/data` permanece.

Filebrowser so existe com `--profile admin-tools`. Parar o container ja e o rollback operacional.

## NPM

1. Volte o digest de `jc21/nginx-proxy-manager` e, se mudou, o de `npm_db`.
2. `docker compose -f infra/nginx-proxy-manager/compose.yaml --env-file infra/nginx-proxy-manager/.env up -d`
3. `depends_on` espera `npm_db` healthy. Os volumes `infra/nginx-proxy-manager/data` permanecem.

## PHP

```bash
PHP_IMAGE_TAG=sha-<commit-anterior> \
  docker compose -f php/compose.yaml --env-file php/.env up -d --no-build
```

`--no-build` usa a tag ja existente. O volume `php_sessions` permanece. Dependencias PHP nao rodam no startup: se o rollback precisar de `vendor/`, ele ja esta no diretorio montado.

## Node

```bash
NODE_IMAGE_TAG=sha-<commit-anterior> \
  docker compose -f node/apigsfacil/compose.yaml --env-file node/apigsfacil/.env up -d --no-build
```

A imagem antiga foi gerada com `npm ci --omit=dev` daquele lock. Nao rode `npm install` para "consertar" o rollback.

## Backup

```bash
docker tag meu-servidor/kopia-rclone:sha-<commit-anterior> meu-servidor/kopia-rclone:0.23.1
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env up -d --no-build
```

Os volumes `infra/backup/data` e o staging local permanecem. `BACKUP_STAGING_CLEANUP` continua `false` salvo mudanca explicita no `.env`.

## O que nao entra no rollback

- Nao apague `infra/data`, `infra/nginx-proxy-manager/data`, `infra/backup/data` nem `infra/backup/staging`.
- Nao rode `docker compose down -v`.
- Nao restaure SQL por cima de `mariadb_global` sem o drill em `docs/restore-drill.md`.
