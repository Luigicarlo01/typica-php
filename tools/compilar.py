#!/usr/bin/env python3
"""Compila o Typica PWA e publica sua API PHP para Apache ou teste local."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import shutil
import subprocess
import urllib.request

from preparar_dados import ROOT, default_assets_dir, prepare, sha256

SQLITE_URL = 'https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.1.7/sqlite3.wasm'
SQLITE_SHA256 = '3c611e38db0a2609c34a141ccf70c89b407b262c9bf06877c4ba213cf9f3624b'


def manifest_endpoint(directory):
    version = sha256(directory / 'data/manifest.json')
    return version, 'api/manifesto.php?versao=' + version


def precache(output):
    shutil.copytree(ROOT / 'api', output / 'api', dirs_exist_ok=True)
    data_version, manifest_path = manifest_endpoint(output)
    manifest = json.loads((output / 'data/manifest.json').read_text())
    version_info = json.loads((output / 'version.json').read_text())
    if not all(key in version_info for key in ('app_name', 'version', 'build_number', 'package_name')):
        raise ValueError('version.json precisa ser o arquivo padrão do Flutter. Compile o projeto novamente.')
    # Apenas o pacote atual entra na publicação. As cópias em web/data são mantidas.
    for pattern in ('*.map', '*.deps', '*.dart'):
        for path in output.rglob(pattern):
            path.unlink()
    core = sorted(path.relative_to(output).as_posix() for path in output.rglob('*')
                  if path.is_file() and not path.name.endswith(('.sqlite.gz', '.partial'))
                  and path.relative_to(output).parts[0] not in ('data', 'api')
                  and not any(part.startswith('.') for part in path.relative_to(output).parts)
                  and path.name not in ('sw.js', 'flutter_service_worker.js', '.htaccess', 'pwa-version.json'))
    core.append(manifest_path)
    digest = hashlib.sha256()
    digest.update(bytes.fromhex(data_version))
    for source in sorted((ROOT / 'api').rglob('*')):
        if source.is_file():
            digest.update(source.relative_to(ROOT).as_posix().encode())
            digest.update(bytes.fromhex(sha256(source)))
    template = (ROOT / 'tools/service_worker.template.js').read_text()
    digest.update(template.encode())
    for relative in core:
        digest.update(relative.encode())
        if relative != manifest_path:
            digest.update(bytes.fromhex(sha256(output / relative)))
    build_id = digest.hexdigest()[:20]
    (output / 'sw.js').write_text(template.replace('__BUILD_ID__', build_id).replace('__CORE_FILES__', json.dumps(core)).replace('__MANIFEST_PATH__', manifest_path))
    (output / 'pwa-version.json').write_text(json.dumps({'build': build_id, 'application': 'typica_pwa_php', 'backend': 'php', 'manifest_version': data_version, 'data': manifest['database_sha256']}, indent=2) + '\n')
    shutil.copy2(ROOT / 'deploy/apache.htaccess', output / '.htaccess')
    size = sum(p.stat().st_size for p in output.rglob('*') if p.is_file())
    print(f'Publicação pronta: {output}\nTotal: {size / 1e6:.1f} MB; cache do aplicativo: {len(core)} arquivos; versão {build_id}.')
    if size > 500_000_000:
        raise ValueError('O pacote ultrapassa os 500 MB informados pela DTI-UFV.')
    return {'build': build_id, 'bytes': size, 'files': len(core)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-href', default='/')
    parser.add_argument('--assets-dir', type=Path, default=default_assets_dir())
    parser.add_argument('--flutter', default=shutil.which('flutter') or str(Path.home() / 'App/flutter/bin/flutter'))
    parser.add_argument('--output', type=Path, default=ROOT / 'build/web')
    args = parser.parse_args()
    if not args.base_href.startswith('/') or not args.base_href.endswith('/') or '..' in args.base_href:
        parser.error('--base-href deve começar e terminar com /, por exemplo /cultivar/.')
    prepare(args.assets_dir)
    data_version, _ = manifest_endpoint(ROOT / 'web')
    wasm = ROOT / 'web/sqlite3.wasm'
    if not wasm.exists():
        with urllib.request.urlopen(SQLITE_URL) as source, wasm.open('wb') as target:
            shutil.copyfileobj(source, target)
    if sha256(wasm) != SQLITE_SHA256:
        raise ValueError('O módulo SQLite WebAssembly não corresponde à versão 3.1.7 esperada.')
    flutter = Path(args.flutter).resolve()
    dart = flutter.parent / 'cache/dart-sdk/bin/dart'
    if not dart.exists():
        dart = flutter.parent / 'dart'
    subprocess.run([str(flutter), 'pub', 'get', '--offline'], cwd=ROOT, check=True)
    subprocess.run([str(dart), 'compile', 'js', '-O2', 'web/drift_worker.dart', '-o', 'web/drift_worker.dart.js'], cwd=ROOT, check=True)
    version = re.search(r'^version:\s*(\S+)', (ROOT / 'pubspec.yaml').read_text(), re.MULTILINE).group(1)
    subprocess.run([str(flutter), 'build', 'web', '--release', '--no-web-resources-cdn', '--no-wasm-dry-run', '--dart-define=CULTIVAR_VERSION=' + version, '--dart-define=TYPICA_DATA_VERSION=' + data_version, '--base-href', args.base_href, '--output', str(args.output)], cwd=ROOT, check=True)
    precache(args.output)


if __name__ == '__main__':
    main()
