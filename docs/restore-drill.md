# Restore drill (configs + SQL + aplicacao)

O drill recupera um snapshot para um diretorio isolado e, se for o caso, importa o SQL num MariaDB temporario. Nao escreve em `mariadb_global`, `npm_db` nem nos diretorios de producao.

O script `infra/backup/scripts/restore-drill.sh` valida a arvore e, no modo dry-run, nao copia nada. Os testes em `infra/backup/scripts/tests/restore-drill.test.sh` cobrem esse plano com um fixture. O import real de um dump de producao continua um passo manual, no container temporario abaixo.

## 1. Escolher o snapshot

```bash
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env exec -T kopia_backup \
  /usr/local/bin/kopia-entrypoint snapshot list
```

O entrypoint le a senha do arquivo em `/run/secrets`. Nao passe `--password` nem cole a senha no comando.

Restaure para um diretorio novo, fora de `infra/data` e fora do volume do NPM:

```bash
mkdir -p /tmp/meu-servidor-restore
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env exec -T kopia_backup \
  /usr/local/bin/kopia-entrypoint restore <root-id> /staging/restore-drill-manual
```

Se o snapshot ja esta numa pasta `infra/backup/staging/<timestamp>/`, use essa pasta como `--source`. Nao apague as outras execucoes durante o drill.

## 2. Validar sem copiar

```bash
./infra/backup/scripts/restore-drill.sh \
  --source infra/backup/staging/<timestamp> \
  --dry-run \
  --require-app
```

Saida esperada:

- `PASS sql` com tamanho e SHA-256
- `PASS config` para `configs/infra/compose.yaml`, `configs/php-compose.yaml` e `configs/nginx-proxy-manager/compose.yaml`
- `PASS aplicacao full/`

Sem `--require-app`, um snapshot so de SQL e configs termina com `aplicacao AUSENTE` e exit 0. O drill completo pede `--require-app`.

## 3. Copiar para um diretorio vazio

```bash
./infra/backup/scripts/restore-drill.sh \
  --source infra/backup/staging/<timestamp> \
  --prepare-isolated /tmp/meu-servidor-restore \
  --require-app
```

O destino precisa estar vazio. O script recusa caminhos debaixo de `infra/data`, `infra/nginx-proxy-manager/data` e `infra/backup/data`. A origem permanece. `MANIFEST.txt` lista o SHA-256 de cada arquivo copiado e nao inclui o proprio manifesto.

Confira, ainda em `/tmp`:

- `sql/gpsjundi_bdgsfacil.sql` abre com `CREATE DATABASE` / `USE` e termina com `Dump completed`
- `configs/*.env.*` existem so nesse diretorio; nao copie por cima dos `.env` vivos
- `full/php` e `full/node` batem com o que o snapshot declara

## 4. Importar o SQL num MariaDB descartavel

Use senha exclusiva deste container. Ele nao entra na rede e o datadir e tmpfs.

```bash
docker run --rm -d \
  --name mariadb_restore_drill \
  --network none \
  --tmpfs /var/lib/mysql \
  -v "$PWD/infra/mariadb.cnf:/etc/mysql/conf.d/custom.cnf:ro" \
  -e MARIADB_ROOT_PASSWORD=restore-drill-only \
  -e MARIADB_DATABASE=gpsjundi_bdgsfacil \
  mariadb:11.4@sha256:70cc072b29b4a89ae07abb2d4da2c64678a7f2dfe092751bb51c87d67dc1338b

docker exec mariadb_restore_drill \
  mariadb-admin ping -uroot -prestore-drill-only --silent

docker exec -i mariadb_restore_drill \
  mariadb -uroot -prestore-drill-only \
  < /tmp/meu-servidor-restore/sql/gpsjundi_bdgsfacil.sql
```

`infra/mariadb.cnf` precisa estar montado antes da primeira inicializacao (`lower_case_table_names=1`).

Depois confira:

```bash
docker exec mariadb_restore_drill \
  mariadb -uroot -prestore-drill-only -e "SELECT @@lower_case_table_names;"

docker exec mariadb_restore_drill \
  mariadb -uroot -prestore-drill-only -N -e \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='gpsjundi_bdgsfacil';"

docker exec mariadb_restore_drill \
  mariadb-check -uroot -prestore-drill-only --databases gpsjundi_bdgsfacil --check --silent
```

Em 21/09/2026 este import, feito com o dump de producao, ficou em 130 tabelas e `mariadb-check` sem erros. O arquivo restaurado do Kopia tinha 51.486.415 bytes e o mesmo SHA-256 do dump de origem.

Encerre so o container do drill:

```bash
docker rm -f mariadb_restore_drill
```

Nao use `docker rm` em `mariadb_global`.

## 5. Aplicacao e configs

A aplicacao restaurada fica em `/tmp/meu-servidor-restore/full`. Compare com o checkout. Nao substitua `php/` nem `node/` da VPS por esse diretorio no meio do expediente.

As configs restauradas servem para reconstruir `.env` num servidor novo. Diff contra uma copia, nunca contra o arquivo que o container esta usando.

O comando `--import-isolated` do script repete o container temporario para um fixture. O teste automatico usa um Docker falso e confere `--network none` e `--tmpfs /var/lib/mysql`. Ele nao sobe o MariaDB de producao.
