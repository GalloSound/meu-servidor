<?php

declare(strict_types=1);

final class AuthRuntime
{
    public static function env($name, $default = '')
    {
        $candidates = array(
            getenv($name),
            isset($_SERVER[$name]) ? $_SERVER[$name] : null,
            isset($_ENV[$name]) ? $_ENV[$name] : null,
        );

        foreach ($candidates as $value) {
            if (is_string($value) && $value !== '') {
                return $value;
            }
        }

        return $default;
    }

    public static function isProduction()
    {
        $env = strtolower(trim(self::env('APP_ENV', 'development')));

        return $env === 'production' || $env === 'on-line' || $env === 'online';
    }

    public static function applyErrorDisplay()
    {
        if (self::isProduction()) {
            ini_set('display_errors', '0');
            ini_set('display_startup_errors', '0');
            ini_set('html_errors', '0');
            ini_set('log_errors', '1');
            error_reporting(E_ALL);

            return;
        }

        ini_set('display_errors', '1');
        ini_set('display_startup_errors', '0');
        ini_set('html_errors', '0');
        ini_set('log_errors', '1');
        error_reporting(E_ALL);
    }

    public static function sessionLifetime()
    {
        $raw = self::env('SESSION_LIFETIME', '14400');
        if (preg_match('/^[1-9][0-9]*$/', $raw) !== 1) {
            return 14400;
        }

        $seconds = (int) $raw;

        return $seconds > 0 ? $seconds : 14400;
    }

    public static function sessionSameSite()
    {
        $value = strtolower(self::env('SESSION_SAMESITE', 'Lax'));
        if ($value === 'strict') {
            return 'Strict';
        }

        return 'Lax';
    }
}
