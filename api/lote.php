<?php
declare(strict_types=1);
require __DIR__ . '/_bootstrap.php';

typica_run(function (): void {
    [$manifest, $version] = typica_dataset();
    typica_require_version($version, true);
    $id = $_GET['id'] ?? null;
    if (!is_string($id) || !preg_match('/^(0|[1-9][0-9]{0,4})$/D', $id)) {
        typica_fail(400, 'Identificador de lote inválido.');
    }
    $bundle = $manifest['bundles'][(int) $id] ?? null;
    if (!is_array($bundle)) {
        typica_fail(404, 'Lote não encontrado.');
    }
    $path = typica_bundle_path($bundle);
    if (!hash_equals($bundle['sha256'], hash_file('sha256', $path))) {
        throw new RuntimeException('Integridade do lote divergente.');
    }
    $stream = fopen($path, 'rb');
    if ($stream === false) {
        throw new RuntimeException('Não foi possível abrir o lote.');
    }
    // O nome vem do manifesto validado, nunca de um caminho enviado pelo cliente.
    header('Content-Type: application/octet-stream');
    header('Content-Length: ' . $bundle['bytes']);
    header('Content-Disposition: inline; filename="' . basename($path) . '"');
    header('Cache-Control: public, max-age=31536000, immutable');
    header('X-Content-Type-Options: nosniff');
    header('ETag: "' . $bundle['sha256'] . '"');
    header('Accept-Ranges: none');
    if ($_SERVER['REQUEST_METHOD'] !== 'HEAD') {
        // Um lote de até 2 MB por vez, transmitido em blocos pequenos.
        while (!feof($stream) && !connection_aborted()) {
            $chunk = fread($stream, 65536);
            if ($chunk === false) {
                break;
            }
            echo $chunk;
        }
    }
    fclose($stream);
});
