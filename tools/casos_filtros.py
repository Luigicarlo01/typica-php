#!/usr/bin/env python3
"""Resultados esperados dos filtros a partir dos bancos originais de dois pixels."""
import gzip
import json
from pathlib import Path
import re
import sqlite3
import struct
import sys
import unicodedata

ROOT = Path(__file__).resolve().parents[1]


def key(text):
    value = re.sub('[^a-z0-9]+', ' ', unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode().lower()).strip()
    return 'bourbon amarelo iac j10' if value == 'bourbon ama iac j10' else value


def contains(blob, longitude, latitude):
    offset = 0

    def ring_inside(points):
        inside = False
        for (x1, y1), (x2, y2) in zip(points, points[1:] + points[:1]):
            if (y1 > latitude) != (y2 > latitude) and longitude < (x2 - x1) * (latitude - y1) / (y2 - y1) + x1:
                inside = not inside
        return inside

    def geometry():
        nonlocal offset
        endian = '<' if blob[offset] == 1 else '>'
        offset += 1
        def integer():
            nonlocal offset
            value = struct.unpack_from(endian + 'I', blob, offset)[0]
            offset += 4
            return value
        kind = integer()
        if kind == 6:
            parts = [geometry() for _ in range(integer())]
            return any(parts)
        if kind != 3:
            raise ValueError(f'Geometria inesperada no teste: {kind}')
        rings = []
        for _ in range(integer()):
            points = []
            for _ in range(integer()):
                points.append(struct.unpack_from(endian + 'dd', blob, offset))
                offset += 16
            rings.append(ring_inside(points))
        return bool(rings and rings[0] and not any(rings[1:]))
    return geometry()


def main():
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / 'build/web'
    manifest = json.loads((directory / 'data/manifest.json').read_text())
    def database(descriptor):
        packed = (directory / manifest['bundles'][descriptor['bundle']]['download']).read_bytes()
        raw = gzip.decompress(packed[descriptor['offset']:descriptor['offset'] + descriptor['compressed_bytes']])
        db = sqlite3.connect(':memory:')
        db.deserialize(raw)
        return db
    catalog = database(manifest['catalog'])
    regional = database(manifest['regions']['VICOSA_2026.geojson'])
    information = json.loads((ROOT / 'private_assets/cultivares.json').read_text())['cultivares']
    information = {key(info['nome']): info for info in information.values()}
    institutions = json.loads((ROOT / 'assets/instituicoes.json').read_text())['cultivars']
    pixels = []
    for latitude, longitude in [(-20.830307493566902, -42.85955821862572), (-20.82459502172251, -42.87347917744958)]:
        matches = [ranking for ranking, blob in regional.execute("SELECT ranking_id,geometria FROM cultivar_feicoes WHERE tipo='grid'") if contains(blob, longitude, latitude)]
        assert len(matches) == 1
        props = json.loads(catalog.execute('SELECT propriedades_json FROM cultivar_rankings WHERE id=?', (matches[0],)).fetchone()[0])
        names = list(dict.fromkeys([props['winner'], *props['alternatives']]))
        cases = []
        selections = [
            ('Todos', 'Todos', 'Todos', 'Todos'),
            ('Todos', 'Epamig', 'Todos', 'Todos'),
            ('Todos', 'IAC', 'Todos', 'Todos'),
            ('Todos', 'Fundação Procafé', 'Todos', 'Todos'),
            ('Todos', 'IDR Paraná', 'Todos', 'Todos'),
            ('Curto', 'Todos', 'Todos', 'Todos'),
            ('Médio', 'Todos', 'Todos', 'Todos'),
            ('Longo', 'Todos', 'Todos', 'Todos'),
            ('Curto', 'IAC', 'Todos', 'Todos'),
            ('Longo', 'IAC', 'Todos', 'Todos'),
            ('Médio', 'Epamig', 'Resistente', 'Suscetível'),
            ('Todos', 'Todos', 'Todos', 'Todos'),
        ]
        for cycle, institution, rust, nematode in selections:
            expected = []
            for name in names:
                normalized = key(name)
                info = information.get(normalized, {})
                if institution != 'Todos' and institutions.get(normalized) != institution:
                    continue
                if cycle != 'Todos' and key(info.get('maturacao') or '') != {'Curto': 'precoce', 'Médio': 'intermediario', 'Longo': 'tardio'}[cycle]:
                    continue
                if rust != 'Todos' and key(info.get('ferrugem') or '') != key(rust):
                    continue
                if nematode != 'Todos' and key(info.get('nematoide') or '') != key(nematode):
                    continue
                expected.append(name)
            cases.append({'cycle': cycle, 'institution': institution, 'rust': rust, 'nematode': nematode, 'expected': expected[:5]})
        pixels.append({'latitude': latitude, 'longitude': longitude, 'ranking': names, 'cases': cases})
    print(json.dumps({'pixels': pixels, 'institutions': sorted(set(institutions.values()))}, ensure_ascii=False))


if __name__ == '__main__':
    main()
