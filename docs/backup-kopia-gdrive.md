# Backup seguro com Kopia + Google Drive (email pessoal)

Guia de backup criptografado da plataforma `meu-servidor` usando Kopia.

## Visao geral

- Snapshot incremental e deduplicado com criptografia ponta a ponta.
- Backup de dados criticos (dumps SQL, `.env`, compose files e certificados).
- Opcionalmente, clone completo de arquivos do projeto (`php`, `node`, `infra`, `docs`).
- Destino remoto: Google Drive via repositorio `rclone` do Kopia (OAuth de usuario).

## 1. Preparar ambiente

```bash
cp infra/backup/.env.example infra/backup/.env
```

Ajuste os valores no `infra/backup/.env`:

- `KOPIA_UI_PASSWORD`
- `KOPIA_REPOSITORY_PASSWORD`
- `MARIADB_DATABASE`
- `RCLONE_REMOTE_NAME`
- `RCLONE_REMOTE_PATH`
- `BACKUP_FULL_ENABLED`
- `BACKUP_FULL_SOURCES`
- `BACKUP_FULL_EXCLUDES`

## 2. Configurar Google Drive com Rclone (OAuth)

No seu Mac (host), instale o rclone se ainda nao tiver:

```bash
brew install rclone
```

Crie o remote OAuth:

```bash
rclone config
```

Sugestao:

- Name: `gdrive`
- Storage: `drive`
- Scope: `drive`
- Use auto config: `yes` (abre o browser no Mac)

Depois exporte o config para a stack:

```bash
mkdir -p infra/backup/rclone
cp ~/.config/rclone/rclone.conf infra/backup/rclone/rclone.conf
```

Esse arquivo nao deve ir para o GitHub.

## 3. Subir o Kopia

O compose usa `--insecure` para o painel em HTTP local (`127.0.0.1`). Em producao, restrinja o acesso (localhost, VPN ou firewall).

```bash
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env up -d --build
```

Painel web (acesso local):

```text
http://127.0.0.1:51515
```

Se precisar acessar remoto, use SSH tunnel:

```bash
ssh -L 51515:127.0.0.1:51515 usuario@seu-vps
```

## 4. Criar repositorio no Google Drive

```bash
./infra/backup/scripts/init-gdrive-repo.sh
```

Esse comando cria o repositorio Kopia via Rclone em:

```text
RCLONE_REMOTE_NAME:RCLONE_REMOTE_PATH
```

## 5. Gerar snapshot manual

```bash
./infra/backup/scripts/snapshot-now.sh
```

O script faz:

1. Dump do banco principal (`mariadb_global`).
2. Dump do banco do NPM (`npm_db`) quando estiver ativo.
3. Copia de arquivos de configuracao essenciais.
4. Clone completo de arquivos (quando `BACKUP_FULL_ENABLED=true`).
5. Snapshot Kopia da pasta de staging.

### Full backup (clone de arquivos)

Por padrao, o full backup inclui:

- `php`
- `node`
- `infra`
- `docs`
- `README.md`

Exclusoes padrao (sensatas para evitar lixo/cache/segredos):

- `.git/` e `.DS_Store`
- `infra/data/`
- `infra/filebrowser/database/`
- `infra/filebrowser/config/`
- `infra/nginx-proxy-manager/data/`
- `infra/backup/data/`, `infra/backup/staging/`, `infra/backup/rclone/`, `infra/backup/credentials/`
- `php/*/vendor/`
- `node/*/node_modules/`

Tudo isso pode ser ajustado no `.env`:

```env
BACKUP_FULL_ENABLED=true
BACKUP_FULL_TARGET_NAME=full
BACKUP_FULL_SOURCES=php,node,infra,docs,README.md
BACKUP_FULL_EXCLUDES=.git/,.DS_Store,infra/data/,infra/filebrowser/database/,infra/filebrowser/config/,infra/nginx-proxy-manager/data/,infra/backup/data/,infra/backup/staging/,infra/backup/rclone/,infra/backup/credentials/,php/*/vendor/,node/*/node_modules/
```

## 6. Politica de retencao (recomendado)

Exemplo para manter:

- 7 diarios
- 4 semanais
- 6 mensais

```bash
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env exec -T kopia_backup \
  kopia policy set /staging --keep-latest 7 --keep-weekly 4 --keep-monthly 6
```

## 7. Agendamento (cron no host)

Exemplo diario as 03:30:

```cron
30 3 * * * /Applications/Docker_Projetos/meu-servidor/infra/backup/scripts/snapshot-now.sh >> /Applications/Docker_Projetos/meu-servidor/infra/backup/backup-cron.log 2>&1
```

## 8. Restore (exemplo rapido)

Listar snapshots:

```bash
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env exec -T kopia_backup \
  kopia snapshot list
```

Restaurar um dump SQL para pasta local:

```bash
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env exec -T kopia_backup \
  kopia restore <snapshot-id>:/staging/<timestamp>/sql/gpsjundi_bdgsfacil.sql /staging/restore/
```

Restaurar clone completo de arquivos:

```bash
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env exec -T kopia_backup \
  kopia restore <snapshot-id>:/staging/<timestamp>/full /staging/restore-full/
```

## 9. Boas praticas de seguranca

- Nunca versionar:
  - `infra/backup/.env`
  - `infra/backup/rclone/`
  - `infra/backup/staging/`
  - `infra/backup/data/`
- Use senha forte no `KOPIA_REPOSITORY_PASSWORD`.
- Guarde a senha do repositorio em cofre seguro (sem ela nao ha restore).
- Restrinja o acesso ao painel Kopia (localhost, VPN ou firewall).
