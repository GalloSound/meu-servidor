# Deploy no VPS Hostgator

Guia de subida da plataforma Docker do `meu-servidor` em um VPS.

## 1. Pre-requisitos

- VPS Linux com acesso SSH.
- Docker instalado.
- Docker Compose plugin instalado (`docker compose version`).
- DNS dos dominios apontando para o IP publico do VPS.
- Portas `80` e `443` liberadas no firewall.

Recomendacao de firewall:

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

O Compose ja publica o que e sensivel em `127.0.0.1`. O firewall e a segunda camada. Nao abra estas portas no UFW:

- `3306` MariaDB global e banco do NPM (os containers nao tem `ports`)
- `8080` phpMyAdmin
- `8082` runtime PHP
- `8083` Filebrowser
- `4000` API Node
- `81` painel do NPM
- `51515` Kopia

Na VPS, so `22`, `80` e `443` ficam alcancaveis de fora. `80` e `443` sao o NPM (`NPM_HTTP_BIND` e `NPM_HTTPS_BIND` em `0.0.0.0`). O painel `81` continua preso a `127.0.0.1` pelo Compose.

## 2. Clonar repositorios

Clone este repo de plataforma:

```bash
git clone https://github.com/GalloSound/meu-servidor.git
cd meu-servidor
```

Clone os projetos de aplicacao nos caminhos esperados pelos compose files:

```bash
git clone <url-app> php/app
git clone <url-app-nf> php/app_nf
git clone <url-app-sistema> php/app_sistema
git clone <url-gsfacilfront> php/gsfacilFront
git clone <url-googlecalendar> php/googlecalendar
git clone <url-peoplecontacts> php/peoplecontacts
git clone <url-apigsfacil> node/apigsfacil
```

Use apenas os projetos que forem realmente necessarios no VPS.

## 3. Criar arquivos de ambiente

O workflow e o mesmo no Mac e na VPS: cada stack usa seu unico `.env.example` como modelo. Nao crie arquivos `.env.dev`, `.env.prod`, Compose alternativo ou Dockerfile especifico para servidor.

```bash
cp infra/.env.example infra/.env
cp infra/nginx-proxy-manager/.env.example infra/nginx-proxy-manager/.env
cp infra/backup/.env.example infra/backup/.env
cp php/.env.example php/.env
cp node/apigsfacil/.env.example node/apigsfacil/.env
```

Edite os arquivos `.env` reais. Eles nao devem ir para o GitHub.

Entre ambientes, altere somente valores: senhas/tokens, URLs, portas, binds do NPM, PUID/PGID e `APP_ENV`. A definicao dos servicos, imagens, volumes e redes permanece identica.

## 4. Variaveis importantes

### `infra/.env`

No VPS:

```env
MARIADB_ROOT_PASSWORD=<senha-forte>
MARIADB_DATABASE=gpsjundi_bdgsfacil
PHPMYADMIN_PORT=8080
FILEBROWSER_PORT=8083
DOCKER_NETWORK=rede-banco-global
DOCKER_PROXY_NETWORK=rede-proxy-global
FILEBROWSER_PUID=1000
FILEBROWSER_PGID=1000
```

Se nao for usar phpMyAdmin/Filebrowser em producao, nao suba o Filebrowser (omitir `--profile admin-tools`) e acesse phpMyAdmin so por tunel. O procedimento de usuarios DB e redes esta em `docs/hardening-privilegio-redes.md`.

### `infra/nginx-proxy-manager/.env`

No VPS, HTTP e HTTPS precisam aceitar trafego publico. O painel administrativo permanece fixo em `127.0.0.1` pelo Compose:

```env
NPM_DB_ROOT_PASSWORD=<senha-forte>
NPM_DB_NAME=npm
NPM_DB_USER=npm
NPM_DB_PASSWORD=<senha-forte>
NPM_HTTP_BIND=0.0.0.0
NPM_HTTPS_BIND=0.0.0.0
NPM_HTTP_PORT=80
NPM_HTTPS_PORT=443
NPM_ADMIN_PORT=81
DOCKER_PROXY_NETWORK=rede-proxy-global
```

No Mac, mantenha os binds `127.0.0.1` fornecidos pelo `.env.example`. Acesse a administracao da VPS por tunel SSH.

### `php/.env`

Use o mesmo banco e senha da infra:

```env
APP_ENV=production
PATH_SISTEMA=/var/www/html/app_sistema
DB_HOST=mariadb_global
DB_DATABASE=gpsjundi_bdgsfacil
DB_USER=app_php
DB_PASS=<senha-do-usuario-app_php>
API_SECRET_KEY=<chave-forte-para-as-APIs-PHP>
SESSION_LIFETIME=14400
SESSION_SAMESITE=Lax
TRUSTED_PROXY_CIDRS=172.16.0.0/12,10.0.0.0/8
```

