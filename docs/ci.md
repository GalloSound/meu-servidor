# CI

O workflow `.github/workflows/ci.yml` roda em pull request e em push para `main`/`master`.

| Job | O que faz |
|---|---|
| `compose-config` | `docker compose config --quiet` nas cinco stacks, com `.env.example` e secrets ficticios |
| `lint-and-bash` | shellcheck, `bash -n`, `php -l` do `php/shared` e testes de cleanup, restore, tags e composer |
| `php-tests` | `php/shared/auth`, `api-guard` e `node-proxy` em PHP 8.2 |
| `node` | `npm ci`, `npm test`, `npm audit --omit=dev --audit-level=critical` |
| `composer-audit` | matriz que faz checkout de `app_nf`, `app_sistema`, `gsfacilFront`, `googlecalendar` e `peoplecontacts` e roda `composer audit --locked` em cada um |
| `secret-scan` | gitleaks na arvore atual (`--no-git`), com `.gitleaks.toml` |
| `image-scan` | Trivy misconfig CRITICAL (falha o job) e CVE CRITICAL das imagens pinadas (so relatorio) |

Os cinco repositorios sao privados. O job faz checkout com `actions/checkout` e o secret `PHP_REPOS_READ_TOKEN` (Contents: Read-only). O token nao entra na URL, no log nem na linha de comando. O job falha se `composer.lock` nao estiver no Git. Nao ha passe quando o lock falta.

No checkout local, com os diretorios em `php/`:

```bash
bash scripts/ci/composer-audit.sh
bash scripts/ci/composer-audit.sh php/gsfacilFront
```

`npm audit --omit=dev` em 21/09/2026 nao tem CRITICAL. Permanecem avisos high em `express`, `body-parser`, `path-to-regexp` e `qs`, dentro do range ja travado no lock. O job nao falha por esses high. Subir de major fica fora deste plano.

O scan de imagem nao reprova o build: a correcao de CVE upstream e trocar o digest em `docs/image-inventory.md`, nao alterar regra de negocio. Misconfig CRITICAL de Dockerfile reprova.

Localmente:

```bash
bash scripts/ci/run-bash-tests.sh
bash scripts/ci/lint.sh
bash scripts/ci/compose-config.sh
bash scripts/ci/composer-audit.sh
bash scripts/ci/scan-images.sh
```

`compose-config.sh` nao imprime o YAML interpolado.
