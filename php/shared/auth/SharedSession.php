<?php

declare(strict_types=1);

/**
 * Cookie path=/, HttpOnly, Secure em HTTPS/produção, SameSite Lax|Strict.
 * Regenera o ID no login e invalida no logout. Duração padrão: 4 horas.
 */
final class SharedSession
{
    /**
     * @return array<string, mixed>
     */
    public static function cookieParams()
    {
        $https = TrustedProxy::isHttps($_SERVER);
        $sameSite = AuthRuntime::sessionSameSite();

        return array(
            'lifetime' => AuthRuntime::sessionLifetime(),
            'path' => '/',
            'domain' => '',
            'secure' => $https,
            'httponly' => true,
            'samesite' => $sameSite,
        );
    }

    public static function start()
    {
        AuthRuntime::applyErrorDisplay();

        if (session_status() === PHP_SESSION_NONE) {
            self::applyIni();
            session_start();
        }

        $session = (isset($_SESSION) && is_array($_SESSION)) ? $_SESSION : array();
        if (SessionIdentity::isExpired($session)) {
            self::destroy();
            if (session_status() === PHP_SESSION_NONE) {
                self::applyIni();
                session_start();
            }
        }

        self::ensureCsrfToken();
    }

    private static function applyIni()
    {
        $lifetime = AuthRuntime::sessionLifetime();
        ini_set('session.gc_maxlifetime', (string) $lifetime);
        ini_set('session.cookie_lifetime', (string) $lifetime);
        ini_set('session.use_strict_mode', '1');
        ini_set('session.use_only_cookies', '1');
        ini_set('session.cookie_httponly', '1');
        ini_set('session.cookie_path', '/');
        ini_set('session.cookie_samesite', AuthRuntime::sessionSameSite());

        if (ini_get('session.use_cookies')) {
            session_set_cookie_params(self::cookieParams());
        }
    }

    /**
     * @param string $token
     * @param int $userId
     */
    public static function establishLogin($token, $userId)
    {
        $token = is_string($token) ? trim($token) : '';
        $userId = (int) $userId;
        if ($token === '' || $userId < 1) {
            throw new InvalidArgumentException('Sessão de login inválida.');
        }

        if (session_status() !== PHP_SESSION_ACTIVE) {
            self::start();
        }

        session_regenerate_id(true);

        $_SESSION[SessionIdentity::TOKEN_KEY] = $token;
        $_SESSION[SessionIdentity::USER_ID_KEY] = $userId;
        $_SESSION[SessionIdentity::EXPIRES_KEY] = time() + AuthRuntime::sessionLifetime();
        $_SESSION[SessionIdentity::CSRF_KEY] = bin2hex(random_bytes(32));
        unset($_SESSION['flash'], $_SESSION['erroLogin']);
    }

    public static function destroy()
    {
        if (session_status() === PHP_SESSION_NONE) {
            self::applyIni();
            session_start();
        }

        $_SESSION = array();

        if (session_status() === PHP_SESSION_ACTIVE) {
            if (ini_get('session.use_cookies')) {
                $params = session_get_cookie_params();
                $options = array(
                    'expires' => time() - 42000,
                    'path' => isset($params['path']) ? $params['path'] : '/',
                    'domain' => isset($params['domain']) ? $params['domain'] : '',
                    'secure' => !empty($params['secure']),
                    'httponly' => !empty($params['httponly']),
                    'samesite' => !empty($params['samesite']) ? $params['samesite'] : AuthRuntime::sessionSameSite(),
                );
                setcookie(session_name(), '', $options);
            }

            session_destroy();
        }
    }

    public static function ensureCsrfToken()
    {
        if (session_status() !== PHP_SESSION_ACTIVE) {
            return '';
        }

        $current = isset($_SESSION[SessionIdentity::CSRF_KEY]) ? $_SESSION[SessionIdentity::CSRF_KEY] : '';
        if (!is_string($current) || strlen($current) < 32) {
            $_SESSION[SessionIdentity::CSRF_KEY] = bin2hex(random_bytes(32));
        }

        return (string) $_SESSION[SessionIdentity::CSRF_KEY];
    }

    public static function token()
    {
        if (session_status() !== PHP_SESSION_ACTIVE) {
            return null;
        }

        return SessionIdentity::token($_SESSION);
    }
}
