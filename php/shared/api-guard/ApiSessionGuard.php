<?php

declare(strict_types=1);

final class ApiAuthDenied extends RuntimeException
{
    public function __construct(
        public readonly int $httpStatus,
        string $message,
        public readonly string $reason
    ) {
        parent::__construct($message);
    }
}

/**
 * Guard de sessão/tenant/CSRF para /gcar e /apicontacts.
 *
 * Contrato de sessão (gsfacilFront):
 * - cookie PHPSESSID compartilhado no runtime PHP
 * - $_SESSION['token'] = token do gs_Administrador
 * - empresa e usuário resolvidos no servidor (SELECT empresa_id WHERE token = ?);
 *   o body do browser nunca é fonte de verdade do tenant
 */
final class ApiSessionGuard
{
    public const ACTION_CALENDAR_CREATE = 'calendar.create';
    public const ACTION_CALENDAR_EDIT = 'calendar.edit';
    public const ACTION_CALENDAR_DELETE = 'calendar.delete';
    public const ACTION_CONTACTS_CREATE = 'contacts.create';
    public const ACTION_CONTACTS_EDIT = 'contacts.edit';
    public const ACTION_CALENDAR_OAUTH = 'calendar.oauth';

    public const CSRF_SESSION_KEY = 'csrf_token';
    public const CSRF_HEADER = 'X-CSRF-Token';

    /**
     * Perfis já usados no frontend para as telas que disparam estas APIs.
     * Qualquer um dos slugs autoriza a ação (OR).
     *
     * @var array<string, list<string>>
     */
    private const ACTION_SLUGS = [
        self::ACTION_CALENDAR_CREATE => ['visualizar_orcamentos', 'visualizar_veiculos_clientes'],
        self::ACTION_CALENDAR_EDIT => ['visualizar_orcamentos', 'visualizar_veiculos_clientes'],
        self::ACTION_CALENDAR_DELETE => ['visualizar_orcamentos', 'visualizar_veiculos_clientes'],
        self::ACTION_CONTACTS_CREATE => ['visualizar_veiculos_clientes', 'visualizar_orcamentos'],
        self::ACTION_CONTACTS_EDIT => ['visualizar_veiculos_clientes', 'visualizar_orcamentos'],
        self::ACTION_CALENDAR_OAUTH => ['desenvolvedor_piloto'],
    ];

    /** @var array<string, mixed> */
    private array $server;

    /** @var array<string, mixed> */
    private array $post;

    /** @var array<string, mixed> */
    private array $session;

    /** @var array<string, string> */
    private array $headers;

    private string $rawInput;

    private bool $exitOnDeny;

    private bool $sessionBound;

    public function __construct(
        private ?PDO $pdo = null,
        ?array $server = null,
        ?array $post = null,
        ?array $session = null,
        ?array $headers = null,
        ?string $rawInput = null,
        bool $exitOnDeny = true
    ) {
        $this->server = $server ?? $_SERVER;
        $this->post = $post ?? $_POST;
        $this->headers = $this->normalizeHeaders($headers ?? $this->headersFromServer($this->server));
        $this->rawInput = $rawInput ?? self::cachedRawInput();
        $this->exitOnDeny = $exitOnDeny;

        if ($session !== null) {
            $this->session = $session;
            $this->sessionBound = false;
        } else {
            $this->session = [];
            $this->sessionBound = true;
        }
    }

    /**
     * @return array{userId:int,empresaId:int,groupId:int,permissions:list<string>,csrfToken:string}
     */
    public static function protect(string $action, array $options = []): array
    {
        $guard = new self(
            $options['pdo'] ?? null,
            $options['server'] ?? null,
            $options['post'] ?? null,
            $options['session'] ?? null,
            $options['headers'] ?? null,
            $options['rawInput'] ?? null,
            $options['exitOnDeny'] ?? true
        );

        return $guard->assert($action);
    }

    public static function cachedRawInput(): string
    {
        if (!isset($GLOBALS['API_GUARD_RAW_INPUT']) || !is_string($GLOBALS['API_GUARD_RAW_INPUT'])) {
            $raw = file_get_contents('php://input');
            $GLOBALS['API_GUARD_RAW_INPUT'] = ($raw === false) ? '' : $raw;
        }

        return $GLOBALS['API_GUARD_RAW_INPUT'];
    }

