<?php

declare(strict_types=1);

$authBootstrap = dirname(__DIR__) . '/auth/bootstrap.php';
if (is_file($authBootstrap)) {
    require_once $authBootstrap;
}

ini_set('display_errors', '0');
ini_set('display_startup_errors', '0');
ini_set('html_errors', '0');

require_once __DIR__ . '/ApiSessionGuard.php';

/**
 * Resolve o bootstrap a partir de um wrapper em public_html/{gcar,apicontacts}.
 */
function api_guard_bootstrap_from_wrapper(string $wrapperDir): string
{
    $candidates = [
        dirname($wrapperDir, 3) . '/shared/api-guard/bootstrap.php',
        '/var/www/html/shared/api-guard/bootstrap.php',
    ];

    foreach ($candidates as $path) {
        if (is_file($path)) {
            return $path;
        }
    }

    http_response_code(500);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode([
        'status' => 'error',
        'code' => 500,
        'message' => 'Guard indisponível.',
    ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}
