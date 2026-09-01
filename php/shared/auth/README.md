# Autenticação e sessão compartilhada

Biblioteca do runtime PHP (`php/shared/auth`). Não é namespace HTTP (`/shared` responde 403).

## Contrato

- Login oficial: **gsfacilFront**. `app_sistema` redireciona `/login` para o frontend.
- Cookie `PHPSESSID`: `path=/`, HttpOnly, Secure em HTTPS/produção, SameSite=Lax (ou Strict via env), 4 horas.
- `$_SESSION['token']` = `gs_Administrador.token` (obrigatório para `isLogged` / `checkLogin`).
- `$_SESSION['ccUser']` = `idAdmin` (alias legado; sozinho não autentica).
- `$_SESSION['auth_expires_at']` = unix de expiração absoluta.
- Senha: `password_hash` / `password_verify`. Plaintext legado é migrado no primeiro login com sucesso. Sem MD5/SHA1.

## Testes

```bash
docker exec php_global php /var/www/html/shared/auth/tests/run.php
```

Requer PDO SQLite.
