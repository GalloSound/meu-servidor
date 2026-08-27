# Guard de sessão das APIs PHP (/gcar e /apicontacts)

Biblioteca compartilhada do runtime PHP. Não é namespace HTTP (`/shared` responde 403).

## Contrato

- Login oficial: `gsfacilFront` grava `$_SESSION['token']`.
- Cookie `PHPSESSID` compartilhado no volume `php_sessions`.
- Empresa e usuário vêm do banco a partir do token da sessão.
- `empresaID` / `userID` no body, se enviados, só podem coincidir com a sessão.
- CSRF: `$_SESSION['csrf_token']` + header `X-CSRF-Token`.
- Same-origin em `https://gsfacil.com.br`. Origem arbitrária em OPTIONS/CORS é recusada.

## Testes

```bash
php php/shared/api-guard/tests/run.php
```

Requer PDO SQLite.
