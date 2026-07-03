# Backup seguro com Kopia + Google Drive

Guia de backup criptografado da plataforma `meu-servidor` usando Kopia.

## Visao geral

- Snapshot incremental e deduplicado com criptografia ponta a ponta.
- Backup de dados criticos (dumps SQL, `.env`, compose files e certificados).
- Destino remoto: Google Drive via repositorio `gdrive` do Kopia.

## 1. Preparar ambiente

```bash
cp infra/backup/.env.example infra/backup/.env
```

Ajuste os valores no `infra/backup/.env`:

- `KOPIA_UI_PASSWORD`
- `KOPIA_REPOSITORY_PASSWORD`
- `MARIADB_DATABASE`
- `GDRIVE_FOLDER_ID`

## 2. Credencial do Google Drive

1. Crie uma Service Account no Google Cloud.
2. Ative a Google Drive API.
3. Baixe o JSON da Service Account.
4. Compartilhe a pasta de destino do Google Drive com o e-mail da Service Account.
5. Salve o JSON em:

```text
infra/backup/credentials/gdrive-service-account.json
```

Esse arquivo nao deve ir para o GitHub.

## 3. Subir o Kopia

```bash
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env up -d
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

Esse comando cria o repositorio Kopia no folder do Google Drive definido em `GDRIVE_FOLDER_ID`.

## 5. Gerar snapshot manual

```bash
./infra/backup/scripts/snapshot-now.sh
```

O script faz:

1. Dump do banco principal (`mariadb_global`).
2. Dump do banco do NPM (`npm_db`) quando estiver ativo.
3. Copia de arquivos de configuracao essenciais.
4. Snapshot Kopia da pasta de staging.

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

## 9. Boas praticas de seguranca

- Nunca versionar:
  - `infra/backup/.env`
  - `infra/backup/credentials/`
  - `infra/backup/staging/`
  - `infra/backup/data/`
- Use senha forte no `KOPIA_REPOSITORY_PASSWORD`.
- Guarde a senha do repositorio em cofre seguro (sem ela nao ha restore).
- Restrinja o acesso ao painel Kopia (localhost, VPN ou firewall).
