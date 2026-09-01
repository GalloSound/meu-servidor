# Migração de autenticação e sessão compartilhada

Escopo: `gsfacilFront` (login oficial) e `app_sistema` (consome a mesma sessão). Senhas iguais entre usuários ficam como estão até a migração funcional do sistema; esta etapa só troca o armazenamento e o cookie.

## Schema

Arquivo: `php/shared/auth/sql/001_expand_senhaAdmin_token.sql`

```sql
ALTER TABLE gs_Administrador
  MODIFY senhaAdmin VARCHAR(255) NOT NULL;

ALTER TABLE gs_Administrador
  MODIFY token VARCHAR(128) NULL;
```

- Não reescreve senhas e não faz reset em massa.
- `senhaAdmin` precisa caber bcrypt (~60) e, no futuro, argon2id (~97+).
- `token` atual no código é 32 hex (`random_bytes(16)`), cabe no `VARCHAR(32)` existente. O `ALTER` para `VARCHAR(128)` é preventivo, para tokens mais longos depois.
- Confira no phpMyAdmin (`http://localhost:8080`) o tipo atual antes de aplicar. No Docker local: `senhaAdmin` já é `VARCHAR(255)`; `token` é `VARCHAR(32)`.

Não há coluna nova de algoritmo: o prefixo `$2y$` / `$argon2` identifica hash; o resto é tratado como plaintext legado.

## Rollout

1. Backup do banco (Kopia / dump privado). Não versionar o dump.
2. Aplicar o `ALTER` no MariaDB (`mariadb_global`).
3. No Mac, `php/.env` pode ficar com `TRUSTED_PROXY_CIDRS` vazio (acesso direto em `localhost:8082`).
4. Na VPS, `php/.env`:

```env
APP_ENV=production
SESSION_LIFETIME=14400
SESSION_SAMESITE=Lax
TRUSTED_PROXY_CIDRS=172.16.0.0/12,10.0.0.0/8
APP_BASE_URL=https://gsfacil.com.br/app_sistema/
APP_BASE_URL_NEW=https://gsfacil.com.br/gsfacilfront/public/
APP_BASE_URL_APP=https://gsfacil.com.br/app/
```

   URLs públicas HTTPS no env. Não depender de `X-Forwarded-Host` para montar links.

5. Rebuild do runtime PHP (mod_remoteip + ini de sessão):

```bash
docker compose -f php/compose.yaml --env-file php/.env up -d --build
```

6. Testes no container:

```bash
docker exec php_global php /var/www/html/shared/auth/tests/run.php
docker exec php_global php /var/www/html/shared/api-guard/tests/run.php
```

7. Janela de login (senhas atuais, ainda iguais entre usuários):

- `http://localhost:8082/gsfacilfront/public/login` (Mac) ou HTTPS de produção.
- Confirmar cookie `PHPSESSID` com Path=`/`, HttpOnly, SameSite=Lax; Secure só em HTTPS.
- Abrir `app_sistema` na mesma origem: deve entrar sem login próprio.
- Logout no frontend: sessão some nos dois.
- Esperar 4h (ou ajustar `auth_expires_at` em teste) e confirmar recusa.
- Depois do primeiro login de um usuário, `senhaAdmin` no banco deve ser `$2y$...`, nunca o plaintext.

8. Criar/editar usuário em `app_sistema` já grava hash. Contas antigas migram só no login bem-sucedido.

## Rollback

| Situação | Ação |
|---|---|
| Cookie/Secure quebrou login no Mac HTTP | `APP_ENV=development`, `TRUSTED_PROXY_CIDRS` vazio, rebuild. Não reverta o hasher. |
| Código antigo (compara plaintext no SQL) depois que alguém já logou | Esse usuário **não** entra no código velho. Não faça rollback do `PasswordHasher` após o primeiro login em produção. |
| `ALTER` de coluna | Não encolha `VARCHAR(255)`: trunca hash. Deixe o tamanho. |
| Sessão | Volume `php_sessions` pode ser recriado; usuários só precisam logar de novo. Token no banco é rotacionado a cada login/logout. |

Rollback seguro de **código** só é possível **antes** do primeiro login migrado, ou se você mantiver o hasher (plaintext + `password_verify`) em qualquer versão antiga restaurada.

## Comportamento

- Duração: 4 horas absolutas a partir do login (`SESSION_LIFETIME=14400`).
- Login regenera o ID da sessão (`session_regenerate_id(true)`).
- Logout destrói a sessão, expira o cookie e zera `gs_Administrador.token`.
- `X-Forwarded-*` só vale se `REMOTE_ADDR` estiver em `TRUSTED_PROXY_CIDRS`. No Apache, `mod_remoteip` reescreve o IP do cliente quando o proxy é RFC1918.
- `display_errors` desligado em `APP_ENV=production`.
