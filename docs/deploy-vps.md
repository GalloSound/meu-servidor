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

Evite expor publicamente:

- `3306` MariaDB
- `8080` phpMyAdmin
- `8082` runtime PHP
- `8083` Filebrowser
- `4000` API Node
- `81` painel do NPM, salvo se houver restricao por IP/VPN

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

```bash
cp infra/.env.example infra/.env
cp infra/nginx-proxy-manager/.env.example infra/nginx-proxy-manager/.env
cp infra/backup/.env.example infra/backup/.env
cp php/.env.example php/.env
cp node/apigsfacil/.env.example node/apigsfacil/.env
```

Edite os arquivos `.env` reais. Eles nao devem ir para o GitHub.

## 4. Variaveis importantes

### `infra/.env`

No VPS:

```env
MARIADB_ROOT_PASSWORD=<senha-forte>
MARIADB_DATABASE=banco_inicial
PHPMYADMIN_PORT=8080
FILEBROWSER_PORT=8083
DOCKER_NETWORK=rede-banco-global
FILEBROWSER_PUID=1000
FILEBROWSER_PGID=1000
```

Se nao for usar phpMyAdmin/Filebrowser em producao, considere remover esses servicos ou bloquear as portas por firewall.

### `infra/nginx-proxy-manager/.env`

No VPS:

```env
NPM_DB_ROOT_PASSWORD=<senha-forte>
NPM_DB_NAME=npm
NPM_DB_USER=npm
NPM_DB_PASSWORD=<senha-forte>
NPM_HTTP_PORT=80
NPM_HTTPS_PORT=443
NPM_ADMIN_PORT=81
```

Restrinja a porta `81` por firewall/VPN quando possivel.

### `php/.env`

Use o mesmo banco e senha da infra:

```env
DB_HOST=mariadb_global
DB_DATABASE=gpsjundi_bdgsfacil
DB_USER=root
DB_PASS=<mesma-senha-do-MARIADB_ROOT_PASSWORD>
```

Troque as URLs locais por URLs HTTPS reais:

```env
APP_BASE_URL_APP=https://seudominio.com.br/app/
APP_BASE_URL_APP_NF=https://seudominio.com.br/app_nf/
APP_BASE_URL=https://seudominio.com.br/app_sistema/
APP_BASE_URL_NEW=https://seudominio.com.br/gsfacilfront/public/
APP_BASE_URL_PEOPLECONTACTS=https://seudominio.com.br/peoplecontacts/
```

### `node/apigsfacil/.env`

Configure banco e tokens reais:

```env
DB_HOST=mariadb_global
DB_USER=root
DB_PASS=<mesma-senha-do-MARIADB_ROOT_PASSWORD>
DB_NAME=gpsjundi_bdgsfacil
```

Preencha tambem as chaves de API externas usadas pelo projeto.

### `infra/backup/.env`

Configure o backup:

```env
KOPIA_UI_USER=admin
KOPIA_UI_PASSWORD=<senha-forte>
KOPIA_REPOSITORY_PASSWORD=<senha-forte-e-diferente>
MARIADB_CONTAINER=mariadb_global
MARIADB_DATABASE=gpsjundi_bdgsfacil
NPM_DB_CONTAINER=npm_db
RCLONE_REMOTE_NAME=gdrive
RCLONE_REMOTE_PATH=Backups/meu-servidor
BACKUP_FULL_ENABLED=true
BACKUP_FULL_SOURCES=php,node,infra,docs,README.md
```

Para Google Drive pessoal, use Rclone OAuth e copie o arquivo em:

```text
infra/backup/rclone/rclone.conf
```

## 5. Ordem de subida

Suba a infra principal primeiro. Ela cria a rede Docker compartilhada:

```bash
docker compose -f infra/compose.yaml --env-file infra/.env up -d
```

Suba o Nginx Proxy Manager:

```bash
docker compose -f infra/nginx-proxy-manager/compose.yaml --env-file infra/nginx-proxy-manager/.env up -d
```

Suba o backup com Kopia:

```bash
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env up -d --build
```

Suba o runtime PHP:

```bash
docker compose -f php/compose.yaml --env-file php/.env up -d --build
```

Suba a API Node:

```bash
docker compose -f node/apigsfacil/compose.yaml --env-file node/apigsfacil/.env up -d --build
```

Inicialize o repositorio Kopia no Google Drive (uma unica vez):

```bash
./infra/backup/scripts/init-gdrive-repo.sh
```

Teste um snapshot manual:

```bash
./infra/backup/scripts/snapshot-now.sh
```

## 6. Nginx Proxy Manager

Acesse o painel:

```text
http://IP_DO_VPS:81
```

Credenciais iniciais padrao:

```text
Email: admin@example.com
Senha: changeme
```

Troque imediatamente no primeiro login.

Crie os Proxy Hosts apontando para os nomes dos containers na rede Docker:

```text
php_global:80
apigsfacil:4000
```

Ative SSL via Let's Encrypt para os dominios publicos.

## 7. Banco de dados

O MariaDB global nao deve ter `ports`.

Para importar dump no VPS, use `docker exec` ou copie o dump temporariamente para o servidor. Exemplo:

```bash
docker exec -i mariadb_global mariadb -uroot -p gpsjundi_bdgsfacil < backup.sql
```

Remova dumps do servidor apos importar.

## 8. Verificacoes

```bash
docker ps
docker network inspect rede-banco-global
docker logs nginx_proxy_manager --tail=100
docker logs mariadb_global --tail=100
```

Confirme:

- `mariadb_global`, `php_global`, `apigsfacil` e `nginx_proxy_manager` na rede `rede-banco-global`.
- Nenhuma porta de banco exposta no host.
- Dominio acessando via HTTPS.
- Painel NPM com senha trocada.
- Snapshot Kopia criado com sucesso.

## 9. Atualizacao

Atualize uma stack por vez:

```bash
docker compose -f infra/compose.yaml --env-file infra/.env pull
docker compose -f infra/compose.yaml --env-file infra/.env up -d
```

Para o NPM, revise antes a versao fixada em `infra/nginx-proxy-manager/compose.yaml`.

Para o backup, veja `docs/backup-kopia-gdrive.md`.
