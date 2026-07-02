# meu-servidor-platform

Repositorio da plataforma Docker compartilhada do ambiente `meu-servidor`.

Este repo versiona a infraestrutura que conecta os projetos PHP e Node, mas **nao versiona o codigo dos projetos de aplicacao**, pois eles continuam em repositorios independentes.

## O que este repo versiona

- `infra/compose.yaml`: MariaDB global, phpMyAdmin, Filebrowser e rede compartilhada.
- `infra/nginx-proxy-manager/compose.yaml`: Nginx Proxy Manager e banco interno do NPM.
- `php/compose.yaml`: runtime PHP/Apache compartilhado.
- `php/Dockerfile`: imagem PHP/Apache comum aos projetos PHP.
- `php/www/`: arquivos compartilhados da raiz do Apache.
- `docs/`: documentacao de deploy e operacao.

## O que nao deve ser versionado

- Arquivos `.env` reais.
- Dados persistentes do MariaDB.
- Dados e certificados do Nginx Proxy Manager.
- Banco/configuracao do Filebrowser.
- Dumps, backups e arquivos compactados.
- Codigo dos projetos em `php/app_*`, `php/gsfacilFront`, `php/googlecalendar`, `php/peoplecontacts` e `node/apigsfacil`.

## Estrutura

```text
meu-servidor/
├── infra/
│   ├── compose.yaml
│   ├── .env.example
│   ├── mariadb.cnf
│   └── nginx-proxy-manager/
│       ├── compose.yaml
│       ├── .env.example
│       └── README.md
├── php/
│   ├── compose.yaml
│   ├── Dockerfile
│   ├── .env.example
│   └── www/
└── docs/
    └── deploy-vps.md
```

## Uso local

Crie os arquivos `.env` a partir dos exemplos:

```bash
cp infra/.env.example infra/.env
cp infra/nginx-proxy-manager/.env.example infra/nginx-proxy-manager/.env
cp php/.env.example php/.env
```

Suba primeiro a infra, depois o NPM e depois os runtimes/projetos:

```bash
docker compose -f infra/compose.yaml --env-file infra/.env up -d
docker compose -f infra/nginx-proxy-manager/compose.yaml --env-file infra/nginx-proxy-manager/.env up -d
docker compose -f php/compose.yaml --env-file php/.env up -d
```

## Deploy no VPS

Veja `docs/deploy-vps.md`.

## GitHub

Antes de subir, confira:

```bash
git status --ignored
```

Arquivos `.env`, `data/`, dumps e projetos independentes nao devem aparecer como arquivos versionaveis.
