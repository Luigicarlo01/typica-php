# Typica PWA com backend PHP

Projeto independente derivado do PWA Typica 0.1.0+9, identificado como
`typica_pwa_php` e versão **0.2.0+1**. Os projetos anteriores não são modificados.
O layout, tutoriais, instalação, filtros, PDF e recomendações por pixel continuam
no frontend Flutter Web. O backend deste projeto é executado em **PHP**.

## Construção

- `lib/` e `web/`: frontend e recursos de instalação/offline.
- `api/`: backend PHP de leitura, sem dependências Composer.
- `private_assets/`: cópias locais dos dados de entrada, ignoradas pelo Git.
- `tools/`: preparação dos dados, compilação, servidor local e testes.
- `deploy/`: configuração Apache e instruções para a UFV-DTI.
- `build/web/`: publicação completa com frontend, PHP e dados.

O PHP informa as versões do aplicativo e dos dados, entrega o manifesto e
transmite os lotes compactados. O frontend usa esses endpoints de verdade;
não se trata de renomear o `index.html` para `.php`.
As consultas ao banco continuam no dispositivo, preservando o uso offline e o
ranking original de cada pixel. O mapa de fundo OpenStreetMap depende de internet.
Não é necessário um banco MySQL/MariaDB para esta distribuição de arquivos.

## Compilar e testar neste computador

```bash
cd typica_pwa_php
python3 tools/compilar.py
python3 tools/servir.py
```

Abra **http://localhost:8081/**. A porta difere do PWA anterior, evitando conflito
e mantendo o armazenamento dos testes separado. O servidor agora executa PHP;
`python -m http.server` não executa os endpoints desta versão.

A ferramenta de teste procura PHP no PATH, na variável `TYPICA_PHP` ou na cópia
local `.runtime/php82/bin/php` (PHP 8.2.35 compilado da distribuição oficial),
com alternativa em `.runtime/php/usr/bin/php8.5` (pacote oficial do Ubuntu).
Essas cópias não instalam nem alteram o PHP do sistema. `.runtime/` não vai para a
hospedagem nem para o Git. Em outro computador, instale PHP CLI ou use:

```bash
python3 tools/servir.py --php /caminho/do/php
```

Flutter/Dart e Python são ferramentas de compilação/teste no computador do
desenvolvedor. Na hospedagem, são necessários somente Apache e PHP. O código
PHP utiliza recursos disponíveis no PHP 8.2 e posteriores, sem extensões de
banco de dados. A validação local registra a versão do PHP efetivamente usada.

## Dados de entrada

Este projeto já tem cópias próprias dos dados necessários em `private_assets/`.
Não usa links simbólicos nem depende dos projetos anteriores para compilar.
Esses dados não são versionados no Git. Para outra instalação, forneça:

```text
private_assets/
  cultivares.json
  colors_2026.json
  mg.geojson
  data/
    manifest.json
    <pacote-original>.sqlite.gz
```

O campo `asset` do manifesto original determina o nome do pacote. Também é
possível usar `--assets-dir /caminho/privado` ou `TYPICA_ASSETS_DIR`. A preparação
confere hashes, copia os arquivos e conserva os resultados científicos originais.

O banco distribuído tem um catálogo e 853 partições municipais compactadas em
46 lotes de até 2 MB. O download continua limitado a um lote por vez, com SHA-256
e retomada por lote. No aparelho, os pacotes são guardados no IndexedDB e apenas
o município consultado é aberto como SQLite. Não houve novo cálculo de previsão.

## API PHP

Todos os endpoints são de leitura (`GET` e `HEAD`):

| Endpoint | Responsabilidade |
| --- | --- |
| `api/saude.php` | Verifica a publicação e a presença dos lotes. |
| `api/versao.php` | Informa versão, build e endereço do manifesto atual. |
| `api/manifesto.php?versao=<sha256>` | Entrega o manifesto da versão fixada no aplicativo. |
| `api/lote.php?id=<indice>&versao=<sha256>` | Transmite um lote validado, sem aceitar caminhos de arquivos do cliente. |

O SHA-256 do manifesto é definido na compilação por `TYPICA_DATA_VERSION`.
O service worker salva a resposta desse manifesto junto da interface. Por isso,
reabrir o app offline não depende do PHP nem da conexão. Downloads e verificação
de novas versões usam a rede; os lotes ficam no IndexedDB, sem duplicação no cache
HTTP da interface. Uma troca de versão no servidor é recusada durante o download
antigo, para impedir misturar pacotes de publicações diferentes.

**Verificar atualização** consulta `api/versao.php` e procura uma nova publicação
do service worker. A atualização do banco é publicada recompilando o conjunto
com os novos dados. Não há painel de edição nem upload público no backend.

## Publicar na UFV-DTI

Envie **todo o conteúdo de `build/web/`**, incluindo `.htaccess`, `api/` e `data/`,
para a pasta pública `web` da hospedagem. Não envie `private_assets/`, `.runtime/`,
os arquivos Dart de origem ou toda a pasta de desenvolvimento.

Confirme com a DTI a habilitação do PHP, o HTTPS, os tipos de conteúdo e o uso
de `.htaccess`. O pacote fica abaixo de 500 MB; a ferramenta informa o tamanho
real ao compilar. A cota contratada e as regras de aceitação cabem à instituição.
Os arquivos precisam de leitura pelo PHP, sem permissões de escrita no servidor.

Para uma subpasta, compile com a base correspondente:

```bash
python3 tools/compilar.py --base-href /typica/
python3 tools/servir.py --base-path /typica/
```

Os endpoints e downloads acompanham essa base, sem domínio fixo no código.
Publique o conjunto completo de forma atômica. Uma atualização incompleta não
deve substituir o conjunto anterior. Instruções em `deploy/UFV-DTI.md`.

## Verificação

Com o servidor PHP em execução:

```bash
python3 tools/testar_api.py
NODE_PATH="$PWD/.runtime/browser/node_modules" node tools/testar_pwa.cjs
NODE_PATH="$PWD/.runtime/browser/node_modules" PWA_TEST_VIEWPORTS=390x844 node tools/testar_tela_inicial.cjs
NODE_PATH="$PWD/.runtime/browser/node_modules" node tools/testar_atualizacao.cjs
# Para o conjunto de teste em /typica/:
NODE_PATH="$PWD/.runtime/browser/node_modules" PWA_TEST_URL=http://localhost:8083/typica/ node tools/testar_offline_api.cjs
```

A dependência de testes pode ser obtida com
`npm install --prefix .runtime/browser playwright-core`. Ela não integra o app
publicado. Os relatórios e capturas ficam em `build/verificacao*/`.
Os testes de navegador são executados no Chrome do computador. Instalação nativa
e comportamento em aparelhos físicos Android/iOS ainda precisam de teste local.

O teste de API cobre versão, manifesto, integridade dos lotes, HEAD, métodos e
entradas inválidas. O teste funcional cobre o download via PHP, ranking em dois
pixels, filtros, PDF e reabertura offline. Os testes de pacotes e recuperação
herdados continuam disponíveis como verificações isoladas do armazenamento.
