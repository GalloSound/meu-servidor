<?php

declare(strict_types=1);

final class NodeApiClient
{
    public const HEADER_TIMESTAMP = 'X-Internal-Timestamp';
    public const HEADER_NONCE = 'X-Internal-Nonce';
    public const HEADER_SIGNATURE = 'X-Internal-Signature';

    public function __construct(
        private string $baseUrl,
        private string $secret,
        private int $timeoutSeconds = 20,
        private int $connectTimeoutSeconds = 5
    ) {
        $this->baseUrl = rtrim($baseUrl, '/');
        if ($this->baseUrl === '' || $this->secret === '') {
            throw new InvalidArgumentException('Cliente interno sem configuração.');
        }
    }

    public static function fromEnv(): self
    {
        $base = getenv('INTERNAL_API_URL');
        $secret = getenv('INTERNAL_API_SECRET');
        $timeout = getenv('INTERNAL_API_TIMEOUT');

        if ($base === false || trim((string) $base) === '' || $secret === false || trim((string) $secret) === '') {
            throw new RuntimeException('INTERNAL_API_URL e INTERNAL_API_SECRET são obrigatórios.');
        }

        $timeoutSeconds = 20;
        if (is_string($timeout) && preg_match('/^[1-9][0-9]*$/', $timeout) === 1) {
            $timeoutSeconds = (int) $timeout;
        }

        return new self(trim((string) $base), trim((string) $secret), $timeoutSeconds);
    }

    /**
     * @param array<string, scalar|null> $fields
     * @return array{status:int, json:array<string, mixed>}
     */
    public function post(string $path, array $fields): array
    {
        $path = '/' . ltrim($path, '/');
        $body = http_build_query($fields, '', '&', PHP_QUERY_RFC3986);
        $timestamp = (string) time();
        $nonce = bin2hex(random_bytes(16));
        $signature = self::sign($this->secret, $timestamp, $nonce, 'POST', $path, $body);

        $headers = [
            'Accept: application/json',
            'Content-Type: application/x-www-form-urlencoded',
            'X-Content-Type-Options: nosniff',
            self::HEADER_TIMESTAMP . ': ' . $timestamp,
            self::HEADER_NONCE . ': ' . $nonce,
            self::HEADER_SIGNATURE . ': ' . $signature,
        ];

        $url = $this->baseUrl . $path;

        try {
            $raw = $this->request($url, $headers, $body);
        } catch (NodeApiTimeout $e) {
            return [
                'status' => 504,
                'json' => [
                    'error' => 'Tempo esgotado no serviço interno',
                    'result' => [],
                ],
            ];
        } catch (Throwable $e) {
            error_log('node-proxy: falha de transporte');
            return [
                'status' => 502,
                'json' => [
                    'error' => 'Falha no serviço interno',
                    'result' => [],
                ],
            ];
        }

        $status = $raw['status'];
        $decoded = json_decode($raw['body'], true);
        if (!is_array($decoded)) {
            return [
                'status' => $status >= 400 ? $status : 502,
                'json' => [
                    'error' => 'Resposta inválida do serviço interno',
                    'result' => [],
                ],
            ];
        }

        return [
            'status' => $status,
            'json' => self::sanitizeJson($decoded),
        ];
    }

    public static function sign(
        string $secret,
        string $timestamp,
        string $nonce,
        string $method,
        string $path,
        string $body
    ): string {
        $canonical = implode("\n", [
            $timestamp,
            $nonce,
            strtoupper($method),
            $path,
            hash('sha256', $body),
        ]);

        return hash_hmac('sha256', $canonical, $secret);
    }

    /**
     * @param array<string, mixed> $decoded
     * @return array<string, mixed>
     */
    public static function sanitizeJson(array $decoded): array
    {
        unset($decoded['detalhe'], $decoded['stack'], $decoded['trace'], $decoded['upstream']);
        if (!array_key_exists('error', $decoded)) {
            $decoded['error'] = '';
        }
        if (!array_key_exists('result', $decoded) || !is_array($decoded['result'])) {
            $decoded['result'] = [];
        }

        return $decoded;
    }

    /**
     * @param list<string> $headers
     * @return array{status:int, body:string}
     */
    private function request(string $url, array $headers, string $body): array
    {
        $context = stream_context_create([
            'http' => [
                'method' => 'POST',
                'header' => implode("\r\n", $headers),
                'content' => $body,
                'timeout' => $this->timeoutSeconds,
                'ignore_errors' => true,
                'follow_location' => 0,
                'protocol_version' => 1.1,
            ],
            'ssl' => [
                'verify_peer' => true,
                'verify_peer_name' => true,
            ],
        ]);

        $level = error_reporting();
        error_reporting($level & ~E_WARNING);
        $response = file_get_contents($url, false, $context);
        error_reporting($level);

        if ($response === false) {
            $last = error_get_last();
            $message = is_array($last) ? (string) ($last['message'] ?? '') : '';
            if (str_contains(strtolower($message), 'timed out') || str_contains(strtolower($message), 'timeout')) {
                throw new NodeApiTimeout('timeout');
            }
            throw new RuntimeException('transport');
        }

        $status = 502;
        foreach ($http_response_header ?? [] as $line) {
            if (preg_match('/^HTTP\/\S+\s+(\d{3})/', $line, $m) === 1) {
                $status = (int) $m[1];
            }
        }

        return ['status' => $status, 'body' => $response];
    }
}

final class NodeApiTimeout extends RuntimeException
{
}
