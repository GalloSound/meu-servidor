<?php

declare(strict_types=1);

/**
 * X-Forwarded-* só vale quando REMOTE_ADDR está na lista confiável (NPM/rede Docker).
 */
final class TrustedProxy
{
    /**
     * @param array<string, mixed> $server
     */
    public static function isTrusted(array $server)
    {
        $remote = self::remoteAddr($server);
        if ($remote === '') {
            return false;
        }

        foreach (self::cidrs() as $cidr) {
            if (self::ipInCidr($remote, $cidr)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @param array<string, mixed> $server
     */
    public static function clientIp(array $server)
    {
        if (self::isTrusted($server)) {
            $forwarded = self::firstForwarded($server, 'HTTP_X_FORWARDED_FOR');
            if ($forwarded !== '') {
                return $forwarded;
            }
        }

        $remote = self::remoteAddr($server);

        return $remote !== '' ? $remote : '0.0.0.0';
    }

    /**
     * @param array<string, mixed> $server
     */
    public static function isHttps(array $server)
    {
        if (AuthRuntime::isProduction()) {
            return true;
        }

        $https = isset($server['HTTPS']) ? strtolower((string) $server['HTTPS']) : '';
        if ($https === 'on' || $https === '1') {
            return true;
        }

        if ((string) (isset($server['SERVER_PORT']) ? $server['SERVER_PORT'] : '') === '443') {
            return true;
        }

        if (self::isTrusted($server)) {
            $proto = strtolower(self::firstForwarded($server, 'HTTP_X_FORWARDED_PROTO'));
            if ($proto === 'https') {
                return true;
            }
        }

        $scheme = isset($server['REQUEST_SCHEME']) ? strtolower((string) $server['REQUEST_SCHEME']) : '';

        return $scheme === 'https';
    }

    /**
     * @param array<string, mixed> $server
     */
    public static function host(array $server)
    {
        $host = '';
        if (self::isTrusted($server) && !empty($server['HTTP_X_FORWARDED_HOST'])) {
            $host = self::firstForwarded($server, 'HTTP_X_FORWARDED_HOST');
        }

        if ($host === '') {
            if (!empty($server['HTTP_HOST'])) {
                $host = trim((string) $server['HTTP_HOST']);
            } elseif (!empty($server['SERVER_NAME'])) {
                $host = trim((string) $server['SERVER_NAME']);
            }
        }

        return $host;
    }

    /**
     * @return list<string>
     */
    public static function cidrs()
    {
        $raw = AuthRuntime::env('TRUSTED_PROXY_CIDRS', '');
        if ($raw === '') {
            return array();
        }

        $parts = preg_split('/[\s,]+/', $raw);
        $cidrs = array();
        if (!is_array($parts)) {
            return array();
        }

        foreach ($parts as $part) {
            $part = trim((string) $part);
            if ($part !== '') {
                $cidrs[] = $part;
            }
        }

        return $cidrs;
    }

    /**
     * @param array<string, mixed> $server
     */
    private static function remoteAddr(array $server)
    {
        return isset($server['REMOTE_ADDR']) ? trim((string) $server['REMOTE_ADDR']) : '';
    }

    /**
     * @param array<string, mixed> $server
     */
    private static function firstForwarded(array $server, $header)
    {
        if (empty($server[$header])) {
            return '';
        }

        $parts = explode(',', (string) $server[$header]);

        return trim($parts[0]);
    }

    private static function ipInCidr($ip, $cidr)
    {
        if (strpos($cidr, '/') === false) {
            return hash_equals($cidr, $ip);
        }

        $bits = explode('/', $cidr, 2);
        $subnet = $bits[0];
        $maskBits = (int) $bits[1];

        $ipBin = inet_pton($ip);
        $subnetBin = inet_pton($subnet);
        if ($ipBin === false || $subnetBin === false || strlen($ipBin) !== strlen($subnetBin)) {
            return false;
        }

        $maxBits = strlen($ipBin) * 8;
        if ($maskBits < 0 || $maskBits > $maxBits) {
            return false;
        }

        $fullBytes = (int) floor($maskBits / 8);
        $remain = $maskBits % 8;
        if ($fullBytes > 0 && substr($ipBin, 0, $fullBytes) !== substr($subnetBin, 0, $fullBytes)) {
            return false;
        }
        if ($remain === 0) {
            return true;
        }

        $mask = chr((0xFF << (8 - $remain)) & 0xFF);

        return ($ipBin[$fullBytes] & $mask) === ($subnetBin[$fullBytes] & $mask);
    }
}
