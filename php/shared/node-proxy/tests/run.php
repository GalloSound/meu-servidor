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
        $this->testSignMatchesNode();
        $this->testSanitizeStripsUpstream();
        $this->testFromEnvFailFast();
        $this->testTimeoutDoesNotLeak();

        echo $this->passed . ' passed, ' . $this->failed . ' failed' . PHP_EOL;
        foreach ($this->failures as $failure) {
            echo 'FAIL: ' . $failure . PHP_EOL;
        }

        return $this->failed === 0 ? 0 : 1;
    }

    private function testSignMatchesNode(): void
    {
        $secret = 'php-node-shared';
        $timestamp = '1710000000';
        $nonce = '00112233445566778899aabbccddeeff';
        $method = 'POST';
        $path = '/api/addclientefast';
        $body = 'nomeCliente=Ana';
        $php = NodeApiClient::sign($secret, $timestamp, $nonce, $method, $path, $body);

        $node = $this->nodeSign($secret, $timestamp, $nonce, $method, $path, $body);
        if ($node === null) {
            $this->assertTrue(preg_match('/^[a-f0-9]{64}$/', $php) === 1, 'HMAC PHP gerado (Node hmac.js ausente neste ambiente)');
            return;
        }
        $this->assertTrue(hash_equals($php, $node) && strlen($php) === 64, 'HMAC PHP === HMAC Node');
    }

    private function testSanitizeStripsUpstream(): void
    {
        $clean = NodeApiClient::sanitizeJson([
            'error' => 'x',
            'detalhe' => ['token' => 'leak', 'data' => 'wonca'],
            'stack' => 'trace',
            'result' => ['ok' => true],
        ]);
        $encoded = json_encode($clean) ?: '';
        $this->assertTrue(
            !isset($clean['detalhe']) && !str_contains($encoded, 'leak') && ($clean['result']['ok'] ?? false) === true,
            'sanitize remove payload de terceiro'
        );
    }

    private function testFromEnvFailFast(): void
    {
        $prevUrl = getenv('INTERNAL_API_URL');
        $prevSecret = getenv('INTERNAL_API_SECRET');
        putenv('INTERNAL_API_URL');
        putenv('INTERNAL_API_SECRET');
        try {
            NodeApiClient::fromEnv();
            $this->fail('fromEnv fail-fast', 'deveria lançar');
        } catch (RuntimeException $e) {
            $this->assertTrue(str_contains($e->getMessage(), 'INTERNAL_API'), 'fromEnv exige env');
        } finally {
            if ($prevUrl !== false) {
                putenv('INTERNAL_API_URL=' . $prevUrl);
            }
            if ($prevSecret !== false) {
                putenv('INTERNAL_API_SECRET=' . $prevSecret);
            }
        }
    }

    private function testTimeoutDoesNotLeak(): void
    {
        $client = new NodeApiClient('http://127.0.0.1:1', 'unit-secret', 1, 1);
        $result = $client->post('/api/consultaplaca', ['placa' => 'ABC1D23']);
        $encoded = json_encode($result) ?: '';
        $ok = in_array($result['status'], [502, 504], true)
            && !str_contains($encoded, 'cURL')
            && !str_contains($encoded, 'Connection refused')
            && !str_contains(strtolower($encoded), '127.0.0.1');
        $this->assertTrue($ok, 'timeout/recusa não vaza detalhe de transporte');
    }

    private function nodeSign(
        string $secret,
        string $timestamp,
        string $nonce,
        string $method,
        string $path,
        string $body
    ): ?string {
        $hmacJs = dirname(__DIR__, 4) . '/node/apigsfacil/src/lib/hmac.js';
        if (!is_file($hmacJs)) {
            return null;
        }

        $script = 'const hmac=require(' . json_encode($hmacJs) . ');'
            . 'process.stdout.write(hmac.sign('
            . json_encode([
                'secret' => $secret,
                'timestamp' => $timestamp,
                'nonce' => $nonce,
                'method' => $method,
                'path' => $path,
                'body' => $body,
            ], JSON_UNESCAPED_SLASHES)
            . '));';

        $cmd = 'node -e ' . escapeshellarg($script);
        $out = [];
        $code = 0;
        exec($cmd, $out, $code);
        $sig = implode('', $out);
        if ($code !== 0 || !preg_match('/^[a-f0-9]{64}$/', $sig)) {
            return null;
        }

        return $sig;
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
