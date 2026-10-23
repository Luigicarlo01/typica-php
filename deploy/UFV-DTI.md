# Publicação do Typica com PHP na UFV-DTI

Este projeto usa frontend Flutter Web já compilado e backend PHP.
O servidor não executa Dart, Python ou Node e não precisa de Composer nem MariaDB.

1. Compile com `python3 tools/compilar.py --base-href /` ou com a subpasta real.
2. Verifique o conjunto com `python3 tools/servir.py` e `python3 tools/testar_api.py`.
3. Envie o conteúdo de `build/web/` para a pasta pública `web`, incluindo arquivos
   ocultos `.htaccess`, `api/` e `data/`. Preserve a publicação anterior durante o envio.
4. Habilite PHP e HTTPS. PHP precisa de leitura dos arquivos do pacote, sem escrita.
5. Abra `https://<dominio>/<base>/api/saude.php`: deve retornar JSON com
   `status: ok`, `backend: php`, 46 lotes e 853 municípios para os dados atuais.
6. Abra `api/versao.php`, teste o download dos dados pela interface e reabra offline.

O código PHP usa recursos disponíveis a partir do PHP 8.2. O pacote de publicação
não contém o runtime local de testes. Use a versão de PHP disponibilizada pela DTI.
A aprovação e a configuração definitiva precisam ser confirmadas com a instituição.

O `.htaccess` da raiz configura `index.html` e os tipos `.js`, `.wasm`, `.bin` e
`.gz`. Em `api/`, o `.htaccess` impede acesso direto aos arquivos internos com
prefixo `_`. Caso `.htaccess` não seja aceito, solicite configurações equivalentes.
`application/wasm` deve ser entregue corretamente. Os lotes são bytes binários,
transmitidos pelo PHP com tamanho, ETag e integridade verificados.

A resposta de `api/versao.php` não deve ser armazenada por proxies/CDN. Downloads
identificados por versão podem ser armazenados. A resposta do manifesto fixado
na compilação entra no cache offline do próprio aplicativo. A aplicação preserva
IndexedDB e preferências durante a atualização. Não exige COOP/COEP nesta configuração.
O mapa de fundo externo continua dependendo de conexão.

Para atualizar os dados, coloque o novo pacote científico na entrada privada,
recompile e publique o conjunto completo. O hash do manifesto e o build mudam,
e a aplicação prepara a nova versão. O backend não fornece edição administrativa.

Os servidores PHP de teste (`php -S`) não são destinados à produção; o servidor
Apache da UFV executará os arquivos PHP usando sua configuração habitual.

Referências do ambiente anunciado:
- https://www1.dti.ufv.br/hospedagem-de-sites/
- https://www1.dti.ufv.br/manual-para-usuarios-do-servico-de-hospedagem-de-sites/
