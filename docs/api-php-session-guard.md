# Rollout e rollback — guard de sessão /gcar e /apicontacts

## O que muda

As APIs PHP ` /gcar ` e ` /apicontacts ` passam a exigir:

1. Cookie `PHPSESSID` com sessão autenticada do `gsfacilFront` (`$_SESSION['token']`).
2. Header `X-CSRF-Token` (token emitido na página logada, ligado à sessão).
3. Empresa/usuário resolvidos no servidor; body divergente retorna 403.
4. Permissão do grupo (slugs já usados nas telas de orçamento/clientes).
5. Same-origin. `Access-Control-Allow-Origin: *` foi removido.

Não há segredo fixo no browser. Credenciais OAuth/DB não foram alteradas.

## Rollout

1. Confirmar PHP 8.2 no runtime (`PHP_VERSION=8.2` em `php/.env`).
2. Subir o volume `./shared` (já no `php/compose.yaml`) e reconstruir a imagem PHP para o deny de `/shared` no Apache:

```bash
docker compose -f php/compose.yaml --env-file php/.env up -d --build
```

3. Rodar os testes do guard **dentro do container** (PDO SQLite faz parte da imagem PHP):

```bash
docker exec php_global php /var/www/html/shared/api-guard/tests/run.php
```

4. Smoke no browser, logado no `gsfacilFront` (same-origin):

- criar/editar/excluir evento de agenda
- criar/editar contato People Contacts (ambiente ON-LINE)

5. Smoke negativo (curl, sem cookie de sessão):

```bash
curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://gsfacil.com.br/gcar/addcalendar.php
# esperado: 401

curl -sS -D - -o /dev/null -X OPTIONS https://gsfacil.com.br/gcar/addcalendar.php \
  -H 'Origin: https://evil.example' -H 'Access-Control-Request-Method: POST'
# esperado: 403 e nenhum Access-Control-Allow-Origin: https://evil.example
```

6. Só então apontar o DNS/proxy definitivo para este servidor Docker. O Hostgator legado não precisa consumir estes endpoints.

## Rollback

1. Reverter os wrappers em `php/googlecalendar/public_html/gcar/` e `php/peoplecontacts/public_html/apicontacts/` para o `require` direto de `config.php` + arquivo público, sem `ApiSessionGuard::protect`.
2. Restaurar `googlecalendar/public/return.php` e `peoplecontacts/public/return.php` se algum cliente legado ainda depender de CORS (neste plano, não deve haver).
3. Reverter o JS (`admin.js`, `functionsCadastroCliente.js`, `footer.php`) se o frontend novo já estiver em produção junto.
4. Recolocar o container PHP:

```bash
docker compose -f php/compose.yaml --env-file php/.env up -d --build
```

O volume de sessão e as credenciais permanecem intocados. Rollback não exige rotacionar OAuth nem senha do banco.

## Observações

- `oauth2callback.php` agora exige sessão + permissão `desenvolvedor_piloto` (GET, sem CSRF).
- Logs de auditoria vão para o error log do PHP (`event=api-guard`), sem cookie, token ou payload.
