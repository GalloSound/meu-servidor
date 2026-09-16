# Plano 5 — Privilegio minimo e redes Docker

Arquitetura vigente (redes, usuarios, portas): `README.md` e `.cursor/rules/infra-docker-multiprojetos.mdc`.

Este arquivo e o **playbook operacional** (dump, SQL, corte de rede, rollback). Nao execute GRANT/REVOKE em producao sem dump validado. Nao altere volumes. Nao coloque senhas reais aqui.

## Mapa atual vs alvo

| Servico | Rede hoje | Rede alvo | Usuario DB hoje | Usuario alvo |
|---|---|---|---|---|
| `mariadb_global` | `rede-banco-global` | `rede-banco-global` (DB) | root (admin) | root so para dump/emergencia |
| `phpmyadmin_global` | `rede-banco-global` | `rede-banco-global` | login humano como root | `pma_admin` |
| `php_global` | `rede-banco-global` | DB + `rede-proxy-global` | `root` | `app_php` |
| `apigsfacil` | `rede-banco-global` | DB + `rede-proxy-global` | `root` | `app_node` |
| `nginx_proxy_manager` | `npm-internal` + DB | `npm-internal` + proxy | `npm` em `npm_db` | sem mudanca |
| `npm_db` | `npm-internal` | `npm-internal` | `npm` | sem mudanca |
| `filebrowser_global` | `infra_default` | sem rede de app | — | perfil `admin-tools`, mounts RO |
| `kopia_backup` | `backup_default` | sem mudanca | dump via `docker exec` root | sem usuario de rede |

PHP e Node compartilham o mesmo schema `gpsjundi_bdgsfacil` (cerca de 130 tabelas). O runtime PHP e um container so; nao da para separar usuario por projeto PHP sem quebrar o compose atual. `banco_inicial` e residual: nenhum app deve receber grant nele.

## O que ja esta no Git vs o que so voce faz

Ja preparado neste repositorio (sem aplicar no banco e sem recriar containers):

- `infra/sql/001_app_users.sql`, `002_verify_grants.sql`, `003_rollback_app_users.sql`
- Redes `rede-banco-global` (DB) e `rede-proxy-global` (proxy) nos compose
- Filebrowser fora do `up -d` padrao (`profiles: [admin-tools]`), mounts somente leitura
- `no-new-privileges`, `cap_drop` e `user: node` onde e compativel
- `.env.example` sem `DB_USER=root`

Voce executa: dump, SQL, edicao dos `.env` reais, recrie de stacks na ordem abaixo, testes e rollback se preciso.

---

## Fase 0 — Duas sessoes SSH (VPS)

Na VPS, abra **duas** sessoes SSH **antes** de mexer no NPM. Nao feche nenhuma ate o smoke test HTTPS passar.

- Sessao A: comandos (`docker compose`, `network connect/disconnect`).
- Sessao B: emergencia. Se o proxy cair, use esta sessao para rollback de rede.

No Mac isso e opcional (o NPM nao e a porta de SSH). Mesmo assim faca o recorte do NPM por ultimo.

---

## Fase 1 — Dump e prova de restauracao

Nao siga adiante sem um dump que voce consiga ler de volta.

```bash
mkdir -p /tmp/hardening-db
chmod 700 /tmp/hardening-db

docker exec mariadb_global sh -c 'mariadb-dump -uroot -p"$MARIADB_ROOT_PASSWORD" --single-transaction --routines --events --databases gpsjundi_bdgsfacil' \
  > /tmp/hardening-db/gpsjundi_bdgsfacil.sql

# Prova de leitura (nao restaura em cima do volume real):
head -n 20 /tmp/hardening-db/gpsjundi_bdgsfacil.sql
grep -E '^(CREATE DATABASE|USE `|Dump completed)' /tmp/hardening-db/gpsjundi_bdgsfacil.sql

# Prova de restauracao em schema temporario (nao mexe no schema de producao):
docker exec -i mariadb_global sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"' <<'SQL'
CREATE DATABASE IF NOT EXISTS gpsjundi_restore_test;
SQL

docker exec -i mariadb_global sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" gpsjundi_restore_test' \
  < /tmp/hardening-db/gpsjundi_bdgsfacil.sql

docker exec mariadb_global sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SHOW TABLES FROM gpsjundi_restore_test;" | wc -l'