    public static function ensureCsrfToken(): string
    {
        if (session_status() !== PHP_SESSION_ACTIVE) {
            return '';
        }

        $current = $_SESSION[self::CSRF_SESSION_KEY] ?? '';
        if (!is_string($current) || $current === '' || strlen($current) < 32) {
            $_SESSION[self::CSRF_SESSION_KEY] = bin2hex(random_bytes(32));
        }

        return (string) $_SESSION[self::CSRF_SESSION_KEY];
    }

    /**
     * @return array{userId:int,empresaId:int,groupId:int,permissions:list<string>,csrfToken:string}
     */
    public function assert(string $action): array
    {
        $this->disableErrorDisplay();

        try {
            $this->enforceSameOriginCors();

            $method = strtoupper((string) ($this->server['REQUEST_METHOD'] ?? 'GET'));
            if ($method === 'OPTIONS') {
                $this->finishOptions();
            }

            $this->startSessionIfNeeded();
            $identity = $this->resolveIdentity();
            $this->enforceCsrf($method);
            $this->enforceTenant($identity);
            $this->enforcePermission($action, $identity);

            $csrf = $this->sessionCsrf();
            if ($csrf === '') {
                $csrf = bin2hex(random_bytes(32));
                $this->writeSession(self::CSRF_SESSION_KEY, $csrf);
            }

            $this->audit('allow', $action, 200, $identity['userId'], $identity['empresaId']);

            $context = [
                'userId' => $identity['userId'],
                'empresaId' => $identity['empresaId'],
                'groupId' => $identity['groupId'],
                'permissions' => $identity['permissions'],
                'csrfToken' => $csrf,
            ];

            $GLOBALS['apiAuth'] = $context;

            return $context;
        } catch (ApiAuthDenied $e) {
            $this->audit(
                'deny',
                $action,
                $e->httpStatus,
                $this->safeInt($this->sessionValue('resolved_user_id') ?? 0) ?: null,
                $this->safeInt($this->sessionValue('resolved_empresa_id') ?? 0) ?: null,
                $e->reason
            );
            $this->deny($e->httpStatus, $e->getMessage(), $e->reason);
        } catch (Throwable $e) {
            error_log('api-guard: ' . $e->getMessage());
            $this->audit('deny', $action, 500, null, null, 'error');
            $this->deny(500, 'Falha interna.', 'error');
        }

        throw new RuntimeException('Guard interrompido.');
    }

    private function disableErrorDisplay(): void
    {
        ini_set('display_errors', '0');
        ini_set('display_startup_errors', '0');
        ini_set('html_errors', '0');
    }

    private function enforceSameOriginCors(): void
    {
        $origin = trim((string) ($this->server['HTTP_ORIGIN'] ?? ''));
        if ($origin === '') {
            return;
        }

        $self = $this->currentOrigin();
        if ($self !== '' && $this->originsMatch($origin, $self)) {
            return;
        }

        throw new ApiAuthDenied(403, 'Origem não permitida.', 'cors');
    }

    private function finishOptions(): never
    {
        if ($this->exitOnDeny) {
            http_response_code(204);
            header('Content-Type: application/json; charset=utf-8');
            header('X-Content-Type-Options: nosniff');
            header('Vary: Origin');
            exit;
        }

        throw new ApiAuthDenied(204, 'OPTIONS same-origin.', 'options');
    }

    private function startSessionIfNeeded(): void
    {
        if (!$this->sessionBound) {
            return;
        }

        if (session_status() === PHP_SESSION_NONE) {
            if (class_exists('SharedSession')) {
                SharedSession::start();
            } else {
                session_set_cookie_params(14400);
                session_start();
            }
        }

        $this->session = $_SESSION;
    }

