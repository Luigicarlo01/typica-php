<?php
declare(strict_types=1);
require __DIR__ . '/_bootstrap.php';

typica_run(function (): void {
    [$manifest, $version] = typica_dataset();
    $release = typica_read_json(TYPICA_ROOT . '/pwa-version.json');
    if (($release['manifest_version'] ?? '') !== $version) {
        throw new RuntimeException('Publicação incompleta.');
    }
    foreach ($manifest['bundles'] as $bundle) {
        typica_bundle_path($bundle);
    }
    typica_json(['status' => 'ok', 'backend' => 'php', 'api_version' => 1,
        'manifest_version' => $version, 'bundles' => count($manifest['bundles']),
        'municipalities' => $manifest['municipalities']]);
});