docker exec mariadb_global sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "DROP DATABASE gpsjundi_restore_test;"'
```

Se o dump vier com `CREATE DATABASE`/`USE gpsjundi_bdgsfacil`, a restauracao de teste pode recusar ou escrever no banco real. Nesse caso restaure so a prova com:

```bash
sed -E 's/^CREATE DATABASE.*/-- &/; s/^USE `gpsjundi_bdgsfacil`/USE `gpsjundi_restore_test`/' \
  /tmp/hardening-db/gpsjundi_bdgsfacil.sql \
  > /tmp/hardening-db/restore-test.sql
```

e importe `restore-test.sql` em `gpsjundi_restore_test`. Depois apague o schema de teste. Nao deixe dumps no servidor.

---

## Fase 2 — Mapear schemas (ja conferido neste ambiente)

| App | Schema | Precisa de DDL em runtime? |
|---|---|---|
| PHP (`php_global`: gsfacilFront, app_sistema, app, app_nf, calendar, contacts) | `gpsjundi_bdgsfacil` | Nao. ALTER de migracao e manual (phpMyAdmin/root). |
| Node `apigsfacil` | `gpsjundi_bdgsfacil` | Nao. So DML. |
| phpMyAdmin | mesmo schema, visao admin | `ALL` so nesse schema |
| NPM | banco `npm` no `npm_db` | ja isolado |
| Kopia | dump via socket do container | continua `root` local |

Se no futuro o PHP precisar de `CREATE TABLE` em producao, aumente o grant do `app_php` com `CREATE, ALTER, INDEX` — nao volte para `root`.

---

## Fase 3 — Gerar senhas e aplicar SQL (manual)

No Mac ou na VPS, em diretorio privado fora do Git:

```bash
openssl rand -base64 32
openssl rand -base64 32
openssl rand -base64 32
```

```bash
cp infra/sql/001_app_users.sql /tmp/hardening-db/001_app_users.filled.sql
chmod 600 /tmp/hardening-db/001_app_users.filled.sql
# substitua __APP_PHP_DB_PASSWORD__, __APP_NODE_DB_PASSWORD__, __PMA_ADMIN_DB_PASSWORD__
```

```bash
docker exec -i mariadb_global sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"' \
  < /tmp/hardening-db/001_app_users.filled.sql

docker exec -i mariadb_global sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"' \
  < infra/sql/002_verify_grants.sql
```

Testes **antes** de trocar os `.env` das apps (root ainda conecta; os novos usuarios ja existem):

```bash
# app_php fala no schema do app e nao administra o resto
docker exec -e MYSQL_PWD='SENHA_APP_PHP' mariadb_global \
  mariadb -uapp_php -e "SELECT COUNT(*) FROM gpsjundi_bdgsfacil.gs_Administrador;"

docker exec -e MYSQL_PWD='SENHA_APP_PHP' mariadb_global \
  mariadb -uapp_php -e "CREATE DATABASE deve_falhar;"   # deve falhar

docker exec -e MYSQL_PWD='SENHA_APP_PHP' mariadb_global \
  mariadb -uapp_php -e "SELECT user FROM mysql.user;"    # deve falhar

docker exec -e MYSQL_PWD='SENHA_APP_NODE' mariadb_global \
  mariadb -uapp_node -e "SELECT 1 FROM gpsjundi_bdgsfacil.gs_Administrador LIMIT 1;"
```

`root` permanece ativo nesta janela. Nao revogue `root@%` agora.

---

## Fase 4 — Validar compose **antes** de subir

Nos `.env` reais, acrescente so a rede nova (ainda **nao** troque `DB_USER`):

```env
DOCKER_PROXY_NETWORK=rede-proxy-global
```

em `infra/.env`, `php/.env`, `node/apigsfacil/.env` e `infra/nginx-proxy-manager/.env`.

No Node, `DB_HOST` dentro do container tem de ser `mariadb_global`. `localhost` so vale se a API rodar no host, fora do Docker.

```bash
docker compose -f infra/compose.yaml --env-file infra/.env config >/dev/null
docker compose -f php/compose.yaml --env-file php/.env config >/dev/null
docker compose -f node/apigsfacil/compose.yaml --env-file node/apigsfacil/.env config >/dev/null
docker compose -f infra/nginx-proxy-manager/compose.yaml --env-file infra/nginx-proxy-manager/.env config >/dev/null
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env config >/dev/null
```

---

## Fase 5 — Redes, sem derrubar o NPM de primeira

Ordem obrigatoria. O NPM so perde a rede DB **depois** de ja resolver PHP/Node na rede proxy.

### 5.1 Criar a rede proxy (MariaDB nao muda de volume)

```bash
docker network inspect rede-proxy-global >/dev/null 2>&1 \
  || docker network create --driver bridge rede-proxy-global

