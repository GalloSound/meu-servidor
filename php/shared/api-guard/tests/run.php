<?php

declare(strict_types=1);

require dirname(__DIR__) . '/ApiSessionGuard.php';

final class ApiSessionGuardTest
{
    private int $passed = 0;
    private int $failed = 0;

    /** @var list<string> */
    private array $failures = [];

    public function run(): int
    {
        if (!in_array('sqlite', PDO::getAvailableDrivers(), true)) {
            fwrite(STDERR, "PDO SQLite ausente. Rode no container PHP (tem pdo_sqlite na imagem):\n");
            fwrite(STDERR, "  docker exec php_global php /var/www/html/shared/api-guard/tests/run.php\n");
            fwrite(STDERR, "Se o driver ainda faltar, reconstrua: docker compose -f php/compose.yaml --env-file php/.env up -d --build\n");
            return 2;
        }

        $this->testNoCookieReturns401();
        $this->testValidCookieWithoutCsrfReturns403();
        $this->testInvalidCsrfReturns403();
        $this->testDivergentTenantReturns403();
        $this->testAuthorizedUserSucceeds();
        $this->testUserWithoutPermissionReturns403();
        $this->testOptionsRejectsArbitraryOrigin();
        $this->testNodeActionAuthorized();
        $this->testNodeActionWithoutPermission();
        $this->testNodeDivergentTenant();

        echo $this->passed . ' passed, ' . $this->failed . ' failed' . PHP_EOL;
        foreach ($this->failures as $failure) {
            echo 'FAIL: ' . $failure . PHP_EOL;
        }

        return $this->failed === 0 ? 0 : 1;
    }

    private function testNoCookieReturns401(): void
    {
        $this->expectDenied('sem cookie: 401', 401, 'unauthenticated', function (): void {
            $this->guard([
                'session' => [],
                'post' => ['title' => 'x'],
            ])->assert(ApiSessionGuard::ACTION_CALENDAR_CREATE);
        });
    }

    private function testValidCookieWithoutCsrfReturns403(): void
    {
        $this->expectDenied('cookie válido sem CSRF: 403', 403, 'csrf', function (): void {
            $this->guard([
                'session' => [
                    'token' => 'tok-ok',
                    ApiSessionGuard::CSRF_SESSION_KEY => 'csrf-ok',
                ],
                'post' => ['title' => 'x'],
                'headers' => [],
            ])->assert(ApiSessionGuard::ACTION_CALENDAR_CREATE);
        });
    }

    private function testInvalidCsrfReturns403(): void
    {
        $this->expectDenied('CSRF inválido: 403', 403, 'csrf', function (): void {
            $this->guard([
                'session' => [
                    'token' => 'tok-ok',
                    ApiSessionGuard::CSRF_SESSION_KEY => 'csrf-ok',
                ],
                'post' => ['title' => 'x'],
                'headers' => ['X-CSRF-Token' => 'csrf-errado'],
            ])->assert(ApiSessionGuard::ACTION_CALENDAR_CREATE);
        });
    }

    private function testDivergentTenantReturns403(): void
    {
        $this->expectDenied('tenant divergente: 403', 403, 'tenant', function (): void {
            $this->guard([
                'session' => [
                    'token' => 'tok-ok',
                    ApiSessionGuard::CSRF_SESSION_KEY => 'csrf-ok',
                ],
                'post' => ['empresaID' => '99', 'title' => 'x'],
                'headers' => ['X-CSRF-Token' => 'csrf-ok'],
            ])->assert(ApiSessionGuard::ACTION_CALENDAR_CREATE);
        });
    }

