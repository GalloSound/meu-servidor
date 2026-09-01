<?php

declare(strict_types=1);

require dirname(__DIR__) . '/bootstrap.php';

final class SharedAuthTest
{
    private $passed = 0;
    private $failed = 0;

    /** @var list<string> */
    private $failures = array();

    public function run()
    {
        if (!in_array('sqlite', PDO::getAvailableDrivers(), true)) {
            fwrite(STDERR, "PDO SQLite ausente. Rode no container PHP:\n");
            fwrite(STDERR, "  docker exec php_global php /var/www/html/shared/auth/tests/run.php\n");
            return 2;
        }

        ob_start();

        $this->testLegacyPlaintextUpgradesOnce();
        $this->testMigratedHashLogin();
        $this->testWrongPasswordDoesNotUpgrade();
        $this->testMd5IsNotAcceptedAsPasswordAlgo();
        $this->testSessionContractCrossAccess();
        $this->testLogoutClearsIdentity();
        $this->testExpirationRejectsSession();
        $this->testCookieFlags();
        $this->testTrustedProxyIgnoresSpoofedHeaders();
        $this->testTrustedProxyHonorsNpm();
        $this->testPublicUrlPrefersEnv();
        $this->testProductionDisablesDisplayErrors();

        echo $this->passed . ' passed, ' . $this->failed . ' failed' . PHP_EOL;
        foreach ($this->failures as $failure) {
            echo 'FAIL: ' . $failure . PHP_EOL;
        }

        ob_end_flush();

        return $this->failed === 0 ? 0 : 1;
    }

    private function testLegacyPlaintextUpgradesOnce()
    {
        $plain = $this->secret('legacy');
        $pdo = $this->pdoWithUser(1, 'a@example.test', $plain);

        $row = $this->fetchUser($pdo, 1);
        $result = PasswordHasher::verifyAndUpgrade($pdo, 1, $row['senhaAdmin'], $plain);
        $after = $this->fetchUser($pdo, 1);

        $ok = !empty($result['ok'])
            && !empty($result['upgraded'])
            && PasswordHasher::looksLikePasswordHash($after['senhaAdmin'])
            && password_verify($plain, $after['senhaAdmin'])
            && strpos($after['senhaAdmin'], $plain) === false;

        $again = PasswordHasher::verifyAndUpgrade($pdo, 1, $after['senhaAdmin'], $plain);
        $ok = $ok && !empty($again['ok']) && empty($again['upgraded']);

        $this->assertTrue($ok, 'login legado: autentica uma vez e grava hash');
    }

    private function testMigratedHashLogin()
    {
        $plain = $this->secret('migrated');
        $hash = PasswordHasher::hash($plain);
        $pdo = $this->pdoWithUser(2, 'b@example.test', $hash);

        $row = $this->fetchUser($pdo, 2);
        $result = PasswordHasher::verifyAndUpgrade($pdo, 2, $row['senhaAdmin'], $plain);
        $after = $this->fetchUser($pdo, 2);

        $ok = !empty($result['ok'])
            && password_verify($plain, $after['senhaAdmin'])
            && $after['senhaAdmin'] === $hash;

        $this->assertTrue($ok, 'login migrado: password_verify sem reescrever plaintext');
    }

    private function testWrongPasswordDoesNotUpgrade()
    {
        $plain = $this->secret('right');
        $pdo = $this->pdoWithUser(3, 'c@example.test', $plain);

        $result = PasswordHasher::verifyAndUpgrade($pdo, 3, $plain, $this->secret('wrong'));
        $after = $this->fetchUser($pdo, 3);

        $ok = empty($result['ok']) && $after['senhaAdmin'] === $plain;
        $this->assertTrue($ok, 'senha errada não migra o hash');
    }

    private function testMd5IsNotAcceptedAsPasswordAlgo()
    {
        $plain = $this->secret('md5plain');
        $md5 = md5($plain);

        $this->assertTrue(
            PasswordHasher::looksLikePasswordHash($md5) === false
            && PasswordHasher::verify($plain, $md5) === false,
            'MD5 não autentica e não é tratado como hash de senha'
        );
    }