docker compose -f infra/compose.yaml --env-file infra/.env up -d
```

`filebrowser_global` sai do `up -d` padrao (perfil `admin-tools`). Em producao, deixe assim. No Mac, so se ainda precisar:

```bash
docker compose -f infra/compose.yaml --env-file infra/.env --profile admin-tools up -d
```

### 5.2 PHP e Node entram na proxy **sem sair** da DB

```bash
docker compose -f php/compose.yaml --env-file php/.env up -d
docker compose -f node/apigsfacil/compose.yaml --env-file node/apigsfacil/.env up -d
```

Isso recria PHP/Node (alguns segundos). Confira:

```bash
docker exec php_global getent hosts mariadb_global
docker exec php_global getent hosts apigsfacil
docker exec apigsfacil getent hosts mariadb_global
docker exec php_global getent hosts nginx_proxy_manager || true
```

Nesta etapa o NPM ainda esta na rede DB, entao o site publico continua.

### 5.3 Cortar o NPM da DB **sem recreate** (janela curta)

```bash
docker network connect rede-proxy-global nginx_proxy_manager
docker exec nginx_proxy_manager getent hosts php_global
docker exec nginx_proxy_manager getent hosts apigsfacil

# so depois dos dois getent acima:
docker network disconnect rede-banco-global nginx_proxy_manager
```

Teste imediato (NPM **nao** deve alcancar o banco principal):

```bash
docker exec nginx_proxy_manager getent hosts mariadb_global
# esperado: falha / sem linha

docker exec nginx_proxy_manager sh -c 'nc -z -w 3 mariadb_global 3306' || echo "ok: npm nao conecta em :3306"
```

Se `getent hosts php_global` falhar, rollback imediato (sessao B):

```bash
docker network connect rede-banco-global nginx_proxy_manager
```

### 5.4 Persistir o compose do NPM

```bash
docker compose -f infra/nginx-proxy-manager/compose.yaml --env-file infra/nginx-proxy-manager/.env up -d
```

Pode recriar o proxy por alguns segundos. Sessao SSH B continua aberta. Smoke: HTTPS do dominio, painel `127.0.0.1:81` (VPS) ou `127.0.0.1:8081` (Mac).

---

## Fase 6 — Trocar `DB_USER=root` nas apps

So depois do SQL e das redes.

Em `php/.env`:

```env
DB_USER=app_php
DB_PASS=<senha gerada do app_php>
```

Em `node/apigsfacil/.env`:

```env
DB_USER=app_node
DB_PASS=<senha gerada do app_node>
DB_NAME=gpsjundi_bdgsfacil
```

Nao coloque a senha do root nesses arquivos. Recrie so PHP e Node:

```bash
docker compose -f php/compose.yaml --env-file php/.env up -d
docker compose -f node/apigsfacil/compose.yaml --env-file node/apigsfacil/.env up -d --build
```

O `--build` do Node e necessario se o Dockerfile passou a usar `USER node`.

phpMyAdmin: no proximo login use `pma_admin`, nao `root`. `root` fica na gaveta.

---

## Fase 7 — Testes depois

```bash
# 1) Portas: nada sensivel em 0.0.0.0
docker inspect php_global apigsfacil phpmyadmin_global filebrowser_global kopia_backup nginx_proxy_manager \
  --format '{{.Name}} {{json .HostConfig.PortBindings}}'
docker inspect mariadb_global npm_db --format '{{.Name}} ports={{json .HostConfig.PortBindings}}'
# esperado: MariaDB/npm_db sem PortBindings; 8080/8082/8083/4000/51515/81 em 127.0.0.1
# VPS: HTTP/HTTPS do NPM em 0.0.0.0:80/443. Mac: 127.0.0.1

# 2) NPM resolve PHP/Node e nao o MariaDB global
docker exec nginx_proxy_manager getent hosts php_global
docker exec nginx_proxy_manager getent hosts apigsfacil
docker exec nginx_proxy_manager getent hosts mariadb_global   # deve falhar