    private function testAuthorizedUserSucceeds(): void
    {
        try {
            $context = $this->guard([
                'session' => [
                    'token' => 'tok-ok',
                    ApiSessionGuard::CSRF_SESSION_KEY => 'csrf-ok',
                ],
                'post' => ['empresaID' => '5', 'title' => 'x'],
                'headers' => ['X-CSRF-Token' => 'csrf-ok'],
            ])->assert(ApiSessionGuard::ACTION_CALENDAR_CREATE);

            $this->assertTrue(
                $context['userId'] === 10 && $context['empresaId'] === 5,
                'usuário autorizado: fluxo funciona'
            );
        } catch (Throwable $e) {
            $this->fail('usuário autorizado: fluxo funciona', $e->getMessage());
        }
    }

    private function testUserWithoutPermissionReturns403(): void
    {
        $this->expectDenied('usuário sem permissão: 403', 403, 'forbidden', function (): void {
            $this->guard([
                'session' => [
                    'token' => 'tok-noperm',
                    ApiSessionGuard::CSRF_SESSION_KEY => 'csrf-ok',
                ],
                'post' => ['title' => 'x'],
                'headers' => ['X-CSRF-Token' => 'csrf-ok'],
            ])->assert(ApiSessionGuard::ACTION_CALENDAR_CREATE);
        });
    }

    private function testOptionsRejectsArbitraryOrigin(): void
    {
        $this->expectDenied('OPTIONS não permite origem arbitrária', 403, 'cors', function (): void {
            $this->guard([
                'server' => [
                    'REQUEST_METHOD' => 'OPTIONS',
                    'HTTP_ORIGIN' => 'https://evil.example',
                    'HTTP_HOST' => 'gsfacil.com.br',
                    'HTTPS' => 'on',
                ],
                'session' => [],
            ])->assert(ApiSessionGuard::ACTION_CALENDAR_CREATE);
        });
    }

    private function testNodeActionAuthorized(): void
    {
        try {
            $context = $this->guard([
                'session' => [
                    'token' => 'tok-ok',
                    ApiSessionGuard::CSRF_SESSION_KEY => 'csrf-ok',
                ],
                'post' => ['empresaID' => '5', 'placa' => 'ABC1D23'],
                'headers' => ['X-CSRF-Token' => 'csrf-ok'],
            ])->assert(ApiSessionGuard::ACTION_NODE_CONSULTA_PLACA);

            $this->assertTrue(
                $context['empresaId'] === 5,
                'node consultaplaca autorizado'
            );
        } catch (Throwable $e) {
            $this->fail('node consultaplaca autorizado', $e->getMessage());
        }
    }

    private function testNodeActionWithoutPermission(): void
    {
        $this->expectDenied('node sem permissão: 403', 403, 'forbidden', function (): void {
            $this->guard([
                'session' => [
                    'token' => 'tok-noperm',
                    ApiSessionGuard::CSRF_SESSION_KEY => 'csrf-ok',
                ],
                'post' => ['code' => 'AB123'],
                'headers' => ['X-CSRF-Token' => 'csrf-ok'],
            ])->assert(ApiSessionGuard::ACTION_NODE_RASTREIO_COD);
        });
    }

    private function testNodeDivergentTenant(): void
    {
        $this->expectDenied('node tenant divergente: 403', 403, 'tenant', function (): void {
            $this->guard([
                'session' => [
                    'token' => 'tok-ok',
                    ApiSessionGuard::CSRF_SESSION_KEY => 'csrf-ok',
                ],
                'post' => ['empresaID' => '99', 'user' => '2', 'descricao' => 'x', 'valor' => '10'],
                'headers' => ['X-CSRF-Token' => 'csrf-ok'],
            ])->assert(ApiSessionGuard::ACTION_NODE_INSERT_DIV);
        });
    }

    /**
     * @param array<string, mixed> $overrides
     */
    private function guard(array $overrides): ApiSessionGuard
    {
        $server = array_merge([
            'REQUEST_METHOD' => 'POST',
            'HTTP_HOST' => 'gsfacil.com.br',
            'HTTPS' => 'on',
            'REQUEST_URI' => '/gcar/addcalendar.php',
            'REMOTE_ADDR' => '203.0.113.10',
        ], $overrides['server'] ?? []);

        return new ApiSessionGuard(
            $this->pdo(),
            $server,
            $overrides['post'] ?? [],
            $overrides['session'] ?? [],
            $overrides['headers'] ?? [],
            $overrides['rawInput'] ?? '',
            false
        );
    }