    /**
     * @return array{userId:int,empresaId:int,groupId:int,permissions:list<string>,ipFixo:?string}
     */
    private function resolveIdentity(): array
    {
        $token = class_exists('SessionIdentity')
            ? SessionIdentity::token($this->session)
            : (isset($this->session['token']) && is_string($this->session['token']) ? trim($this->session['token']) : '');
        if ($token === null || $token === '') {
            throw new ApiAuthDenied(401, 'Não autenticado.', 'unauthenticated');
        }

        $pdo = $this->pdo();
        // Tenant = gs_Administrador.empresa_id do token na sessão. Sem default 1: token inválido → 401.
        $sql = $pdo->prepare(
            'SELECT
                gs_Administrador.idAdmin,
                gs_Administrador.group_id,
                gs_Administrador.empresa_id,
                empresasUsuarias.ipFixo
             FROM gs_Administrador
             INNER JOIN empresasUsuarias
                ON empresasUsuarias.idEmpresa = gs_Administrador.empresa_id
             WHERE token = :token AND gs_Administrador.status = 1'
        );
        $sql->bindValue(':token', $token);
        $sql->execute();
        $row = $sql->fetch(PDO::FETCH_ASSOC);

        if (!is_array($row)) {
            throw new ApiAuthDenied(401, 'Não autenticado.', 'unauthenticated');
        }

        $userId = $this->safeInt($row['idAdmin'] ?? null);
        $empresaId = $this->safeInt($row['empresa_id'] ?? null);
        $groupId = $this->safeInt($row['group_id'] ?? null);

        if ($userId === null || $empresaId === null || $groupId === null) {
            throw new ApiAuthDenied(401, 'Não autenticado.', 'unauthenticated');
        }

        $permissions = $this->loadPermissions($groupId, $empresaId);
        $this->writeSession('resolved_user_id', $userId);
        $this->writeSession('resolved_empresa_id', $empresaId);

        $identity = [
            'userId' => $userId,
            'empresaId' => $empresaId,
            'groupId' => $groupId,
            'permissions' => $permissions,
            'ipFixo' => isset($row['ipFixo']) ? (string) $row['ipFixo'] : null,
        ];

        if (!in_array('external_access', $permissions, true)) {
            $remote = class_exists('TrustedProxy')
                ? TrustedProxy::clientIp($this->server)
                : (string) ($this->server['REMOTE_ADDR'] ?? '');
            if ($identity['ipFixo'] === null || $remote === '' || !hash_equals($identity['ipFixo'], $remote)) {
                throw new ApiAuthDenied(403, 'Sem permissão para esta ação.', 'forbidden');
            }
        }

        return $identity;
    }

    /**
     * @return list<string>
     */
    private function loadPermissions(int $groupId, int $empresaId): array
    {
        $pdo = $this->pdo();

        if ($empresaId === 1) {
            $sql = $pdo->prepare(
                'SELECT id_permission_item FROM permission_links WHERE id_permission_group = :group_id'
            );
        } else {
            $sql = $pdo->prepare(
                'SELECT id_permission_item FROM permission_links
                 WHERE id_permission_group = :group_id AND empresaID = 1'
            );
        }

        $sql->bindValue(':group_id', $groupId, PDO::PARAM_INT);
        $sql->execute();
        $ids = [];
        foreach ($sql->fetchAll(PDO::FETCH_ASSOC) as $item) {
            $id = $this->safeInt($item['id_permission_item'] ?? null);
            if ($id !== null) {
                $ids[] = $id;
            }
        }

        if ($ids === []) {
            return [];
        }

        $placeholders = implode(',', array_fill(0, count($ids), '?'));
        $slugSql = $pdo->prepare('SELECT slug FROM permission_itens WHERE id IN (' . $placeholders . ')');
        foreach ($ids as $index => $id) {
            $slugSql->bindValue($index + 1, $id, PDO::PARAM_INT);
        }
        $slugSql->execute();

        $slugs = [];
        foreach ($slugSql->fetchAll(PDO::FETCH_ASSOC) as $item) {
            $slug = trim((string) ($item['slug'] ?? ''));
            if ($slug !== '') {
                $slugs[] = $slug;
            }
        }

        return $slugs;
    }

    private function enforceCsrf(string $method): void
    {
        if (in_array($method, ['GET', 'HEAD', 'OPTIONS'], true)) {
            return;
        }

        $expected = $this->sessionCsrf();
        if ($expected === '') {
            throw new ApiAuthDenied(403, 'CSRF inválido.', 'csrf');
        }

        $provided = $this->providedCsrf();
        if ($provided === '' || !hash_equals($expected, $provided)) {
            throw new ApiAuthDenied(403, 'CSRF inválido.', 'csrf');
        }
    }