    private function testSessionContractCrossAccess()
    {
        $session = array(
            SessionIdentity::TOKEN_KEY => 'tok-shared',
            SessionIdentity::USER_ID_KEY => 42,
            SessionIdentity::EXPIRES_KEY => time() + 14400,
        );

        $frontOk = SessionIdentity::isAuthenticated($session)
            && SessionIdentity::token($session) === 'tok-shared';
        $legacyOk = SessionIdentity::userId($session) === 42;
        $sistemaNeedsToken = SessionIdentity::token($session) !== null;

        $ccUserOnly = array(SessionIdentity::USER_ID_KEY => 42);
        $ccUserRejected = SessionIdentity::isAuthenticated($ccUserOnly) === false;

        $this->assertTrue(
            $frontOk && $legacyOk && $sistemaNeedsToken && $ccUserRejected,
            'acesso cruzado: token compartilha; ccUser sozinho não autentica'
        );
    }

    private function testLogoutClearsIdentity()
    {
        $this->withCliSession(function () {
            SharedSession::establishLogin('tok-out', 9);
            $before = SessionIdentity::isAuthenticated($_SESSION);
            SharedSession::destroy();
            $afterActive = session_status() === PHP_SESSION_ACTIVE;
            $after = $afterActive ? SessionIdentity::isAuthenticated($_SESSION) : false;

            $this->assertTrue($before && $after === false, 'logout invalida a sessão');
        });
    }

    private function testExpirationRejectsSession()
    {
        $session = array(
            SessionIdentity::TOKEN_KEY => 'tok-exp',
            SessionIdentity::USER_ID_KEY => 1,
            SessionIdentity::EXPIRES_KEY => time() - 10,
        );

        $this->assertTrue(
            SessionIdentity::isExpired($session) && !SessionIdentity::isAuthenticated($session),
            'expiração de 4h recusa token antigo'
        );

        $this->withCliSession(function () {
            SharedSession::establishLogin('tok-exp2', 8);
            $_SESSION[SessionIdentity::EXPIRES_KEY] = time() - 1;
            SharedSession::start();
            $ok = !SessionIdentity::isAuthenticated($_SESSION);
            $this->assertTrue($ok, 'start() destrói sessão expirada');
        });
    }

    private function testCookieFlags()
    {
        $prevEnv = getenv('APP_ENV');
        putenv('APP_ENV=production');
        $_SERVER['HTTPS'] = 'on';
        $params = SharedSession::cookieParams();
        $ok = $params['path'] === '/'
            && $params['httponly'] === true
            && $params['secure'] === true
            && ($params['samesite'] === 'Lax' || $params['samesite'] === 'Strict')
            && (int) $params['lifetime'] === 14400;

        if ($prevEnv === false) {
            putenv('APP_ENV');
        } else {
            putenv('APP_ENV=' . $prevEnv);
        }
        unset($_SERVER['HTTPS']);

        $this->assertTrue($ok, 'cookie path=/ HttpOnly Secure SameSite e 4h');
    }

    private function testTrustedProxyIgnoresSpoofedHeaders()
    {
        $prev = getenv('TRUSTED_PROXY_CIDRS');
        $prevEnv = getenv('APP_ENV');
        putenv('TRUSTED_PROXY_CIDRS=172.18.0.0/16');
        putenv('APP_ENV=development');

        $ip = TrustedProxy::clientIp(array(
            'REMOTE_ADDR' => '203.0.113.9',
            'HTTP_X_FORWARDED_FOR' => '198.51.100.1',
            'HTTP_X_FORWARDED_PROTO' => 'https',
        ));
        $https = TrustedProxy::isHttps(array(
            'REMOTE_ADDR' => '203.0.113.9',
            'HTTP_X_FORWARDED_PROTO' => 'https',
            'HTTPS' => 'off',
        ));

        if ($prev === false) {
            putenv('TRUSTED_PROXY_CIDRS');
        } else {
            putenv('TRUSTED_PROXY_CIDRS=' . $prev);
        }
        if ($prevEnv === false) {
            putenv('APP_ENV');
        } else {
            putenv('APP_ENV=' . $prevEnv);
        }

        $this->assertTrue($ip === '203.0.113.9' && $https === false, 'X-Forwarded-* ignorado sem proxy confiável');
    }

