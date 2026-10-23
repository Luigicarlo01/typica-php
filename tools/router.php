<?php
declare(strict_types=1);

// Exclusivo do teste local com php -S. A publicação usa Apache e .htaccess.
$root = realpath((string) getenv('TYPICA_WEB_ROOT'));
$base = (string) getenv('TYPICA_BASE_PATH');
$url = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$url = is_string($url) ? rawurldecode($url) : '';
if ($root === false || strpos($url, $base) !== 0) {
    http_response_code(404);
    exit;
}
$relative = substr($url, strlen($base));
if ($relative === '') {
    $relative = 'index.html';
}
foreach (explode('/', $relative) as $part) {
    if ($part === '..' || strpos($part, '.') === 0 || strpos($part, '_') === 0 || strpos($part, "\0") !== false) {
        http_response_code(404);
        exit;
    }
}
$path = realpath($root . '/' . $relative);
if ($path === false || !is_file($path) || strpos($path, $root . DIRECTORY_SEPARATOR) !== 0) {
    http_response_code(404);
    exit;
}
if (!in_array($_SERVER['REQUEST_METHOD'], ['GET', 'HEAD'], true) && substr($relative, -4) !== '.php') {
    header('Allow: GET, HEAD');
    http_response_code(405);
    exit;
}
if (substr($relative, -4) === '.php') {
    require $path;
    exit;
}
$types = ['html' => 'text/html; charset=utf-8', 'js' => 'application/javascript', 'mjs' => 'application/javascript',
    'json' => 'application/json', 'wasm' => 'application/wasm', 'css' => 'text/css', 'svg' => 'image/svg+xml',
    'png' => 'image/png', 'ico' => 'image/x-icon', 'ttf' => 'font/ttf', 'otf' => 'font/otf',
    'woff' => 'font/woff', 'woff2' => 'font/woff2', 'gz' => 'application/gzip', 'bin' => 'application/octet-stream'];
header('Content-Type: ' . ($types[strtolower(pathinfo($path, PATHINFO_EXTENSION))] ?? 'application/octet-stream'));
header('Cache-Control: no-cache');
header('Content-Length: ' . filesize($path));
if ($_SERVER['REQUEST_METHOD'] !== 'HEAD') {
    readfile($path);
}