    /**
     * Se o body disser que a empresa/usuário é outro, recusa.
     * Ausência de empresaID no POST é ok: o Node resolve a empresa pelo token.
     * O campo "user" do insertdiv (colaborador da retirada) NÃO entra nesta lista.
     *
     * @param array{userId:int,empresaId:int,groupId:int,permissions:list<string>,ipFixo:?string} $identity
     */
    private function enforceTenant(array $identity): void
    {
        $claimedEmpresa = $this->claimedInt(['empresaID', 'empresa_id', 'id_company']);
        if ($claimedEmpresa !== null && $claimedEmpresa !== $identity['empresaId']) {
            throw new ApiAuthDenied(403, 'Empresa divergente da sessão.', 'tenant');
        }

        $claimedUser = $this->claimedInt(['userID', 'userId', 'idAdmin', 'id_usuario']);
        if ($claimedUser !== null && $claimedUser !== $identity['userId']) {
            throw new ApiAuthDenied(403, 'Usuário divergente da sessão.', 'tenant');
        }
    }

    /**
     * @param array{userId:int,empresaId:int,groupId:int,permissions:list<string>,ipFixo:?string} $identity
     */
    private function enforcePermission(string $action, array $identity): void
    {
        $required = self::ACTION_SLUGS[$action] ?? null;
        if ($required === null) {
            throw new ApiAuthDenied(403, 'Sem permissão para esta ação.', 'forbidden');
        }

        foreach ($required as $slug) {
            if (in_array($slug, $identity['permissions'], true)) {
                return;
            }
        }

        throw new ApiAuthDenied(403, 'Sem permissão para esta ação.', 'forbidden');
    }

    private function providedCsrf(): string
    {
        $headerNames = [
            'x-csrf-token',
            'x-csrftoken',
            strtolower(self::CSRF_HEADER),
        ];
        foreach ($headerNames as $name) {
            if (isset($this->headers[$name]) && is_string($this->headers[$name]) && $this->headers[$name] !== '') {
                return $this->headers[$name];
            }
        }

        $fromPost = $this->post['csrf_token'] ?? $this->post['_csrf'] ?? '';
        if (is_string($fromPost) && $fromPost !== '') {
            return $fromPost;
        }

        $body = $this->parsedBody();
        $fromBody = $body['csrf_token'] ?? $body['_csrf'] ?? '';

        return is_string($fromBody) ? $fromBody : '';
    }

    /**
     * @param list<string> $keys
     */
    private function claimedInt(array $keys): ?int
    {
        $sources = [$this->post, $this->parsedBody()];
        foreach ($sources as $source) {
            foreach ($keys as $key) {
                if (!array_key_exists($key, $source)) {
                    continue;
                }
                $value = $this->safeInt($source[$key]);
                if ($value !== null) {
                    return $value;
                }
            }
        }

        return null;
    }

    /**
     * @return array<string, mixed>
     */
    private function parsedBody(): array
    {
        $raw = trim($this->rawInput);
        if ($raw === '') {
            return [];
        }

        $contentType = strtolower((string) ($this->server['CONTENT_TYPE'] ?? $this->headers['content-type'] ?? ''));
        if (str_contains($contentType, 'application/json')) {
            try {
                $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
            } catch (JsonException) {
                return [];
            }

            return is_array($decoded) ? $decoded : [];
        }

        $parsed = [];
        parse_str($raw, $parsed);

        return is_array($parsed) ? $parsed : [];
    }

    private function sessionCsrf(): string
    {
        $token = $this->session[self::CSRF_SESSION_KEY] ?? '';

        return is_string($token) ? $token : '';
    }

    private function sessionValue(string $key): mixed
    {
        return $this->session[$key] ?? null;
    }

    private function writeSession(string $key, mixed $value): void
    {
        $this->session[$key] = $value;
        if ($this->sessionBound && session_status() === PHP_SESSION_ACTIVE) {
            $_SESSION[$key] = $value;
        }
    }

    private function pdo(): PDO
    {
        if ($this->pdo instanceof PDO) {
            return $this->pdo;
        }

        $host = getenv('DB_HOST');
        $database = getenv('DB_DATABASE');
        $user = getenv('DB_USER');
        $pass = getenv('DB_PASS');

        if ($host === false || $database === false || $user === false || $pass === false
            || trim((string) $host) === '' || trim((string) $database) === '') {
            throw new RuntimeException('Configuração de banco ausente para o guard.');
        }

        $this->pdo = new PDO(
            'mysql:dbname=' . $database . ';host=' . $host . ';charset=utf8mb4',
            (string) $user,
            (string) $pass,
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]
        );

