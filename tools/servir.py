#!/usr/bin/env python3
"""Executa o PWA e sua API com o servidor PHP local, sem alterar o sistema."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    php82 = ROOT / '.runtime/php82/bin/php'
    local_php = php82 if php82.is_file() else ROOT / '.runtime/php/usr/bin/php8.5'
    parser.add_argument('--php', default=os.environ.get('TYPICA_PHP') or shutil.which('php') or str(local_php))
    parser.add_argument('--port', type=int, default=8081)
    parser.add_argument('--base-path', default='/')
    parser.add_argument('--directory', type=Path, default=ROOT / 'build/web')
    args = parser.parse_args()
    if not args.base_path.startswith('/') or not args.base_path.endswith('/') or '..' in args.base_path:
        parser.error('--base-path deve começar e terminar com /.')
    if not (args.directory / 'sw.js').is_file() or not (args.directory / 'api/saude.php').is_file():
        parser.error('Compile primeiro: python3 tools/compilar.py')
    php = shutil.which(args.php) or args.php
    if not Path(php).is_file():
        parser.error('PHP CLI não encontrado. Instale php-cli ou informe --php /caminho/do/php.')
    env = {**os.environ, 'TYPICA_WEB_ROOT': str(args.directory.resolve()), 'TYPICA_BASE_PATH': args.base_path}
    command = [php, '-n', '-d', 'display_errors=0', '-d', 'zlib.output_compression=0',
               '-d', 'memory_limit=128M', '-S', f'127.0.0.1:{args.port}', '-t',
               str(args.directory.resolve()), str(ROOT / 'tools/router.php')]
    print(f'Typica PWA + PHP: http://localhost:{args.port}{args.base_path}', flush=True)
    print('Servidor de desenvolvimento; na UFV, publicar o conteúdo de build/web no Apache.', flush=True)
    server = subprocess.Popen(command, env=env)
    try:
        return server.wait()
    except KeyboardInterrupt:
        server.terminate()
        server.wait()
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
