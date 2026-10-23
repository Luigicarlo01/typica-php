#!/usr/bin/env python3
"""Copia os assets privados e o pacote SQLite existente para o projeto PWA.

Não lê MySQL, não recalcula rankings e não modifica os arquivos de origem.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
from particionar_dados import partition

ROOT = Path(__file__).resolve().parents[1]


def default_assets_dir():
    configured = os.environ.get('TYPICA_ASSETS_DIR')
    local_path = ROOT / '.typica-assets-path'
    if not configured and local_path.is_file():
        configured = local_path.read_text().strip()
    return Path(configured).expanduser() if configured else ROOT / 'private_assets'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def prepare(assets):
    assets = Path(assets).resolve()
    if not (assets / 'data/manifest.json').is_file():
        raise FileNotFoundError(
            'Dados privados não encontrados. Informe --assets-dir /caminho/dos/assets '
            'ou organize os arquivos em private_assets/. Consulte o README.md.'
        )
    manifest = json.loads((assets / 'data/manifest.json').read_text())
    source = assets / Path(manifest['asset']).relative_to('assets')
    if source.stat().st_size != manifest['compressed_bytes'] or sha256(source) != manifest['compressed_sha256']:
        raise ValueError('O pacote SQLite de origem não corresponde ao manifesto.')
    private_files = ['cultivares.json', 'colors_2026.json', 'mg.geojson']
    logos = ['logo_epamig.svg', 'typica_logo.svg', 'typica_logo_sem_borda.svg',
             'logo_ufv.png', 'logo_ufv.svg', 'Logo embrapa cafe.png']
    for name in private_files:
        if not (assets / name).is_file():
            raise FileNotFoundError(f'Asset necessário não encontrado: {assets / name}')
    for name in logos:
        if not (assets / name).is_file() and not (ROOT / 'assets' / name).is_file():
            raise FileNotFoundError(f'Logotipo necessário não encontrado: {name}')
    (ROOT / 'assets').mkdir(exist_ok=True)
    for name in private_files + logos:
        source_asset, target_asset = assets / name, ROOT / 'assets' / name
        if source_asset.is_file() and source_asset.resolve() != target_asset.resolve():
            shutil.copy2(source_asset, target_asset)
    output = ROOT / 'web/data'
    output.mkdir(parents=True, exist_ok=True)
    filename = f"cultivar_{manifest['database_sha256'][:20]}.sqlite.gz"
    target = output / filename
    if target.exists():
        if sha256(target) != manifest['compressed_sha256']:
            raise ValueError(f'O pacote existente diverge da origem: {target}')
    else:
        partial = output / f'{filename}.partial'
        shutil.copy2(source, partial)
        partial.replace(target)
    partition(source, manifest, output)
    print('Dados originais preservados. O pacote monolítico não é usado pelo novo PWA.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--assets-dir', type=Path, default=default_assets_dir())
    prepare(parser.parse_args().assets_dir)
