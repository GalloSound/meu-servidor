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
| `image-scan` | checkout do submodulo `node/apigsfacil`; Trivy misconfig CRITICAL (falha o job); CVE CRITICAL corrigivel das imagens pinadas (so relatorio; falha do scanner bloqueia) |

Os cinco repositorios sao privados. O job faz checkout com `actions/checkout` e o secret `PHP_REPOS_READ_TOKEN` (Contents: Read-only). O token nao entra na URL, no log nem na linha de comando. O job falha se `composer.lock` nao estiver no Git. Nao ha passe quando o lock falta.

No checkout local, com os diretorios em `php/`:

```bash
bash scripts/ci/composer-audit.sh
bash scripts/ci/composer-audit.sh php/gsfacilFront
```

`npm audit --omit=dev` em 21/09/2026 nao tem CRITICAL. Permanecem avisos high em `express`, `body-parser`, `path-to-regexp` e `qs`, dentro do range ja travado no lock. O job nao falha por esses high. Subir de major fica fora deste plano.

O job `image-scan` inicializa o submodulo privado `node/apigsfacil` com `APIGSFACIL_READ_TOKEN` e `persist-credentials: false`. Sem esse checkout o diretorio chega vazio e o Trivy config nao ve `node/apigsfacil/Dockerfile`.

O passo de misconfig usa `aquasecurity/trivy-action@v0.36.0` (Trivy v0.70.0), `severity: CRITICAL` e `exit-code: 1`. Em 02/10/2026, Trivy 0.70.0 e 0.74.0 leram tres Dockerfiles (`infra/backup/Dockerfile`, `node/apigsfacil/Dockerfile` e `php/Dockerfile`) e nao acharam misconfig CRITICAL. `compose.yaml` nao e alvo desses scanners.

CVE de imagem continua so em relatorio. `SCAN_IMAGES_STRICT` nao esta ligado no workflow. Trivy 0.74.0 com codigo de saida 0 termina 0 mesmo quando existe CVE CRITICAL corrigivel: `mariadb:11.4` tem CVE-2025-68121 e mesmo assim saiu 0. O mesmo scan com codigo de saida 1 saiu 1 nessa imagem e 0 em `filebrowser/filebrowser:v2-s6`, que nao tem CVE CRITICAL corrigivel. O script agora so pede codigo de saida 1 quando `SCAN_IMAGES_STRICT=true`. O padrao pede codigo 0: achado nao bloqueia. Falha operacional do scanner bloqueia nos dois modos, depois de varrer todas as imagens. No modo estrito, achado ou falha operacional reprova.

Ligar o modo estrito agora reprovaria o CI. O inventario de 02/10/2026, em `docs/image-inventory.md`, mostra CVE CRITICAL corrigivel em imagens que o workflow varre. O proximo passo e escolher outro digest de proposito, trocar o pin e esta tabela no mesmo cambio, varrer de novo e so entao exportar `SCAN_IMAGES_STRICT=true` no job quando o conjunto pinado nao tiver CVE CRITICAL corrigivel. Nao usar tag flutuante e nao atualizar digest sozinho.

Localmente:

```bash
bash scripts/ci/run-bash-tests.sh
bash scripts/ci/lint.sh
bash scripts/ci/compose-config.sh
bash scripts/ci/composer-audit.sh
bash scripts/ci/scan-images.sh
```

`compose-config.sh` nao imprime o YAML interpolado.
