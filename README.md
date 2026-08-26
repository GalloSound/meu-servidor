# meu-servidor-platform

Plataforma Docker compartilhada do ambiente `meu-servidor`. Os mesmos `compose.yaml` e `Dockerfile` sao usados no Docker Desktop do Mac e no Docker da VPS; somente os arquivos `.env` reais mudam.

## Stacks e projetos

- `infra/compose.yaml`: MariaDB global, phpMyAdmin, Filebrowser e rede compartilhada.
- `infra/nginx-proxy-manager/`: Nginx Proxy Manager e seu banco interno.
- `infra/backup/`: backup com Kopia.
- `php/compose.yaml` e `php/Dockerfile`: runtime Apache/PHP compartilhado.
- `node/apigsfacil/`: API Node em container proprio.
- `docs/`: deploy e operacao.

O repositorio da plataforma nao versiona o codigo das aplicacoes em `php/app*`, `php/gsfacilFront`, `php/googlecalendar`, `php/peoplecontacts` e `node/apigsfacil`; esses diretorios possuem repositorios independentes.

## Configuracao por ambiente

Cada stack possui exatamente um `.env.example`. Copie-o para `.env` no mesmo diretorio e edite apenas a copia:

```bash
cp infra/.env.example infra/.env
cp infra/nginx-proxy-manager/.env.example infra/nginx-proxy-manager/.env
cp infra/backup/.env.example infra/backup/.env
cp php/.env.example php/.env
cp node/apigsfacil/.env.example node/apigsfacil/.env
```

Nao crie `.env.dev`, `.env.prod` ou variantes do Compose. Os `.env` reais nunca devem ser versionados.

As diferencas permitidas entre Mac e VPS sao valores de ambiente: senhas/tokens, URLs, portas, bind HTTP/HTTPS do NPM, IDs de usuario/grupo e identificacao do ambiente. Imagens, Dockerfiles, mounts, servicos e redes permanecem iguais.

No Mac, o exemplo do NPM publica HTTP/HTTPS somente em `127.0.0.1`. Na VPS, altere `NPM_HTTP_BIND` e `NPM_HTTPS_BIND` para `0.0.0.0`; o painel administrativo continua sempre em `127.0.0.1`.

## Ordem de subida

```bash
docker compose -f infra/compose.yaml --env-file infra/.env up -d
docker compose -f infra/nginx-proxy-manager/compose.yaml --env-file infra/nginx-proxy-manager/.env up -d
docker compose -f php/compose.yaml --env-file php/.env up -d --build
docker compose -f node/apigsfacil/compose.yaml --env-file node/apigsfacil/.env up -d --build
docker compose -f infra/backup/compose.yaml --env-file infra/backup/.env up -d --build
```

A infra deve subir primeiro porque cria `rede-banco-global`. NPM, PHP, Node e backup dependem dela. Para detalhes de VPS, tunel SSH e troca de servidor, consulte `docs/deploy-vps.md`.

## Seguranca e versionamento

MariaDB nao publica porta no host. phpMyAdmin, Filebrowser, PHP e API Node usam `127.0.0.1`; o painel do NPM tambem fica restrito a localhost.

Antes de enviar alteracoes:

```bash
git status --ignored
```

Arquivos `.env`, dados persistentes, certificados, dumps, backups e codigos dos projetos independentes nao devem aparecer como arquivos versionaveis.
