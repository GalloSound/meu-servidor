# Backup stack (Kopia)

Stack de backup criptografado da plataforma.

## Arquivos

- `compose.yaml`: servico `kopia_backup`.
- `.env.example`: variaveis obrigatorias.
- `scripts/pre-backup.sh`: dump SQL obrigatorio, configs e clone completo opcional.
- `scripts/init-gdrive-repo.sh`: cria repositorio no Google Drive via Rclone.
- `scripts/snapshot-now.sh`: executa snapshot manual.

## Uso rapido

```bash
cp infra/backup/.env.example infra/backup/.env
mkdir -p infra/backup/rclone
# copie seu ~/.config/rclone/rclone.conf para infra/backup/rclone/rclone.conf
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env up -d
./infra/backup/scripts/init-gdrive-repo.sh
./infra/backup/scripts/snapshot-now.sh
```

Se quiser somente backup essencial (sem clone completo), ajuste:

```env
BACKUP_FULL_ENABLED=false
```

O dump do banco principal (`mariadb_global`) e obrigatorio: o script sobe o container se estiver parado, valida o `.sql` e aborta se falhar. O clone de arquivos e secundario (`BACKUP_FULL_FAIL_SOFT=true`).

## Documentacao completa

Veja `docs/backup-kopia-gdrive.md`.

> Na primeira execucao use `--build` para gerar a imagem local com Kopia + Rclone.