`TRUSTED_PROXY_CIDRS` deve cobrir a rede Docker do Nginx Proxy Manager. Sem isso, `X-Forwarded-*` é ignorado.

Troque as URLs locais por URLs HTTPS reais:

```env
APP_BASE_URL_APP=https://seudominio.com.br/app/
APP_BASE_URL_APP_NF=https://seudominio.com.br/app_nf/
APP_BASE_URL=https://seudominio.com.br/app_sistema/
APP_BASE_URL_NEW=https://seudominio.com.br/gsfacilfront/public/
APP_BASE_URL_PEOPLECONTACTS=https://seudominio.com.br/peoplecontacts/
APP_BASE_URL_GALLOSOUNDSITE=https://gallosound.com.br/
BASE_DIR=/gsfacilfront/public
BASE_URL_IMAGES=/app_sistema/
BASE_APP=/app/
INTERNAL_API_URL=http://apigsfacil:4000
BASE_URL_API_CONTACTS=/gcar/
BASE_URL_API_PEOPLECONTACTS=/peoplecontacts/public_html/apicontacts/
```

As variaveis `GOOGLE_CALENDAR_CLIENT_ID`, `GOOGLE_CALENDAR_CLIENT_SECRET`, `GOOGLE_CALENDAR_REDIRECT_URI` e `GOOGLE_CALENDAR_TOKEN_PATH` sao opcionais e podem ficar vazias. Quando habilitar OAuth, use a URL HTTPS publica no redirect e um caminho persistente/acessivel pelo runtime para o token.

### `node/apigsfacil/.env`

Configure banco e tokens reais:

```env
DB_HOST=mariadb_global
DB_USER=app_node
DB_PASS=<senha-do-usuario-app_node>
DB_NAME=gpsjundi_bdgsfacil
```

Preencha tambem as chaves de API externas usadas pelo projeto. A API Node
valida o token de login enviado pelo PHP (`X-Session-Token`); nao precisa
de `INTERNAL_API_SECRET`.

### `infra/backup/.env`

Configure o backup:

```env
KOPIA_UI_USER=admin
KOPIA_UI_PASSWORD=<senha-forte>
KOPIA_REPOSITORY_PASSWORD=<senha-forte-e-diferente>
BACKUP_STAGING_KEEP=3
BACKUP_STAGING_CLEANUP=false
MARIADB_CONTAINER=mariadb_global
MARIADB_DATABASE=gpsjundi_bdgsfacil
NPM_DB_CONTAINER=npm_db
RCLONE_REMOTE_NAME=gdrive
RCLONE_REMOTE_PATH=Backups/meu-servidor
BACKUP_FULL_ENABLED=true
BACKUP_FULL_SOURCES=php,node,infra,docs,README.md
```

Antes de subir o Kopia, gere os arquivos de senha. O Compose nao coloca essas senhas na linha de comando:

```bash
./infra/backup/scripts/render-kopia-secrets.sh
```

Para Google Drive pessoal, use Rclone OAuth e copie o arquivo em:

```text
infra/backup/rclone/rclone.conf
```

## 5. Ordem de subida

Suba a infra principal primeiro. Ela cria a rede Docker do banco:

```bash
docker compose -f infra/compose.yaml --env-file infra/.env up -d
```

Crie a rede proxy (PHP/Node/NPM) se ainda nao existir:

```bash
docker network inspect rede-proxy-global >/dev/null 2>&1 \
  || docker network create --driver bridge rede-proxy-global
```

Suba o Nginx Proxy Manager:

```bash
docker compose -f infra/nginx-proxy-manager/compose.yaml --env-file infra/nginx-proxy-manager/.env up -d
```

Suba o runtime PHP:

```bash
docker compose -f php/compose.yaml --env-file php/.env up -d --build
```

Suba a API Node:

```bash
docker compose -f node/apigsfacil/compose.yaml --env-file node/apigsfacil/.env up -d --build
```

Suba o backup com Kopia (depois de `render-kopia-secrets.sh`):

```bash
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env up -d --build
```

Inicialize o repositorio Kopia no Google Drive (uma unica vez):

```bash
./infra/backup/scripts/init-gdrive-repo.sh
```

Teste um snapshot manual:

```bash
./infra/backup/scripts/snapshot-now.sh
```

## 6. Binds locais e tunel SSH

O mesmo Compose vale no Mac e na VPS. O que muda e o `.env`.

| Servico | VPS | Mac (`.env.example`) |
|---|---|---|
| HTTP/HTTPS do NPM | `0.0.0.0:80` e `0.0.0.0:443` | `127.0.0.1:8084` e `127.0.0.1:4443` |
| Painel do NPM | `127.0.0.1:81` | `127.0.0.1:8081` |
| phpMyAdmin | `127.0.0.1:8080` | `127.0.0.1:8080` |
| PHP | `127.0.0.1:8082` | `127.0.0.1:8082` |
| API Node | `127.0.0.1:4000` | `127.0.0.1:4000` |
| Kopia | `127.0.0.1:51515` | `127.0.0.1:51515` |
| Filebrowser | `127.0.0.1:8083`, so com `--profile admin-tools` | igual, e nao sobe no `up -d` |
| MariaDB e `npm_db` | sem porta no host | sem porta no host |

