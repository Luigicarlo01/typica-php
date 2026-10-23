#!/usr/bin/env python3
"""Deriva SQLite por município, sem alterar o SQL, SQLite ou GeoJSON original."""
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import tempfile

FORMAT = 'cultivar-sqlite-regions-v2'
REVISION = 1
BUNDLE_LIMIT = 2_000_000
MAX_DATABASE = 4_000_000


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def partition(source_gzip, original, output):
    folder = output / f"regioes_{original['database_sha256'][:20]}_r{REVISION}"
    cached = folder / 'manifest.json'
    if cached.exists():
        manifest = json.loads(cached.read_text())
        if manifest.get('converter_revision') == REVISION and all(
            (output.parent / b['download']).is_file()
            and file_digest(output.parent / b['download']) == b['sha256']
            for b in manifest['bundles']
        ):
            (output / 'manifest.json').write_text(cached.read_text())
            print(f"Partições reaproveitadas: {len(manifest['regions'])} municípios.")
            return manifest
    folder.mkdir(parents=True, exist_ok=True)
    packages = []
    bundles = []
    buffer = bytearray()

    def flush():
        if not buffer:
            return
        sha = digest(buffer)
        name = f'lote_{len(bundles):03d}_{sha[:16]}.bin'
        target = folder / name
        if target.exists():
            if file_digest(target) != sha:
                raise ValueError(f'Pacote existente divergente: {target}')
        else:
            target.write_bytes(buffer)
        bundles.append({'download': f'data/{folder.name}/{name}', 'bytes': len(buffer), 'sha256': sha})
        buffer.clear()

    def save(db_path, key, kind, features=0):
        raw = db_path.read_bytes()
        if len(raw) > MAX_DATABASE:
            raise ValueError(f'A partição {key} excede o limite de memória: {len(raw)} bytes')
        packed = gzip.compress(raw, compresslevel=6, mtime=0)
        if len(buffer) + len(packed) > BUNDLE_LIMIT:
            flush()
        descriptor = {'key': key, 'kind': kind, 'database_bytes': len(raw), 'database_sha256': digest(raw),
                      'compressed_bytes': len(packed), 'compressed_sha256': digest(packed),
                      'features': features, 'bundle': len(bundles), 'offset': len(buffer)}
        packages.append(descriptor)
        buffer.extend(packed)
        return descriptor

    def metadata(db, kind, key):
        db.execute('CREATE TABLE cultivar_metadata (chave TEXT PRIMARY KEY, valor TEXT NOT NULL)')
        db.executemany('INSERT INTO cultivar_metadata VALUES (?,?)', [
            ('format', FORMAT), ('kind', kind), ('key', key),
            ('source_sql_sha256', original['source_sql_sha256']),
            ('source_database_sha256', original['database_sha256']),
        ])

    with tempfile.TemporaryDirectory(prefix='cultivar-particoes-') as temp:
        temp = Path(temp)
        source_path = temp / 'origem.sqlite'
        with gzip.open(source_gzip, 'rb') as src, source_path.open('wb') as target:
            shutil.copyfileobj(src, target, 1024 * 1024)
        if file_digest(source_path) != original['database_sha256']:
            raise ValueError('SQLite descompactado divergente da origem.')
        source = sqlite3.connect(f'file:{source_path}?mode=ro', uri=True)
        catalog_path = temp / 'catalogo.sqlite'
        catalog = sqlite3.connect(catalog_path)
        for table in ['cultivar_municipios', 'cultivar_arquivos', 'cultivar_rankings', 'cultivar_ranking_itens']:
            schema = source.execute("SELECT sql FROM sqlite_master WHERE name=?", (table,)).fetchone()[0]
            catalog.execute(schema)
            rows = source.execute(f'SELECT * FROM {table}').fetchall()
            placeholders = ','.join('?' for _ in rows[0])
            catalog.executemany(f'INSERT INTO {table} VALUES ({placeholders})', rows)
        metadata(catalog, 'catalog', 'catalog')
        catalog.commit()
        catalog.close()
        catalog_info = save(catalog_path, 'catalog', 'catalog')
        regions = {}
        feature_count = 0
        pixels = 0
        boundaries = 0
        for file_id, filename, expected in source.execute('SELECT id,arquivo,total_feicoes FROM cultivar_arquivos ORDER BY id'):
            region_path = temp / 'regiao.sqlite'
            if region_path.exists():
                region_path.unlink()  # Apenas o arquivo temporário criado nesta função.
            db = sqlite3.connect(region_path)
            db.execute('CREATE TABLE cultivar_feicoes (id INTEGER PRIMARY KEY, arquivo_id INTEGER NOT NULL, indice INTEGER NOT NULL, tipo TEXT NOT NULL, ranking_id INTEGER NOT NULL, geometria BLOB NOT NULL)')
            rows = source.execute('SELECT id,arquivo_id,indice,tipo,ranking_id,geometria FROM cultivar_feicoes WHERE arquivo_id=? ORDER BY indice', (file_id,)).fetchall()
            assert len(rows) == expected
            db.executemany('INSERT INTO cultivar_feicoes VALUES (?,?,?,?,?,?)', rows)
            metadata(db, 'region', filename)
            db.commit()
            # Confere todas as geometrias, referências e índices contra a origem.
            assert db.execute('SELECT id,arquivo_id,indice,tipo,ranking_id,geometria FROM cultivar_feicoes ORDER BY indice').fetchall() == rows
            db.close()
            regions[filename] = save(region_path, filename, 'region', len(rows))
            feature_count += len(rows)
            pixels += sum(row[3] == 'grid' for row in rows)
            boundaries += sum(row[3] == 'municipio' for row in rows)
        source.close()
    flush()
    assert feature_count == original['features'] and pixels == original['pixels'] and boundaries == original['boundaries']
    manifest = {'format': FORMAT, 'schema_version': 2, 'converter_revision': REVISION,
                'database_sha256': original['database_sha256'], 'source_sql_sha256': original['source_sql_sha256'],
                'municipalities': original['municipalities'], 'features': feature_count, 'pixels': pixels, 'boundaries': boundaries,
                'database_bytes': sum(p['database_bytes'] for p in packages),
                'compressed_bytes': sum(b['bytes'] for b in bundles),
                'max_database_bytes': max(p['database_bytes'] for p in packages),
                'max_bundle_bytes': max(b['bytes'] for b in bundles),
                'catalog': catalog_info, 'regions': regions, 'bundles': bundles}
    text = json.dumps(manifest, ensure_ascii=False, separators=(',', ':')) + '\n'
    cached.write_text(text)
    (output / 'manifest.json').write_text(text)
    print(f"Dados particionados: {len(regions)} municípios, {len(bundles)} lotes, {manifest['compressed_bytes']/1e6:.1f} MB; maior SQLite {manifest['max_database_bytes']/1e6:.2f} MB.")
    return manifest
