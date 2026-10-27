#!/usr/bin/env python3
"""Extrai somente cultivar/instituição do Excel, sem modificar a planilha."""
import argparse
import hashlib
import json
from pathlib import Path
import posixpath
import re
import unicodedata
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
REL = '{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'


def normalize(value):
    value = unicodedata.normalize('NFKD', value).encode('ascii', 'ignore').decode().lower()
    return re.sub(r'[^a-z0-9]+', ' ', value).strip()


def extract(source, sheet):
    with zipfile.ZipFile(source) as archive:
        workbook = ET.fromstring(archive.read('xl/workbook.xml'))
        selected = next((s for s in workbook.findall('s:sheets/s:sheet', NS) if s.attrib['name'] == sheet), None)
        if selected is None:
            raise ValueError(f'Aba não encontrada: {sheet}')
        relationships = ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))
        target = next(r.attrib['Target'] for r in relationships if r.attrib['Id'] == selected.attrib[REL])
        path = target.lstrip('/') if target.startswith('/') else posixpath.normpath('xl/' + target)
        strings = []
        if 'xl/sharedStrings.xml' in archive.namelist():
            strings = [''.join(node.itertext()) for node in ET.fromstring(archive.read('xl/sharedStrings.xml')).findall('s:si', NS)]
        rows = []
        for row in ET.fromstring(archive.read(path)).findall('s:sheetData/s:row', NS):
            values = {}
            for cell in row.findall('s:c', NS):
                column = re.sub(r'\d+', '', cell.attrib['r'])
                value = cell.find('s:v', NS)
                if cell.attrib.get('t') == 'inlineStr':
                    text = ''.join(cell.find('s:is', NS).itertext())
                elif value is None:
                    continue
                elif cell.attrib.get('t') == 's':
                    text = strings[int(value.text)]
                else:
                    text = value.text or ''
                values[column] = text.strip()
            if any(values.values()):
                rows.append((int(row.attrib['r']), values))
    header = rows[0][1]
    columns = {normalize(value): column for column, value in header.items()}
    if not {'cultivar', 'instituicao'}.issubset(columns):
        raise ValueError('A aba precisa das colunas Cultivar e Instituição.')
    mapping = {}
    for index, row in rows[1:]:
        name = row.get(columns['cultivar'], '')
        institution = row.get(columns['instituicao'], '')
        if not name:
            continue
        if not institution or institution in ('Todos', 'Não informada'):
            raise ValueError(f'Instituição ausente ou inválida na linha {index}.')
        key = normalize(name)
        if key in mapping and mapping[key] != institution:
            raise ValueError(f'Instituições conflitantes para {name}.')
        mapping[key] = institution
    if not mapping:
        raise ValueError('Nenhuma instituição encontrada.')
    return {'source_file': source.name, 'source_sheet': sheet,
            'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'cultivars': dict(sorted(mapping.items()))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workbook', type=Path)
    parser.add_argument('--sheet', default='Informação Cultivares')
    parser.add_argument('--output', type=Path, default=ROOT / 'assets/instituicoes.json')
    args = parser.parse_args()
    result = extract(args.workbook, args.sheet)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'cultivars': len(result['cultivars']),
                      'institutions': sorted(set(result['cultivars'].values())),
                      'output': str(args.output)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