No Mac, `8080`, `8081`, `8082`, `4000` e `51515` costumam estar ocupadas pela stack local. O tunel abaixo usa portas locais diferentes e aponta para o localhost da VPS:

```bash
ssh -N \
  -L 18080:127.0.0.1:8080 \
  -L 18081:127.0.0.1:81 \
  -L 18082:127.0.0.1:8082 \
  -L 18083:127.0.0.1:8083 \
  -L 14000:127.0.0.1:4000 \
  -L 15151:127.0.0.1:51515 \
  usuario@IP_DO_VPS
```

Enquanto a sessao estiver aberta, use no Mac:

- phpMyAdmin: `http://127.0.0.1:18080`
- NPM Admin: `http://127.0.0.1:18081`
- PHP: `http://127.0.0.1:18082`
- Filebrowser: `http://127.0.0.1:18083` (somente se o perfil `admin-tools` estiver ligado na VPS)
- API Node: `http://127.0.0.1:14000`
- Kopia: `http://127.0.0.1:15151`

O primeiro numero de cada `-L` e a porta no Mac. O destino (`127.0.0.1:porta`) e o bind na VPS. Nao troque o destino para `0.0.0.0`.

## 7. Nginx Proxy Manager

Apos abrir o tunel, acesse o painel:

```text
http://127.0.0.1:18081
```

Credenciais iniciais padrao:

```text
Email: admin@example.com
Senha: changeme
```

Troque imediatamente no primeiro login.

Crie os Proxy Hosts apontando para os nomes dos containers na rede proxy:

```text
php_global:80
```

Não publique `apigsfacil:4000` na internet. O gsfacilFront chama a API Node
pela rede Docker (`INTERNAL_API_URL=http://apigsfacil:4000`). A Custom Location
pública `/api` só deve ser removida depois do checklist em
`docs/api-php-node-proxy.md`.

Ative SSL via Let's Encrypt para os dominios publicos.

## 8. Banco de dados

O MariaDB global nao deve ter `ports`.

Para importar dump no VPS, use `docker exec` ou copie o dump temporariamente para o servidor. Exemplo:

```bash
docker exec -i mariadb_global mariadb -uroot -p gpsjundi_bdgsfacil < backup.sql
```

Remova dumps do servidor apos importar.

## 9. Verificacoes

```bash
docker ps
docker network inspect rede-banco-global
docker network inspect rede-proxy-global
docker logs nginx_proxy_manager --tail=100
docker logs mariadb_global --tail=100
```

Confirme:

- `mariadb_global`, `php_global` e `apigsfacil` na rede `rede-banco-global`.
- `nginx_proxy_manager`, `php_global` e `apigsfacil` na rede `rede-proxy-global`.
- `nginx_proxy_manager` **fora** de `rede-banco-global`.
- Nenhuma porta de banco exposta no host.
- Dominio acessando via HTTPS.
- Painel NPM com senha trocada.
- Snapshot Kopia criado com sucesso.
- `docker inspect --format '{{.State.Health.Status}}' mariadb_global php_global apigsfacil nginx_proxy_manager` em `healthy` depois do recreate com estes compose. PHP, Node e Kopia precisam de `--build` para a imagem nova.

## 10. Atualizacao

Atualize uma stack por vez:

```bash
docker compose -f infra/compose.yaml --env-file infra/.env pull
docker compose -f infra/compose.yaml --env-file infra/.env up -d
```

Para o NPM, revise antes o digest em `docs/image-inventory.md`.

Para voltar uma stack, use `docs/rollback-stacks.md`. Para o backup, veja `docs/backup-kopia-gdrive.md`.

## 11. Troca de servidor

1. Instale Docker/Compose e clone a plataforma e os repositorios das aplicacoes nos mesmos caminhos.
2. Copie com seguranca os `.env` reais e dados persistentes; nao os envie pelo Git.
3. Restaure MariaDB, dados/certificados do NPM e o repositorio de backup conforme a estrategia adotada.
4. Revise URLs, segredos, PUID/PGID e confirme `NPM_HTTP_BIND=0.0.0.0` e `NPM_HTTPS_BIND=0.0.0.0`.
5. Suba as stacks na ordem deste guia e valide usando o IP novo antes de mudar o DNS.
6. Reduza o TTL, troque os registros DNS, valide HTTPS e mantenha o servidor antigo disponivel durante a janela de rollback.

Os arquivos Compose e Dockerfiles nao devem ser alterados na migracao. Somente os `.env` reais e dados persistentes acompanham o ambiente.
