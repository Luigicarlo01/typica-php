<?php
declare(strict_types=1);
require __DIR__ . '/_bootstrap.php';

typica_run(function (): void {
    [$manifest, $version] = typica_dataset();
    $release = typica_read_json(TYPICA_ROOT . '/pwa-version.json');
    $app = typica_read_json(TYPICA_ROOT . '/version.json');
    if (($release['manifest_version'] ?? '') !== $version) {
        throw new RuntimeException('Versões do aplicativo e dos dados divergentes.');
    }
    typica_json([
        'application' => 'Typica',
        'backend' => 'php',
        'api_version' => 1,
        'version' => $app['version'],
        'build_number' => $app['build_number'],
        'build' => $release['build'],
        'data' => $manifest['database_sha256'],
        'manifest_version' => $version,
        'manifest_url' => 'api/manifesto.php?versao=' . $version,
        'bundles' => count($manifest['bundles']),
        'compressed_bytes' => $manifest['compressed_bytes'],
    ]);
});
