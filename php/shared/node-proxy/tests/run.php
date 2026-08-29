<?php

declare(strict_types=1);

require dirname(__DIR__) . '/NodeApiClient.php';

final class NodeApiClientTest
{
    private int $passed = 0;
    private int $failed = 0;

    /** @var list<string> */
    private array $failures = [];

    public function run(): int
    {
        $this->testSanitizeStripsUpstream();
        $this->testFromEnvFailFast();
        $this->testTimeoutDoesNotLeak();

        echo $this->passed . ' passed, ' . $this->failed . ' failed' . PHP_EOL;
        foreach ($this->failures as $failure) {
            echo 'FAIL: ' . $failure . PHP_EOL;
        }

        return $this->failed === 0 ? 0 : 1;
    }

    private function testSanitizeStripsUpstream(): void
    {
        $clean = NodeApiClient::sanitizeJson([
            'error' => 'x',
            'detalhe' => ['token' => 'leak'],
            'result' => ['ok' => true],
        ]);
        $encoded = json_encode($clean) ?: '';
        $this->assertTrue(
            !isset($clean['detalhe']) && !str_contains($encoded, 'leak'),
            'sanitize remove payload de terceiro'
        );
    }

    private function testFromEnvFailFast(): void
    {
        $prevUrl = getenv('INTERNAL_API_URL');
        putenv('INTERNAL_API_URL');
        try {
            NodeApiClient::fromEnv();
            $this->fail('fromEnv fail-fast', 'deveria lançar');
        } catch (RuntimeException $e) {
            $this->assertTrue(str_contains($e->getMessage(), 'INTERNAL_API_URL'), 'fromEnv exige URL');
        } finally {
            if ($prevUrl !== false) {
                putenv('INTERNAL_API_URL=' . $prevUrl);
            }
        }
    }

    private function testTimeoutDoesNotLeak(): void
    {
        $client = new NodeApiClient('http://127.0.0.1:1', 1);
        $result = $client->post('/api/consultaplaca', ['placa' => 'ABC1D23'], 'tok-teste');
        $encoded = json_encode($result) ?: '';
        $ok = in_array($result['status'], [502, 504], true)
            && !str_contains($encoded, 'Connection refused')
            && !str_contains(strtolower($encoded), '127.0.0.1');
        $this->assertTrue($ok, 'timeout/recusa não vaza detalhe de transporte');
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

exit((new NodeApiClientTest())->run());