    private function pdo(): PDO
    {
        static $pdo = null;
        if ($pdo instanceof PDO) {
            return $pdo;
        }

        $pdo = new PDO('sqlite::memory:');
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->exec('CREATE TABLE empresasUsuarias (
            idEmpresa INTEGER PRIMARY KEY,
            nomeEmpresa TEXT,
            timezone TEXT,
            ipFixo TEXT,
            contacts TEXT,
            idBalcaoEmp INTEGER,
            urlLogo TEXT
        )');
        $pdo->exec('CREATE TABLE gs_Administrador (
            idAdmin INTEGER PRIMARY KEY,
            group_id INTEGER,
            empresa_id INTEGER,
            nomeAdmin TEXT,
            token TEXT,
            status INTEGER
        )');
        $pdo->exec('CREATE TABLE permission_links (
            id_permission_group INTEGER,
            id_permission_item INTEGER,
            empresaID INTEGER
        )');
        $pdo->exec('CREATE TABLE permission_itens (
            id INTEGER PRIMARY KEY,
            slug TEXT
        )');

        $pdo->exec("INSERT INTO empresasUsuarias (idEmpresa, nomeEmpresa, timezone, ipFixo)
            VALUES (5, 'Empresa Teste', 'America/Sao_Paulo', '192.0.2.1')");
        $pdo->exec("INSERT INTO gs_Administrador (idAdmin, group_id, empresa_id, nomeAdmin, token, status)
            VALUES (10, 2, 5, 'Auth', 'tok-ok', 1), (11, 3, 5, 'NoPerm', 'tok-noperm', 1)");
        $pdo->exec("INSERT INTO permission_itens (id, slug) VALUES
            (1, 'visualizar_orcamentos'),
            (2, 'external_access'),
            (3, 'exemplo'),
            (4, 'visualizar_financeiro'),
            (5, 'entrada_estoque'),
            (6, 'visualizar_veiculos_clientes')");
        $pdo->exec('INSERT INTO permission_links (id_permission_group, id_permission_item, empresaID) VALUES
            (2, 1, 1),
            (2, 2, 1),
            (2, 4, 1),
            (2, 5, 1),
            (2, 6, 1),
            (3, 2, 1),
            (3, 3, 1)');

        return $pdo;
    }

    private function expectDenied(string $label, int $status, string $reason, callable $fn): void
    {
        try {
            $fn();
            $this->fail($label, 'esperado ' . $status . '/' . $reason . ', mas o guard autorizou');
        } catch (ApiAuthDenied $e) {
            $ok = $e->httpStatus === $status && $e->reason === $reason && $e->getMessage() !== '';
            $noTrace = !str_contains($e->getMessage(), 'Stack trace')
                && !str_contains($e->getMessage(), 'ApiSessionGuard.php');
            if ($ok && $noTrace) {
                $this->passed++;
                echo 'PASS ' . $label . PHP_EOL;
                return;
            }
            $this->fail(
                $label,
                'obtido ' . $e->httpStatus . '/' . $e->reason . ' — ' . $e->getMessage()
            );
        } catch (Throwable $e) {
            $this->fail($label, get_class($e) . ': ' . $e->getMessage());
        }
    }

    private function assertTrue(bool $ok, string $label): void
    {
        if ($ok) {
            $this->passed++;
            echo 'PASS ' . $label . PHP_EOL;
            return;
        }
        $this->fail($label, 'asserção falsa');
    }

    private function fail(string $label, string $detail): void
    {
        $this->failed++;
        $this->failures[] = $label . ' — ' . $detail;
        echo 'FAIL ' . $label . PHP_EOL;
    }
}

exit((new ApiSessionGuardTest())->run());
