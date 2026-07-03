# Backup stack (Kopia)

Stack de backup criptografado da plataforma.

## Arquivos

- `compose.yaml`: servico `kopia_backup`.
- `.env.example`: variaveis obrigatorias.
- `scripts/pre-backup.sh`: gera dumps e pacote de configuracoes.
- `scripts/init-gdrive-repo.sh`: cria repositorio no Google Drive.
- `scripts/snapshot-now.sh`: executa snapshot manual.

## Uso rapido

```bash
cp infra/backup/.env.example infra/backup/.env
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env up -d
./infra/backup/scripts/init-gdrive-repo.sh
./infra/backup/scripts/snapshot-now.sh
```

## Documentacao completa

Veja `docs/backup-kopia-gdrive.md`.
