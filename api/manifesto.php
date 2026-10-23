<?php
declare(strict_types=1);
require __DIR__ . '/_bootstrap.php';

typica_run(function (): void {
    [$manifest, $version] = typica_dataset();
    typica_require_version($version);
    foreach ($manifest['bundles'] as $index => &$bundle) {
        $bundle['download'] = 'api/lote.php?id=' . $index . '&versao=' . $version;
    }
    unset($bundle);
    $manifest['manifest_version'] = $version;
    $manifest['backend'] = ['type' => 'php', 'api_version' => 1];
    typica_json($manifest);
});
