#!/usr/bin/env python3
"""Contrato HTTP real da API PHP. Requer tools/servir.py em execução."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', default='http://localhost:8081/')
    parser.add_argument('--directory', type=Path, default=ROOT / 'build/web')
    parser.add_argument('--output', type=Path, default=ROOT / 'build/verificacao-api/resultado.json')
    args = parser.parse_args()
    checks = []

    def request(relative, method='GET', status=200):
        url = urllib.parse.urljoin(args.url, relative)
        req = urllib.request.Request(url, method=method)
        try:
            response = urllib.request.urlopen(req, timeout=30)
        except urllib.error.HTTPError as error:
            response = error
        with response:
            body = response.read()
            assert response.status in (status if isinstance(status, tuple) else (status,)), (relative, response.status, body[:200])
            return body, response.headers

    def get_json(relative):
        body, headers = request(relative)
        assert headers.get_content_type() == 'application/json'
        assert headers.get('Cache-Control') == 'no-store'
        return json.loads(body)

    health = get_json('api/saude.php')
    assert health['status'] == 'ok' and health['backend'] == 'php'
    latest = get_json('api/versao.php')
    release = json.loads((args.directory / 'pwa-version.json').read_text())
    assert latest['build'] == release['build'] and latest['backend'] == 'php'
    checks.append('Servidor PHP informa saúde e versão real da publicação, sem cache de atualização')
    manifest = get_json(latest['manifest_url'])
    raw = json.loads((args.directory / 'data/manifest.json').read_text())
    assert manifest['manifest_version'] == hashlib.sha256((args.directory / 'data/manifest.json').read_bytes()).hexdigest()
    assert manifest['regions'] == raw['regions'] and manifest['catalog'] == raw['catalog']
    assert manifest['source_sql_sha256'] == raw['source_sql_sha256']
    assert len(manifest['bundles']) == health['bundles'] == latest['bundles']
    checks.append('Manifesto PHP mantém todos os municípios, pixels, rankings e hashes originais')
    indices = {0, len(manifest['bundles']) - 1, max(range(len(raw['bundles'])), key=lambda i: raw['bundles'][i]['bytes'])}
    for index in sorted(indices):
        bundle = manifest['bundles'][index]
        assert bundle['download'].startswith('api/lote.php?')
        body, headers = request(bundle['download'])
        assert len(body) == bundle['bytes']
        assert hashlib.sha256(body).hexdigest() == bundle['sha256']
        assert headers.get_content_type() == 'application/octet-stream'
        assert headers.get('Content-Encoding') is None
        head, head_headers = request(bundle['download'], method='HEAD')
        assert head == b'' and int(head_headers['Content-Length']) == len(body)
    checks.append('Primeiro, último e maior lote transmitidos pelo PHP com tamanho e SHA-256 corretos; HEAD sem corpo')
    version = latest['manifest_version']
    for path, status in [
        ('api/lote.php', 400),
        ('api/lote.php?id=0', 400),
        (f'api/lote.php?id=99999&versao={version}', 404),
        (f'api/lote.php?id=../api/_bootstrap.php&versao={version}', 400),
        (f'api/lote.php?id[]=0&versao={version}', 400),
        ('api/manifesto.php?versao[]=x', 400),
        ('api/manifesto.php?versao=' + '0' * 64, 409),
        ('api/lote.php?id=0&versao=' + '0' * 64, 409),
        ('api/_bootstrap.php', (403, 404)),
    ]:
        request(path, status=status)
    _, headers = request('api/manifesto.php', method='POST', status=405)
    assert headers.get('Allow') == 'GET, HEAD'
    checks.append('Entradas inválidas, acesso a arquivos internos e mistura de versões rejeitados')
    report = {'success': True, 'url': args.url, 'checks': checks, 'build': latest['build'],
              'municipalities': manifest['municipalities'], 'pixels': manifest['pixels']}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
