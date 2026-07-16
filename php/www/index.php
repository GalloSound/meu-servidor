<?php
declare(strict_types=1);

$projects = [
    [
        'name' => 'APP',
        'description' => 'Backend do APP (versão atual)',
        'url' => '/app/',
    ],
    [
        'name' => 'APP NF',
        'description' => 'Emissão e gestão de notas fiscais',
        'url' => '/app_nf/',
    ],
    [
        'name' => 'GsFacil Front',
        'description' => 'Frontend PHP do ecossistema',
        'url' => '/gsfacilfront/public/',
    ],
    [
        'name' => 'Gallo Sound Site',
        'description' => 'Site institucional publico da empresa',
        'url' => '/gallosoundsite/',
    ],
];
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>meu-servidor — Projetos PHP</title>
    <style>
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            background: #f4f6f8;
            color: #1a1a2e;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 2rem;
        }
        .container {
            background: #fff;
            border-radius: 12px;
            box-shadow: 0 4px 24px rgba(0, 0, 0, 0.08);
            padding: 2.5rem;
            max-width: 520px;
            width: 100%;
        }
        h1 {
            font-size: 1.4rem;
            font-weight: 600;
            margin-bottom: 0.25rem;
        }
        .subtitle {
            color: #6b7280;
            font-size: 0.9rem;
            margin-bottom: 1.75rem;
        }
        ul { list-style: none; }
        li + li { margin-top: 0.75rem; }
        a {
            display: block;
            padding: 0.85rem 1rem;
            border: 1px solid #e5e7eb;
            border-radius: 8px;
            text-decoration: none;
            color: inherit;
            transition: border-color 0.15s, background 0.15s;
        }
        a:hover {
            border-color: #3b82f6;
            background: #eff6ff;
        }
        .project-name {
            font-weight: 600;
            font-size: 0.95rem;
        }
        .project-desc {
            color: #6b7280;
            font-size: 0.8rem;
            margin-top: 0.15rem;
        }
        footer {
            margin-top: 1.75rem;
            text-align: center;
            color: #9ca3af;
            font-size: 0.75rem;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>meu-servidor</h1>
        <p class="subtitle">Ambiente local de desenvolvimento PHP</p>
        <ul>
            <?php foreach ($projects as $project): ?>
            <li>
                <a href="<?= htmlspecialchars($project['url'], ENT_QUOTES, 'UTF-8') ?>">
                    <div class="project-name"><?= htmlspecialchars($project['name'], ENT_QUOTES, 'UTF-8') ?></div>
                    <div class="project-desc"><?= htmlspecialchars($project['description'], ENT_QUOTES, 'UTF-8') ?></div>
                </a>
            </li>
            <?php endforeach; ?>
        </ul>
        <footer>php_global &middot; porta 8082</footer>
    </div>
</body>
</html>