        return $this->pdo;
    }

    private function currentOrigin(): string
    {
        if (class_exists('PublicUrl')) {
            return PublicUrl::origin($this->server);
        }

        $https = strtolower((string) ($this->server['HTTPS'] ?? ''));
        $scheme = ($https === 'on' || $https === '1') ? 'https' : 'http';
        $host = trim((string) ($this->server['HTTP_HOST'] ?? $this->server['SERVER_NAME'] ?? ''));
        if ($host === '') {
            return '';
        }

        return $scheme . '://' . $host;
    }

    private function originsMatch(string $a, string $b): bool
    {
        $na = $this->normalizeOrigin($a);
        $nb = $this->normalizeOrigin($b);

        return $na !== '' && $nb !== '' && hash_equals($na, $nb);
    }

    private function normalizeOrigin(string $origin): string
    {
        $parts = parse_url($origin);
        if (!is_array($parts) || empty($parts['scheme']) || empty($parts['host'])) {
            return '';
        }

        $scheme = strtolower((string) $parts['scheme']);
        $host = strtolower((string) $parts['host']);
        $port = isset($parts['port']) ? (int) $parts['port'] : ($scheme === 'https' ? 443 : 80);
        $default = ($scheme === 'https' && $port === 443) || ($scheme === 'http' && $port === 80);

        return $default ? $scheme . '://' . $host : $scheme . '://' . $host . ':' . $port;
    }

    /**
     * @param array<string, mixed>|null $headers
     * @return array<string, string>
     */
    private function normalizeHeaders(?array $headers): array
    {
        $normalized = [];
        foreach ($headers ?? [] as $name => $value) {
            if (!is_string($name) || !is_string($value)) {
                continue;
            }
            $normalized[strtolower($name)] = $value;
        }

        return $normalized;
    }

    /**
     * @param array<string, mixed> $server
     * @return array<string, string>
     */
    private function headersFromServer(array $server): array
    {
        $headers = [];
        foreach ($server as $key => $value) {
            if (!is_string($key) || !is_string($value)) {
                continue;
            }
            if (str_starts_with($key, 'HTTP_')) {
                $name = strtolower(str_replace('_', '-', substr($key, 5)));
                $headers[$name] = $value;
            }
        }

        if (isset($server['CONTENT_TYPE']) && is_string($server['CONTENT_TYPE'])) {
            $headers['content-type'] = $server['CONTENT_TYPE'];
        }

        if (function_exists('getallheaders')) {
            $all = getallheaders();
            if (is_array($all)) {
                foreach ($all as $name => $value) {
                    if (is_string($name) && is_string($value)) {
                        $headers[strtolower($name)] = $value;
                    }
                }
            }
        }

        return $headers;
    }

    private function safeInt(mixed $value): ?int
    {
        if (is_int($value)) {
            return $value > 0 ? $value : null;
        }
        if (is_string($value) && preg_match('/^[1-9][0-9]*$/', $value) === 1) {
            return (int) $value;
        }

        return null;
    }

    private function audit(
        string $result,
        string $action,
        int $status,
        ?int $userId,
        ?int $empresaId,
        ?string $reason = null
    ): void {
        $path = parse_url((string) ($this->server['REQUEST_URI'] ?? ''), PHP_URL_PATH);
        $entry = [
            'event' => 'api-guard',
            'result' => $result,
            'action' => $action,
            'status' => $status,
            'reason' => $reason,
            'method' => strtoupper((string) ($this->server['REQUEST_METHOD'] ?? '')),
            'path' => is_string($path) ? $path : '',
            'userId' => $userId,
            'empresaId' => $empresaId,
        ];

        error_log(json_encode($entry, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?: 'api-guard: log-fail');
    }

    private function deny(int $status, string $message, string $reason): never
    {
        if ($this->exitOnDeny) {
            if (!headers_sent()) {
                http_response_code($status === 204 ? 204 : $status);
                header('Content-Type: application/json; charset=utf-8');
                header('X-Content-Type-Options: nosniff');
                header('Cache-Control: no-store');
                header('Vary: Origin');
            }

            if ($status !== 204) {
                echo json_encode([
                    'status' => 'error',
                    'code' => $status,
                    'message' => $message,
                    'reason' => $reason,
                ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            }

            exit;
        }

        throw new ApiAuthDenied($status, $message, $reason);
    }
}
