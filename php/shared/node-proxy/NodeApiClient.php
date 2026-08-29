<?php

declare(strict_types=1);

/**
 * Cliente HTTP PHP → Node, só na rede Docker (http://apigsfacil:4000).
 * Autenticação: header X-Session-Token = token do login (gs_Administrador.token).
 */
final class NodeApiClient
{
    public const HEADER_TOKEN = 'X-Session-Token';

    public function __construct(
        private string $baseUrl,
        private int $timeoutSeconds = 20
    ) {
        $this->baseUrl = rtrim($baseUrl, '/');
        if ($this->baseUrl === '') {
            throw new InvalidArgumentException('INTERNAL_API_URL ausente.');
        }
    }

    public static function fromEnv(): self
    {
        $base = self::readEnv('INTERNAL_API_URL');
        $timeout = self::readEnv('INTERNAL_API_TIMEOUT');

        if ($base === null) {
            throw new RuntimeException('INTERNAL_API_URL é obrigatório.');
        }

        $timeoutSeconds = 20;
        if ($timeout !== null && preg_match('/^[1-9][0-9]*$/', $timeout) === 1) {
            $timeoutSeconds = (int) $timeout;
        }

        return new self($base, $timeoutSeconds);
    }

    private static function readEnv(string $name): ?string
    {
        foreach ([getenv($name), $_SERVER[$name] ?? null, $_ENV[$name] ?? null] as $value) {
            if (is_string($value) && trim($value) !== '') {
                return trim($value);
            }
        }

        return null;
    }

    /**
     * @param array<string, scalar|null> $fields
     * @return array{status:int, json:array<string, mixed>}
     */
    public function post(string $path, array $fields, string $loginToken): array
    {
        if (trim($loginToken) === '') {
            throw new InvalidArgumentException('Token de sessão ausente.');
        }

        $path = '/' . ltrim($path, '/');
        unset($fields['token'], $fields['pass'], $fields['password'], $fields['empresaID'], $fields['empresa_id']);
        $body = http_build_query($fields, '', '&', PHP_QUERY_RFC3986);

        $headers = [
            'Accept: application/json',
            'Content-Type: application/x-www-form-urlencoded',
            'X-Content-Type-Options: nosniff',
            self::HEADER_TOKEN . ': ' . $loginToken,
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

    /**
     * @param array<string, mixed> $decoded
     * @return array<string, mixed>
     */
    public static function sanitizeJson(array $decoded): array
    {
        unset($decoded['detalhe'], $decoded['stack'], $decoded['trace'], $decoded['upstream'], $decoded['token']);
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