# 3) PHP/Node falam com o banco e entre si
docker exec php_global getent hosts mariadb_global
docker exec php_global getent hosts apigsfacil
docker exec apigsfacil getent hosts mariadb_global

# 4) Grants
docker exec php_global php -r 'try { new PDO("mysql:host=".getenv("DB_HOST").";dbname=".getenv("DB_DATABASE"), getenv("DB_USER"), getenv("DB_PASS")); echo "php-ok\n"; } catch (Throwable $e) { fwrite(STDERR, $e->getMessage()."\n"); exit(1);} '
docker logs apigsfacil --tail=30
docker exec php_global php /var/www/html/shared/auth/tests/run.php
docker exec php_global php /var/www/html/shared/api-guard/tests/run.php
```

Smoke funcional:

- Login `gsfacilFront` e sessao em `app_sistema`
- Uma chamada `/internal/api` que va ao Node
- phpMyAdmin com `pma_admin` (nao criar usuario, nao ver `mysql.user`)
- Confirmar que Filebrowser nao esta rodando na VPS, ou que `/srv` nao monta o repositorio inteiro gravavel

Quando o smoke passar, a janela de `root` nas apps acabou. Nao dropa `root`; so deixa de usa-lo nos `.env`.

---

## Filebrowser

Producao: nao passe `--profile admin-tools`. O servico nao sobe.

Mac (opcional): perfil `admin-tools`. Monta `php/` e `docs/` em somente leitura. Nao monta `infra/data`, `.env` nem o repo inteiro.

---

## cap_drop / no-new-privileges / user

| Servico | Aplicado | Motivo se incompleto |
|---|---|---|
| `apigsfacil` | `user: node`, `cap_drop: ALL`, `no-new-privileges` | imagem Node oficial tem usuario `node` |
| `mariadb_global` / `npm_db` | `cap_drop: ALL` + caps de init, `no-new-privileges` | usuario `mysql` ja e o padrao da imagem |
| `php_global` | `no-new-privileges`, `cap_drop: ALL` + caps do Apache | Apache precisa de root no master para bind `:80` e depois dropa para `www-data` |
| `phpmyadmin_global` | igual ao PHP | Apache da imagem oficial |
| `nginx_proxy_manager` | so `no-new-privileges` | imagem jc21 nao e estavel com `cap_drop: ALL` / user custom |
| `filebrowser` | `no-new-privileges` | s6 precisa de root para aplicar PUID/PGID |
| `kopia_backup` | `no-new-privileges` | volumes de config ja existentes |

---

## Rollback

| Falha | Acao |
|---|---|
| NPM perde `php_global` | `docker network connect rede-banco-global nginx_proxy_manager` na sessao B. Depois reverta o compose do NPM para incluir `rede-banco-global`. |
| Login/API com `app_php`/`app_node` | `DB_USER=root` e senha antiga nos `.env`, `up -d` PHP e Node. Usuarios novos podem ficar. |
| Abortar usuarios novos | so depois das apps de volta em root: `infra/sql/003_rollback_app_users.sql` |
| Filebrowser sumiu no Mac | `--profile admin-tools up -d` |
| Apache/PHP nao sobe com cap_drop | remova `cap_drop`/`cap_add` daquele servico, `up -d`, deixe `no-new-privileges` |

Nao restaure volume `infra/data` por causa desta mudanca. Nao rode `DROP USER 'root'`.

---

## Ordem exata (resumo)

1. Duas SSH na VPS.
2. Dump + restauracao em schema de teste.
3. Copiar SQL, preencher senhas, aplicar `001`, conferir `002`. Testes negativos dos novos usuarios.
4. `DOCKER_PROXY_NETWORK` nos `.env`. `compose config`.
5. `docker network create rede-proxy-global` (se ainda nao existir). `infra up -d` (Filebrowser some no padrao).
6. PHP e Node `up -d` (passam a ter as duas redes).
7. `network connect` proxy no NPM; `getent php_global`; `network disconnect` DB do NPM.
8. `compose up -d` do NPM.
9. Trocar `DB_USER`/`DB_PASS` PHP e Node; `up -d` (Node com `--build`).
10. Testes de porta, DNS, grants e smoke. Manter `root` so para dump/Kopia/emergencia.
