<?php

declare(strict_types=1);

/**
 * URLs públicas vêm do env quando forem absolutas (produção).
 * Sem URL absoluta, monta origin só com Host local / proxy confiável.
 */
final class PublicUrl
{
    /**
     * @param array<string, mixed> $server
     */
    public static function origin(array $server)
    {
        $fromEnv = self::absoluteEnv('APP_PUBLIC_ORIGIN');
        if ($fromEnv === null) {
            $fromEnv = self::originFromAbsolute(self::envAbsolute('APP_BASE_URL_NEW'));
        }
        if ($fromEnv !== null) {
            return $fromEnv;
        }

        $scheme = TrustedProxy::isHttps($server) ? 'https' : 'http';
        $host = TrustedProxy::host($server);
        if ($host === '') {
            $host = 'localhost';
        }

        if (preg_match('/^(.+):(\d+)$/', $host, $m) === 1) {
            $hostOnly = $m[1];
            $headerPort = $m[2];
            $isDefault = ($scheme === 'https' && ($headerPort === '80' || $headerPort === '443'))
                || ($scheme === 'http' && $headerPort === '80');
            $host = $isDefault ? $hostOnly : $host;
        } elseif (
            !TrustedProxy::isTrusted($server)
            && isset($server['SERVER_PORT'])
        ) {
            $port = (string) $server['SERVER_PORT'];
            if ($port !== '' && $port !== '80' && $port !== '443' && strpos($host, ':') === false) {
                $host .= ':' . $port;
            }
        }

        return $scheme . '://' . $host;
    }

    /**
     * @param array<string, mixed> $server
     */
    public static function preferEnv($envName, $fallbackPath, array $server)
    {
        $absolute = self::envAbsolute($envName);
        if ($absolute !== null) {
            return rtrim($absolute, '/');
        }

        $path = AuthRuntime::env($envName, $fallbackPath);
        if ($path === '') {
            $path = $fallbackPath;
        }
        if (preg_match('#^https?://#i', $path) === 1) {
            return rtrim($path, '/');
        }

        $path = '/' . ltrim($path, '/');

        return rtrim(self::origin($server) . rtrim($path, '/'), '/');
    }

    public static function envAbsolute($name)
    {
        $value = trim(AuthRuntime::env($name, ''));
        if ($value === '' || preg_match('#^https?://#i', $value) !== 1) {
            return null;
        }

        return rtrim($value, '/');
    }

    private static function absoluteEnv($name)
    {
        return self::envAbsolute($name);
    }

    private static function originFromAbsolute($url)
    {
        if (!is_string($url) || $url === '') {
            return null;
        }

        $parts = parse_url($url);
        if (!is_array($parts) || empty($parts['scheme']) || empty($parts['host'])) {
            return null;
        }

        $scheme = strtolower((string) $parts['scheme']);
        $host = strtolower((string) $parts['host']);
        $port = isset($parts['port']) ? (int) $parts['port'] : ($scheme === 'https' ? 443 : 80);
        $default = ($scheme === 'https' && $port === 443) || ($scheme === 'http' && $port === 80);

        return $default ? $scheme . '://' . $host : $scheme . '://' . $host . ':' . $port;
    }
}
