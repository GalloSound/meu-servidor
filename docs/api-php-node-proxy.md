# Autenticação PHP → apigsfacil

Arquitetura alvo:

```text
Browser (sessão + CSRF)
    → POST /gsfacilfront/public/internal/api/{acao}
    → NodeProxyController (ApiSessionGuard)
    → rede Docker
    → http://apigsfacil:4000/api/*
       HMAC (INTERNAL_API_SECRET) + tenant + rate limit
```

O JavaScript do navegador **não** conhece `INTERNAL_API_SECRET`,
`API_MAINTENANCE_PASS` nem a URL interna `apigsfacil:4000`.

## O que mudou

| Antes | Depois |
|--------|--------|
| Browser → Node com `pass` no body | Browser → PHP autenticado → Node com HMAC |
| `/api/addclientefast` sem middleware | HMAC obrigatório em todas as rotas mutáveis |
| CORS aberto | Origin recusado na API Node |
| Sem rate limit / helmet | Rate limit, helmet, body 32kb, error handler |
| `insertdiv` com `empresaID=1` e sem transação | Tenant da sessão + transação SQL |
| Payload de Wonca/APIBrasil no JSON | Campos sanitizados; 502/504 sem detalhe de terceiro |

## Variáveis

PHP (`php/.env`), o mesmo valor de segredo no Node:

```env
INTERNAL_API_URL=http://apigsfacil:4000
INTERNAL_API_SECRET=<gerar longo e aleatório>
INTERNAL_API_TIMEOUT=20
```

Node (`node/apigsfacil/.env`):

```env
INTERNAL_API_SECRET=<o mesmo valor>
HMAC_MAX_SKEW_SECONDS=60
RATE_LIMIT_WINDOW_MS=60000
RATE_LIMIT_MAX=300
```

Gere o segredo uma vez e copie para os dois arquivos. Não use o valor legado
`002398`. Rotacione `INTERNAL_API_SECRET` pelo procedimento em
`docs/rotacao-segredos.md`.

## Permissões (slugs já existentes)

| Rota PHP | Ação | Slug (OR) |
|----------|------|-----------|
| `/internal/api/consultaplaca` | `node.consultaplaca` | `visualizar_veiculos_clientes`, `visualizar_orcamentos` |
| `/internal/api/rastreiocod` | `node.rastreiocod` | `entrada_estoque` |
| `/internal/api/rastreio` | `node.rastreio` | `entrada_estoque` |
| `/internal/api/insertdiv` | `node.insertdiv` | `visualizar_financeiro` |
| `/internal/api/addclientefast` | `node.addclientefast` | `visualizar_veiculos_clientes`, `visualizar_orcamentos` |

`/cadastrodiv` e `/cadastroclienterapido` passam a exigir login + o slug da
ação. A senha de manutenção foi removida do formulário.

## Rollout

1. Coloque `INTERNAL_API_SECRET` idêntico em `php/.env` e `node/apigsfacil/.env`.
2. Recrie os containers:

```bash
docker compose -f php/compose.yaml --env-file php/.env up -d --build
docker compose -f node/apigsfacil/compose.yaml --env-file node/apigsfacil/.env up -d --build
```

3. Testes automatizados:

```bash
docker exec php_global php /var/www/html/shared/api-guard/tests/run.php
docker exec php_global php /var/www/html/shared/node-proxy/tests/run.php
# no diretório da API:
(cd node/apigsfacil && npm test)
```

4. Smoke autenticado (logado no gsfacilFront, same-origin):

- consulta de placa no cadastro de cliente/veículo
- rastreio de pedido (`rastreiocod`)
- cadastro rápido de cliente (`/cadastroclienterapido`)
- retirada DIV (`/cadastrodiv`)

No DevTools → Network, as chamadas devem ir para
`/gsfacilfront/public/internal/api/...` e **não** para `:4000` nem `/api` público.

5. Negativos:

```bash
# anônimo no PHP
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  http://127.0.0.1:8082/gsfacilfront/public/internal/api/consultaplaca
# esperado: 401

# tenant divergente (sessão empresa A + body empresaID=99): 403

# Node direto, sem HMAC
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  http://127.0.0.1:4000/api/addclientefast \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'nomeCliente=Teste&celularCliente=11999999999'
# esperado: 401

# pass legado ignorado
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  http://127.0.0.1:4000/api/consultaplaca \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'placa=ABC1D23&pass=002398'
# esperado: 401

# rate limit (ajuste RATE_LIMIT_MAX=3 só no teste)
# esperado: 429
```

6. Confirme no JavaScript público a ausência de `pass`, `002398`,
   `INTERNAL_API_SECRET` e `localhost:4000`.

## Quando remover a Custom Location / Proxy Host público `/api` no NPM

**Não remova agora automaticamente.** Só depois de todos os itens abaixo.

Checklist que autoriza a remoção:

1. `rg -n "002398|pass=|localhost:4000|/api/consultaplaca|/api/rastreiocod" php/gsfacilFront/public/assets/js` não encontra chamada Node.
2. DevTools (placa, rastreio, DIV, cliente rápido) mostra somente
   `/internal/api/...` same-origin, status 200 no fluxo feliz.
3. `curl` anônimo em `https://<dominio-publico-da-api>/api/consultaplaca` e
   `/api/addclientefast` retorna **401** (HMAC), não 200.
4. `curl` autenticado PHP → Node (container `php_global`) funciona:
   `docker exec php_global wget -qO- http://apigsfacil:4000/api/ping`
5. Nenhum outro consumidor (app_sistema, scripts, app móvel, Zapier) usa o
   hostname público da API. `app_sistema` hoje **não** chama apigsfacil.
6. Janela de rollback: o Proxy Host/Custom Location ainda existe, mas o
   browser já não depende dele.

Teste final no NPM, **depois** dos itens 1–6:

```bash
# Com a location /api ainda publicada, deve falhar HMAC:
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  https://api.seudominio.com.br/api/consultaplaca \
  -d 'placa=ABC1D23&pass=002398'
# 401

# Só então apague no NPM:
# - Custom Location `/api` no Proxy Host do gsfacilFront (same-origin /api), se existir
# - e/ou o Proxy Host do hostname público da API apontando para apigsfacil:4000
```

Depois da remoção, `https://api.seudominio.com.br` pode deixar de existir.
O bind `127.0.0.1:4000` permanece para túnel SSH e debug. A comunicação de
produção é só `php_global` → `apigsfacil:4000` na `rede-banco-global`.

## Rollback

1. Reverter o JS para não é suficiente: o Node **não** aceita mais `pass`.
2. Rollback real: restaurar o commit anterior de `node/apigsfacil` **e** do
   gsfacilFront/shared, recriar os dois containers.
3. `INTERNAL_API_SECRET` não precisa ser rotacionado no rollback, a menos
   que tenha vazado.

## Status HTTP

| Código | Uso |
|--------|-----|
| 400 | Validação (placa, código, campos DIV) |
| 401 | Sem sessão PHP, CSRF ausente no PHP, ou HMAC inválido no Node |
| 403 | Permissão, tenant, origem |
| 429 | Rate limit |
| 502 | Falha no serviço externo/interno, sem payload de terceiro |
| 504 | Timeout, sem detalhe de transporte |
