<?php

declare(strict_types=1);

/**
 * Contrato de sessão compartilhado: gsfacilFront e app_sistema.
 *
 * - token: gs_Administrador.token (fonte de verdade do login)
 * - ccUser: idAdmin (alias legado; isLogged continua exigindo token)
 */
final class SessionIdentity
{
    const TOKEN_KEY = 'token';
    const USER_ID_KEY = 'ccUser';
    const EXPIRES_KEY = 'auth_expires_at';
    const CSRF_KEY = 'csrf_token';

    /**
     * @param array<string, mixed> $session
     * @return string|null
     */
    public static function token(array $session)
    {
        if (!isset($session[self::TOKEN_KEY]) || !is_string($session[self::TOKEN_KEY])) {
            return null;
        }

        $token = trim($session[self::TOKEN_KEY]);

        return $token !== '' ? $token : null;
    }

    /**
     * @param array<string, mixed> $session
     * @return int|null
     */
    public static function userId(array $session)
    {
        if (!isset($session[self::USER_ID_KEY])) {
            return null;
        }

        $raw = $session[self::USER_ID_KEY];
        if (is_int($raw) && $raw > 0) {
            return $raw;
        }
        if (is_string($raw) && preg_match('/^[1-9][0-9]*$/', $raw) === 1) {
            return (int) $raw;
        }

        return null;
    }

    /**
     * @param array<string, mixed> $session
     * @param int|null $now
     */
    public static function isAuthenticated(array $session, $now = null)
    {
        if (self::token($session) === null) {
            return false;
        }

        $now = $now === null ? time() : (int) $now;
        if (!isset($session[self::EXPIRES_KEY])) {
            return true;
        }

        $expires = (int) $session[self::EXPIRES_KEY];

        return $expires >= $now;
    }

    /**
     * @param array<string, mixed> $session
     * @param int|null $now
     */
    public static function isExpired(array $session, $now = null)
    {
        if (self::token($session) === null) {
            return false;
        }

        $now = $now === null ? time() : (int) $now;
        if (!isset($session[self::EXPIRES_KEY])) {
            return false;
        }

        return (int) $session[self::EXPIRES_KEY] < $now;
    }
}
