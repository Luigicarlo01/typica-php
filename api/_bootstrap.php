<?php
declare(strict_types=1);

// Somente leitura: o PHP não precisa de credenciais nem de permissões de escrita.
ini_set('display_errors', '0');
ini_set('zlib.output_compression', '0');

const TYPICA_ROOT = __DIR__ . '/..';

function typica_json(array $value, int $status = 200): void
{
    $body = json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR) . "\n";
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    header('Content-Length: ' . strlen($body));
    if ($_SERVER['REQUEST_METHOD'] !== 'HEAD') {
        echo $body;
    }
}

function typica_fail(int $status, string $message): void
{
    typica_json(['error' => $message], $status);
    exit;
}

function typica_run(callable $action): void
{
    if (!in_array($_SERVER['REQUEST_METHOD'], ['GET', 'HEAD'], true)) {
        header('Allow: GET, HEAD');
        typica_fail(405, 'Método não permitido.');
    }
    try {
        $action();
    } catch (Throwable $error) {
        error_log('Typica API: ' . $error->getMessage());
        typica_fail(503, 'Publicação incompleta ou indisponível. Tente novamente mais tarde.');
    }
}

function typica_read_json(string $path): array
{
    $raw = file_get_contents($path);
    if ($raw === false) {
        throw new RuntimeException('Arquivo de publicação ausente.');
    }
    $value = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
    if (!is_array($value)) {
        throw new RuntimeException('Arquivo JSON incompatível.');
    }
    return $value;
}

function typica_dataset(): array
{
    $raw = file_get_contents(TYPICA_ROOT . '/data/manifest.json');
    if ($raw === false) {
        throw new RuntimeException('Manifesto de dados ausente.');
    }
    $manifest = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
    if (!is_array($manifest) || ($manifest['format'] ?? '') !== 'cultivar-sqlite-regions-v2'
        || ($manifest['schema_version'] ?? null) !== 2 || !isset($manifest['catalog'], $manifest['regions'], $manifest['bundles'])) {
        throw new RuntimeException('Manifesto de dados incompatível.');
    }
    return [$manifest, hash('sha256', $raw)];
}

function typica_require_version(string $version, bool $required = false): void
{
    $requested = $_GET['versao'] ?? null;
    if ($requested === null && !$required) {
        return;
    }
    if (!is_string($requested) || !preg_match('/^[a-f0-9]{64}$/D', $requested)) {
        typica_fail(400, 'Versão dos dados inválida.');
    }
    if (!hash_equals($version, $requested)) {
        typica_fail(409, 'Os dados no servidor foram atualizados. Atualize o aplicativo antes de continuar o download.');
    }
}

function typica_bundle_path(array $bundle): string
{
    $relative = $bundle['download'] ?? '';
    if (!is_string($relative)
        || !preg_match('~^data/regioes_[a-f0-9]+_r[0-9]+/lote_[0-9]+_[a-f0-9]+\.bin$~D', $relative)) {
        throw new RuntimeException('Caminho de lote incompatível.');
    }
    $dataRoot = realpath(TYPICA_ROOT . '/data');
    $path = realpath(TYPICA_ROOT . '/' . $relative);
    if ($dataRoot === false || $path === false || !is_file($path)
        || strpos($path, $dataRoot . DIRECTORY_SEPARATOR) !== 0
        || !isset($bundle['bytes'], $bundle['sha256']) || !is_int($bundle['bytes'])
        || $bundle['bytes'] <= 0 || $bundle['bytes'] > 2000000 || filesize($path) !== $bundle['bytes']
        || !is_string($bundle['sha256']) || !preg_match('/^[a-f0-9]{64}$/D', $bundle['sha256'])) {
        throw new RuntimeException('Lote ausente ou incompleto.');
    }
    return $path;
}
