# Nginx Proxy Manager (infra interna)

Stack dedicada do Nginx Proxy Manager para o ambiente `meu-servidor`.

## Objetivo

- Rodar o proxy reverso em container proprio.
- Manter o banco do NPM **somente interno** (sem exposicao de porta).
- Conectar o proxy na rede compartilhada `rede-banco-global` para rotear servicos internos.

## Subida local

1. Copie `.env.example` para `.env` e ajuste as senhas.
2. Suba a stack:

```bash
docker compose -f infra/nginx-proxy-manager/compose.yaml --env-file infra/nginx-proxy-manager/.env up -d
```

3. Acesse o painel:

- `http://localhost:8081` (porta default local no `.env.example`)

## Sobre seguranca do banco

- O servico `npm_db` nao possui `ports`.
- O banco so responde na rede interna `npm-internal`.
- Somente o container `nginx_proxy_manager` tem acesso direto ao `npm_db`.

## Sobre versao da imagem

- A imagem do NPM esta fixada em tag + digest (imutavel) para evitar mudancas inesperadas do `latest`.
- O banco do NPM usa `mariadb:11.4` (imagem oficial), na mesma linha da sua infra global.
- Quando quiser atualizar, revise a documentacao oficial e troque para a proxima release estavel suportada.

## Migracao para VPS (Hostgator)

- No VPS, ajuste no `.env` para usar portas publicas reais:
  - `NPM_HTTP_PORT=80`
  - `NPM_HTTPS_PORT=443`
  - `NPM_ADMIN_PORT=81` (ou restrinja por firewall/VPN)
- Mantenha `npm_db` sem `ports` para continuar sem exposicao externa.
