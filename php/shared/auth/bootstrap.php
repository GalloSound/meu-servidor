<?php

declare(strict_types=1);

require_once __DIR__ . '/AuthRuntime.php';
require_once __DIR__ . '/PasswordHasher.php';
require_once __DIR__ . '/SessionIdentity.php';
require_once __DIR__ . '/TrustedProxy.php';
require_once __DIR__ . '/PublicUrl.php';
require_once __DIR__ . '/SharedSession.php';

AuthRuntime::applyErrorDisplay();