    private function testTrustedProxyHonorsNpm()
    {
        $prev = getenv('TRUSTED_PROXY_CIDRS');
        $prevEnv = getenv('APP_ENV');
        putenv('TRUSTED_PROXY_CIDRS=172.18.0.0/16');
        putenv('APP_ENV=development');

        $ip = TrustedProxy::clientIp(array(
            'REMOTE_ADDR' => '172.18.0.4',
            'HTTP_X_FORWARDED_FOR' => '198.51.100.20, 172.18.0.4',
        ));
        $https = TrustedProxy::isHttps(array(
            'REMOTE_ADDR' => '172.18.0.4',
            'HTTP_X_FORWARDED_PROTO' => 'https',
        ));

        if ($prev === false) {
            putenv('TRUSTED_PROXY_CIDRS');
        } else {
            putenv('TRUSTED_PROXY_CIDRS=' . $prev);
        }
        if ($prevEnv === false) {
            putenv('APP_ENV');
        } else {
            putenv('APP_ENV=' . $prevEnv);
        }

        $this->assertTrue($ip === '198.51.100.20' && $https === true, 'NPM na rede confiável: usa X-Forwarded-*');
    }

    private function testPublicUrlPrefersEnv()
    {
        $prev = getenv('APP_BASE_URL_NEW');
        putenv('APP_BASE_URL_NEW=https://gsfacil.com.br/gsfacilfront/public/');

        $base = PublicUrl::preferEnv('APP_BASE_URL_NEW', '/gsfacilfront/public', array(
            'HTTP_HOST' => 'evil.example',
            'HTTP_X_FORWARDED_HOST' => 'evil.example',
            'REMOTE_ADDR' => '203.0.113.9',
        ));

        if ($prev === false) {
            putenv('APP_BASE_URL_NEW');
        } else {
            putenv('APP_BASE_URL_NEW=' . $prev);
        }

        $this->assertTrue($base === 'https://gsfacil.com.br/gsfacilfront/public', 'URL pública fixa via env');
    }

    private function testProductionDisablesDisplayErrors()
    {
        $prev = getenv('APP_ENV');
        putenv('APP_ENV=production');
        AuthRuntime::applyErrorDisplay();
        $off = ini_get('display_errors');
        $ok = $off === '0' || $off === '' || strtolower((string) $off) === 'off';

        if ($prev === false) {
            putenv('APP_ENV');
        } else {
            putenv('APP_ENV=' . $prev);
        }
        AuthRuntime::applyErrorDisplay();

        $this->assertTrue($ok, 'display_errors desligado em produção');
    }

    private function pdoWithUser($id, $email, $senha)
    {
        $pdo = new PDO('sqlite::memory:');
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->exec('CREATE TABLE gs_Administrador (
            idAdmin INTEGER PRIMARY KEY,
            emailAdmin TEXT,
            senhaAdmin TEXT,
            token TEXT,
            status INTEGER
        )');
        $sql = $pdo->prepare('INSERT INTO gs_Administrador (idAdmin, emailAdmin, senhaAdmin, token, status)
            VALUES (:id, :email, :senha, :token, 1)');
        $sql->bindValue(':id', $id, PDO::PARAM_INT);
        $sql->bindValue(':email', $email);
        $sql->bindValue(':senha', $senha);
        $sql->bindValue(':token', '');
        $sql->execute();

        return $pdo;
    }

    private function fetchUser(PDO $pdo, $id)
    {
        $sql = $pdo->prepare('SELECT * FROM gs_Administrador WHERE idAdmin = :id');
        $sql->bindValue(':id', $id, PDO::PARAM_INT);
        $sql->execute();
        $row = $sql->fetch(PDO::FETCH_ASSOC);

        return is_array($row) ? $row : array();
    }

    private function secret($label)
    {
        return $label . '-' . bin2hex(random_bytes(6));
    }

    private function withCliSession(callable $fn)
    {
        if (session_status() === PHP_SESSION_ACTIVE) {
            session_write_close();
        }

        $prevCookies = ini_get('session.use_cookies');
        ini_set('session.use_cookies', '0');
        session_id(bin2hex(random_bytes(8)));
        $_SESSION = array();
        try {
            $fn();
        } finally {
            if (session_status() === PHP_SESSION_ACTIVE) {
                $_SESSION = array();
                session_destroy();
            }
            $_SESSION = array();
            ini_set('session.use_cookies', (string) $prevCookies);
        }
    }

    private function assertTrue($ok, $label)
    {
        if ($ok) {
            $this->passed++;
            echo 'PASS ' . $label . PHP_EOL;
            return;
        }
        $this->fail($label, 'asserção falsa');
    }

    private function fail($label, $detail)
    {
        $this->failed++;
        $this->failures[] = $label . ' — ' . $detail;
        echo 'FAIL ' . $label . PHP_EOL;
    }
}

exit((new SharedAuthTest())->run());
