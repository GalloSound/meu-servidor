# PHP → apigsfacil (token de login)

O Node **não** é público. Só o container PHP fala com ele na rede Docker.

```text
Browser (já logado, cookie PHPSESSID + CSRF)
    → POST /gsfacilfront/public/internal/api/{acao}
    → PHP lê $_SESSION['token']
    → http://apigsfacil:4000/api/*
       header X-Session-Token
    → Node: SELECT gs_Administrador WHERE token = ? AND status = 1
    → usa empresa_id desse registro
```

O JavaScript **não** envia o token nem senha. Quem está logado já tem a sessão; o PHP reutiliza o mesmo token do login.

## Variável PHP

```env
INTERNAL_API_URL=http://apigsfacil:4000
```

Não há `INTERNAL_API_SECRET` nem `pass` na API.

## Recriar

```bash
docker compose -f php/compose.yaml --env-file php/.env up -d --build
docker compose -f node/apigsfacil/compose.yaml --env-file node/apigsfacil/.env up -d --build
```

## Testes

```bash
docker exec php_global php /var/www/html/shared/api-guard/tests/run.php
docker exec php_global php /var/www/html/shared/node-proxy/tests/run.php
(cd node/apigsfacil && npm test)
```

Chamada direta ao Node, sem token: **401**.

## Remover `/api` no NPM

O Node deve permanecer só em `127.0.0.1:4000` e na rede Docker. Apague Custom Location / Proxy Host público `/api` quando o DevTools mostrar apenas `/internal/api/...` e o `curl` anônimo em `:4000` retornar 401.
