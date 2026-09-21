# Secrets do Kopia

O Compose nao recebe `KOPIA_UI_PASSWORD` nem `KOPIA_REPOSITORY_PASSWORD` na linha de comando.

Gere os arquivos uma vez, a partir do `infra/backup/.env`:

```bash
./infra/backup/scripts/render-kopia-secrets.sh
```

Isso grava, com permissao `0600`:

- `kopia-repository-password`: uma linha com a senha do repositorio. O entrypoint exporta `KOPIA_PASSWORD` dentro do processo, sem argv.
- `kopia-ui.htpasswd`: hash da senha da UI. O servidor usa `--htpasswd-file`.

Esses dois arquivos nao entram no Git. Para trocar a senha, rode o script com `--force` e recrie somente `kopia_backup`.
